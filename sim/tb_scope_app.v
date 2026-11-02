`timescale 1ns / 1ps
//=============================================================================
// tb_scope_app.v -- 滚动状态来源 / 横轴连续缩放 / 长按快速重复（配置侧回归）
//
// 为了仿真快，CLK_HZ=50_000（1ms = 50 拍）：
//   去抖 20ms=1000 拍，长按 500ms=25000 拍，快速重复 30ms=1500 拍
//
// 判据:
//   1) SW5 拨上/拨下 -> scroll_en 与别名 roll 跟着变（电平语义）
//   2) 横轴缩放系数 S：复位 64(1:1)；短按 L/R 各走一小步，且严格按 S ± S/8
//   3) 长按 U -> 500ms 处垂直放大一档；短按/长按共用同一套动作
//   4) 长按 R -> 500ms 后每 30ms 再走一小步（4 个事件，S 按公式变化）
//   5) S 夹紧在 1..102：一直缩小停在 102，一直放大停在 1
//   6) 菜单 HSC 项 -> 与 L/R 完全相同的乘性规则（U 放大 / D 缩小）
//   7) 菜单 ROL 项 -> 短按 U 能翻转 scroll_en（而且不会被 SW5 每拍覆盖）
//   8) 串口 S0/S1 -> 同样能改 scroll_en，优先级最高
//   9) 关菜单后滚动状态不被 SW5 之外的东西覆盖
//  10) 菜单关闭时 SW2 = 通道选择: 拨下=CH0(sel_ch=0)、拨上=CH1(sel_ch=1)
//  11) 菜单关闭时 U/D 只改"选中通道"的垂直增益档 vstep，另一路完全不动
//      （vstep 为有符号 6bit：复位 0、每步 ±1、夹紧 ±30，每步 ×1.125）
//  12) 长按首拍 + 30ms 重复同样只作用选中通道（次数、夹紧都对）
//  13) SW7 拨上时 U/D 仍是移动基线（优先级高于通道选择）
//  14) 菜单打开时 SW2 仍是翻页（P0/P1），sel_ch 保持；关菜单后重新跟随 SW2
//  15) ch0_en/ch1_en 不受 SW2/U/D 影响
//  16) 菜单项 0/1 对通道使能的控制权没有丢
//=============================================================================
module tb_scope_app;

    localparam integer CLK_HZ   = 50_000;
    localparam integer DB_CNT   = (CLK_HZ/1000) * 20;    // 1000 拍 = 20ms 去抖
    localparam integer LONG_CNT = (CLK_HZ/1000) * 500;   // 25000 拍 = 500ms
    localparam integer FAST_CNT = (CLK_HZ/1000) * 30;    // 1500 拍 = 30ms

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [3:0]  key_n = 4'b1111;
    reg         gen_ena = 1'b1;
    reg         sw_menu = 1'b0;
    reg         sw_run  = 1'b0;      // SW1：拨下=运行（v1.5 起反转）
    reg         sw_page = 1'b0;
    reg         sw_roll = 1'b0;
    reg         sw_roll2 = 1'b1;   // SW5：拨上(1)=非滚动、拨下(0)=滚动
    reg         sw_move = 1'b0;    // SW7：1=U/D 移动基线（优先级高于通道选择）

    reg         ext_tb_we = 1'b0;    reg [15:0] ext_tb = 16'd0;
    reg         ext_run_we = 1'b0;   reg        ext_run = 1'b1;
    reg         ext_ten_we = 1'b0;   reg        ext_ten = 1'b0;
    reg         ext_lvl_we = 1'b0;   reg [9:0]  ext_lvl = 10'd512;
    reg         ext_edg_we = 1'b0;   reg        ext_edg = 1'b0;
    reg         ext_scr_we = 1'b0;   reg        ext_scr = 1'b0;
    reg         ext_tmode_we = 1'b0; reg [1:0]  ext_tmode = 2'd1;
    reg         ext_tsrc_we = 1'b0;  reg        ext_tsrc = 1'b0;
    reg         ext_pre_we = 1'b0;   reg [9:0]  ext_pre = 10'd0;
    reg         ext_hold_we = 1'b0;  reg [15:0] ext_hold = 16'd0;

    wire        cap_done = 1'b0;
    wire [1:0]  cap_state = 2'd0;

    wire [15:0] tb_div;
    wire        run, arm, trig_en, trig_src, trig_edge, scroll_en;
    wire [1:0]  trig_mode;
    wire [9:0]  trig_level, pre_trig;
    wire [15:0] holdoff;
    wire [3:0]  tb_idx;
    wire        page;
    wire [2:0]  state_o;
    wire        ev_short_o, ev_long_o;
    wire        ch0_en, ch1_en;
    wire        sel_ch;              // 选中通道 0=CH0 1=CH1（菜单关闭时由 SW2 选择）
    wire signed [5:0] vstep0, vstep1;   // 2026-11-02: Q12 连续增益档（±30），不再是右移档 2..7
    wire [3:0]  pos0, pos1;
    wire        roll;
    wire [6:0]  hscale;              // 横轴缩放系数 S(1..102)：自适应采样率下固定 102
    wire signed [9:0] hzoom10;       // 横轴缩放档 x10（每按一次 ±5，夹紧 ±300）
    wire signed [12:0] yoff;
    wire        menu_page;
    // 两套独立信号源参数（CH0/CH1）
    wire [1:0]  wave0, wave1;
    wire [2:0]  fsel0, fsel1;
    wire [1:0]  asel0, asel1;
    wire [3:0]  phase0, phase1;
    wire        menu_on;
    wire [3:0]  menu_sel;

    scope_app #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst(rst), .key_n(key_n), .gen_ena(gen_ena),
        .sw_menu(sw_menu), .sw_run(sw_run), .sw_page(sw_page),
        .sw_roll(sw_roll), .sw_roll2(sw_roll2), .sw_hzfree(1'b0), .sw_move(sw_move),
        .ext_tb_we(ext_tb_we),   .ext_tb(ext_tb),
        .ext_run_we(ext_run_we), .ext_run(ext_run),
        .ext_ten_we(ext_ten_we), .ext_ten(ext_ten),
        .ext_lvl_we(ext_lvl_we), .ext_lvl(ext_lvl),
        .ext_edg_we(ext_edg_we), .ext_edg(ext_edg),
        .ext_scr_we(ext_scr_we), .ext_scr(ext_scr),
        .ext_tmode_we(ext_tmode_we), .ext_tmode(ext_tmode),
        .ext_tsrc_we(ext_tsrc_we),   .ext_tsrc(ext_tsrc),
        .ext_pre_we(ext_pre_we),     .ext_pre(ext_pre),
        .ext_hold_we(ext_hold_we),   .ext_hold(ext_hold),
        .cap_done(cap_done), .cap_state(cap_state),
        .tb_div(tb_div), .run(run), .arm(arm),
        .trig_en(trig_en), .trig_mode(trig_mode), .trig_src(trig_src),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .scroll_en(scroll_en), .tb_idx(tb_idx), .page(page), .state_o(state_o),
        .ev_short_o(ev_short_o), .ev_long_o(ev_long_o),
        .ch0_en(ch0_en), .ch1_en(ch1_en), .sel_ch(sel_ch),
        .vstep0(vstep0), .vstep1(vstep1), .pos0(pos0), .pos1(pos1),
        .roll(roll), .hscale(hscale), .hzoom10(hzoom10), .yoff(yoff), .menu_page(menu_page),
        .wave0(wave0), .fsel0(fsel0), .asel0(asel0), .phase0(phase0),
        .wave1(wave1), .fsel1(fsel1), .asel1(asel1), .phase1(phase1),
        .menu_on(menu_on), .menu_sel(menu_sel)
    );

    always #5 clk = ~clk;

    //------------------------------------------------------------------
    // 参考模型：S <- S ± S/8（S/8=0 时步长保底 1），夹紧 1..102
    //   与 RTL 的 hsc_in / hsc_out 逐条对应
    //------------------------------------------------------------------
    function [6:0] ref_in;
        input [6:0] s;
        integer d;
        begin
            d = s / 8;
            if (d == 0) d = 1;
            ref_in = (s > d) ? (s - d) : 7'd1;
        end
    endfunction

    function [6:0] ref_out;
        input [6:0] s;
        integer d;
        begin
            d = s / 8;
            if (d == 0) d = 1;
            ref_out = ((s + d) > 102) ? 7'd102 : (s + d);
        end
    endfunction

    integer errors = 0;
    integer i;
    reg [6:0] s_exp;

    // 短按：按住 30ms(>20ms 去抖)，再松开
    task press_key;
        input integer idx;
        begin
            key_n[idx] = 1'b0;
            repeat (1500) @(posedge clk);
            key_n[idx] = 1'b1;
            repeat (900) @(posedge clk);
        end
    endtask

    // 长按：按住指定拍数后松开
    task hold_key;
        input integer idx;
        input integer n;
        begin
            key_n[idx] = 1'b0;
            repeat (n) @(posedge clk);
            key_n[idx] = 1'b1;
            repeat (900) @(posedge clk);
        end
    endtask

    initial begin
        $display("[tb_scope_app] 滚动状态来源 / 横轴连续缩放 / 长按快速重复");
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ---------- 0) 默认值 ----------
        $display("  默认: scroll_en=%b roll=%b vstep0=%0d S=%0d menu_on=%b",
                 scroll_en, roll, vstep0, hscale, menu_on);
        // 复位值：vstep 两路都应回到 0（Q12 连续增益的中点 = 1:1）
        if ((vstep0 !== 6'sd0) || (vstep1 !== 6'sd0)) begin
            errors=errors+1; $display("  FAIL 复位后 vstep 应为 0/0"); end
        if ((scroll_en !== 1'b0) || (roll !== 1'b0)) begin
            errors=errors+1; $display("  FAIL 复位后滚动状态应为 0"); end
        if (hscale !== 7'd102) begin
            errors=errors+1; $display("  FAIL 复位后 hscale 应为 102（自适应采样率，一屏用满缓冲）"); end

        // 两套信号源参数：CH0=正弦/50Hz/满幅/0 度，CH1=方波/50Hz/半幅/0 度
        $display("  默认: CH0 WAV=%0d FRE=%0d ATT=%0d PHA=%0d / CH1 WAV=%0d FRE=%0d ATT=%0d PHA=%0d",
                 wave0, fsel0, asel0, phase0, wave1, fsel1, asel1, phase1);
        if ((wave0 !== 2'd0) || (fsel0 !== 3'd3) || (asel0 !== 2'd0) || (phase0 !== 4'd0)) begin
            errors=errors+1; $display("  FAIL CH0 信号源默认参数不对"); end
        if ((wave1 !== 2'd1) || (fsel1 !== 3'd3) || (asel1 !== 2'd1) || (phase1 !== 4'd0)) begin
            errors=errors+1; $display("  FAIL CH1 信号源默认参数不对（两路应各自独立）"); end

        // ---------- 1) SW5 滚动开关（拨上=非滚动、拨下=滚动）----------
        sw_roll2 = 1'b0;                    // 拨下 = 滚动
        repeat (10) @(posedge clk);
        $display("  1) SW5 拨下: scroll_en=%b roll=%b (expect 1/1)", scroll_en, roll);
        if ((scroll_en !== 1'b1) || (roll !== 1'b1)) begin
            errors=errors+1; $display("  FAIL SW5 拨下没有进入滚动"); end

        sw_roll2 = 1'b1;                    // 拨上 = 非滚动
        repeat (10) @(posedge clk);
        $display("  1) SW5 拨上: scroll_en=%b roll=%b (expect 0/0)", scroll_en, roll);
        if ((scroll_en !== 1'b0) || (roll !== 1'b0)) begin
            errors=errors+1; $display("  FAIL SW5 拨上没有退出滚动"); end

        // ---------- 2) 短按 L/R：时基档 tb_idx ±1 ----------
        //   [2026-11-02 语义变更] 横轴缩放改成"自适应采样率"：hscale 固定 HSC_MAX(102)，
        //   L/R 不再改 hscale，而是改 tb_idx（采样率档），每按一次 ±1 档并记账 ±5。
        //   tb_idx: 0 最快(tb_div=49999) .. 15 最慢(tb_div=0)。
        $display("  2) 复位: hscale=%0d (expect 102=固定) tb_idx=%0d (expect 0)",
                 hscale, tb_idx);
        if (hscale !== 7'd102) begin errors=errors+1; $display("  FAIL hscale 应固定 102"); end
        if (tb_idx !== 4'd0)  begin errors=errors+1; $display("  FAIL 复位 tb_idx 应为 0"); end

        press_key(1);      // L = 放大 -> tb_idx+1
        $display("  2) 短按 L: tb_idx=%0d (expect 1) tb_div=%0d (expect 24999)", tb_idx, tb_div);
        if (tb_idx !== 4'd1) begin errors=errors+1; $display("  FAIL 短按 L 没进一档"); end
        if (tb_div !== 16'd24999) begin errors=errors+1; $display("  FAIL tb_div 没跟着换表"); end

        press_key(1);      // L 再一档 -> 2
        if (tb_idx !== 4'd2) begin errors=errors+1; $display("  FAIL 短按 L 第二次没累加"); end

        press_key(0);      // R = 缩小 -> 回 1
        $display("  2) 短按 R: tb_idx=%0d (expect 1) tb_div=%0d (expect 24999)", tb_idx, tb_div);
        if (tb_idx !== 4'd1) begin errors=errors+1; $display("  FAIL 短按 R 没退一档"); end
        if (tb_div !== 16'd24999) begin errors=errors+1; $display("  FAIL tb_div 没跟着退回"); end

        // ---------- 3) 长按 U：500ms 处垂直放大一档 ----------
        hold_key(3, DB_CNT + LONG_CNT + 500);
        $display("  3) 长按 U %0d 拍: vstep0=%0d (expect 1，长按一档)",
                 DB_CNT + LONG_CNT + 500, vstep0);
        if (vstep0 !== 6'sd1) begin errors=errors+1; $display("  FAIL 长按 U 没有动作"); end

        // ---------- 4) 长按 R：500ms 后每 30ms 一档 ----------
        //   事件：ev_long(500ms) + 3 个 ev_repeat = 4 次；从 tb_idx=1 起连退
        //   4 档，但 tb_idx 有 0 下界保护，所以最终停在 0。
        hold_key(0, DB_CNT + LONG_CNT + 3*FAST_CNT + 500);
        $display("  4) 长按 R(1+3 次事件): tb_idx=%0d (expect 0，退到 0 停住)", tb_idx);
        if (tb_idx !== 4'd0) begin
            errors=errors+1; $display("  FAIL 长按 R 没有连续步进或没在 0 停住"); end

        // ---------- 5) tb_idx 夹紧 0..15 + hzoom10 夹紧 ±300 ----------
        for (i = 0; i < 20; i = i + 1) press_key(1);    // L 一直放大 -> 顶到 15
        $display("  5) 连按 L 20 次: tb_idx=%0d (expect 15 上限) tb_div=%0d (expect 0)",
                 tb_idx, tb_div);
        if (tb_idx !== 4'd15) begin errors=errors+1; $display("  FAIL tb_idx 上限没有夹紧"); end
        if (tb_div !== 16'd0) begin errors=errors+1; $display("  FAIL 顶档 tb_div 应为 0"); end
        press_key(1);       // 再按不应回绕到 0
        if (tb_idx !== 4'd15) begin errors=errors+1; $display("  FAIL 已到 15 还能继续进"); end

        for (i = 0; i < 20; i = i + 1) press_key(0);    // R 一直缩小 -> 回到 0
        $display("  5) 连按 R 20 次: tb_idx=%0d (expect 0 下限)", tb_idx);
        if (tb_idx !== 4'd0) begin errors=errors+1; $display("  FAIL tb_idx 下限没有夹紧"); end
        press_key(0);
        if (tb_idx !== 4'd0) begin errors=errors+1; $display("  FAIL 已到 0 还能继续退"); end

        //   hzoom10 记账：上面共按了很多次，夹在 ±300（=±30.0 档）。
        $display("  5) hzoom10=%0d (expect 在 -300..300 之间)", hzoom10);
        if ((hzoom10 > 10'sd300) || (hzoom10 < -10'sd300)) begin
            errors=errors+1; $display("  FAIL hzoom10 没有夹紧"); end

        // 把时基拉回 1:1 附近，让 HSC 的乘性步进能看出真实变化（而不是 1/2 的边界值）
        // 死代码已删：hscale 固定 102，这个等待条件永不成立

        // ---------- 6) 菜单 HSC 项：与 L/R 同一规则 ----------
        sw_menu = 1'b1;
        repeat (10) @(posedge clk);
        if (menu_on !== 1'b1) begin errors=errors+1; $display("  FAIL SW0 没有打开菜单"); end
        for (i = 0; i < 6; i = i + 1) press_key(0);    // 光标 0 -> 6(HSC)
        $display("  6) 菜单光标: menu_sel=%0d (expect 6=HSC)", menu_sel);
        if (menu_sel !== 4'd6) begin errors=errors+1; $display("  FAIL 菜单光标没有到 HSC"); end

        s_exp = ref_in(hscale);
        press_key(3);      // U 短按 = 放大
        $display("  6) 菜单 HSC U: S=%0d (expect %0d)", hscale, s_exp);
        if (hscale !== s_exp) begin errors=errors+1; $display("  FAIL 菜单 HSC 的 U 没有按乘性规则放大"); end
        s_exp = ref_out(s_exp);
        press_key(2);      // D 短按 = 缩小
        $display("  6) 菜单 HSC D: S=%0d (expect %0d)", hscale, s_exp);
        if (hscale !== s_exp) begin errors=errors+1; $display("  FAIL 菜单 HSC 的 D 没有按乘性规则缩小"); end

        // ---------- 7) 菜单 ROL 项 ----------
        press_key(0); press_key(0);                    // 光标 6 -> 8(ROL)
        $display("  7) 菜单光标: menu_sel=%0d (expect 8)", menu_sel);
        if (menu_sel !== 4'd8) begin errors=errors+1; $display("  FAIL 菜单光标没有到 ROL 项"); end
        if (scroll_en !== 1'b0) begin
            errors=errors+1; $display("  FAIL 打开菜单不该改滚动状态"); end

        press_key(3);      // U 短按 = 翻转 ROL
        $display("  7) 菜单 ROL 第一次: scroll_en=%b roll=%b (expect 1/1)", scroll_en, roll);
        if ((scroll_en !== 1'b1) || (roll !== 1'b1)) begin
            errors=errors+1; $display("  FAIL 菜单 ROL 改不动滚动状态"); end
        press_key(3);
        $display("  7) 菜单 ROL 第二次: scroll_en=%b (expect 0)", scroll_en);
        if (scroll_en !== 1'b0) begin errors=errors+1; $display("  FAIL 菜单 ROL 第二次不生效"); end
        press_key(3);
        if (scroll_en !== 1'b1) begin errors=errors+1; $display("  FAIL 菜单 ROL 第三次不生效"); end

        // ---------- 8) 串口 S 命令（优先级最高）----------
        @(posedge clk); ext_scr_we <= 1'b1; ext_scr <= 1'b0;
        @(posedge clk); ext_scr_we <= 1'b0;
        repeat (5) @(posedge clk);
        $display("  8) 串口 S0: scroll_en=%b (expect 0)", scroll_en);
        if (scroll_en !== 1'b0) begin errors=errors+1; $display("  FAIL 串口 S0 没生效"); end

        @(posedge clk); ext_scr_we <= 1'b1; ext_scr <= 1'b1;
        @(posedge clk); ext_scr_we <= 1'b0;
        repeat (5) @(posedge clk);
        $display("  8) 串口 S1: scroll_en=%b roll=%b (expect 1/1)", scroll_en, roll);
        if ((scroll_en !== 1'b1) || (roll !== 1'b1)) begin
            errors=errors+1; $display("  FAIL 串口 S1 没生效"); end

        // 关菜单后状态保持不变（SW5 没动过，不该被覆盖）
        sw_menu = 1'b0;
        repeat (20) @(posedge clk);
        $display("  9) 关菜单后: menu_on=%b scroll_en=%b (expect 0/1)", menu_on, scroll_en);
        if (menu_on !== 1'b0)  begin errors=errors+1; $display("  FAIL 菜单没关上"); end
        if (scroll_en !== 1'b1) begin
            errors=errors+1; $display("  FAIL 关菜单后滚动状态被覆盖了"); end

        // ---------- 10) 菜单关闭时 SW2 = 通道选择 ----------
        //   拨下=CH0(sel_ch=0)、拨上=CH1(sel_ch=1)，电平语义，菜单关闭时跟随。
        if (sel_ch !== 1'b0) begin
            errors=errors+1; $display("  FAIL 复位后默认应选中 CH0"); end
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        $display("  10) SW2 拨上(菜单关): sel_ch=%b (expect 1=CH1)", sel_ch);
        if (sel_ch !== 1'b1) begin errors=errors+1; $display("  FAIL SW2 拨上没有选中 CH1"); end

        sw_page = 1'b0;
        repeat (10) @(posedge clk);
        $display("  10) SW2 拨下(菜单关): sel_ch=%b (expect 0=CH0)", sel_ch);
        if (sel_ch !== 1'b0) begin errors=errors+1; $display("  FAIL SW2 拨下没有选中 CH0"); end

        // ---------- 11) 菜单关闭时 U/D 只改"选中通道"的垂直增益档 ----------
        //   新语义（2026-11-02 Q12 连续增益）：vstep 有符号 6bit，复位 0，
        //   U=+1（放大 1.125x）、D=-1（缩小），两路各自夹紧在 ±30。
        //   进入本步时 vstep0=1（第 3 步长按改过）、vstep1=0（复位值）。
        press_key(3);      // U = 放大 CH0
        $display("  11) sel_ch=0 短按 U: vstep0=%0d vstep1=%0d (expect 2/0)", vstep0, vstep1);
        if (vstep0 !== 6'sd2) begin errors=errors+1; $display("  FAIL CH0 档位没有放大"); end
        if (vstep1 !== 6'sd0) begin errors=errors+1; $display("  FAIL 选中 CH0 时改到了 CH1"); end

        press_key(3);      // 再 +1 -> 3（这里不再夹紧，夹紧留到第 12 步做满量程验证）
        $display("  11) sel_ch=0 再按 U: vstep0=%0d (expect 3)", vstep0);
        if (vstep0 !== 6'sd3) begin errors=errors+1; $display("  FAIL CH0 连续两档没有累加"); end

        press_key(2);      // D = 缩小 CH0 -> 2
        $display("  11) sel_ch=0 短按 D: vstep0=%0d vstep1=%0d (expect 2/0)", vstep0, vstep1);
        if (vstep0 !== 6'sd2) begin errors=errors+1; $display("  FAIL CH0 档位没有缩小"); end
        if (vstep1 !== 6'sd0) begin errors=errors+1; $display("  FAIL 选中 CH0 时 D 改到了 CH1"); end

        // 切到 CH1（SW2 拨上），U/D 应只改 vstep1
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        if (sel_ch !== 1'b1) begin errors=errors+1; $display("  FAIL 切不到 CH1"); end
        press_key(2); press_key(2);        // D 两次：vstep1 0 -> -2
        press_key(3);                      // U 一次：-2 -> -1
        $display("  11) sel_ch=1 短按 D,D,U: vstep1=%0d vstep0=%0d (expect -1/2)", vstep1, vstep0);
        if (vstep1 !== -6'sd1) begin errors=errors+1; $display("  FAIL CH1 档位没有按 D/D/U 变化"); end
        if (vstep0 !== 6'sd2) begin errors=errors+1; $display("  FAIL 选中 CH1 时改到了 CH0"); end

        // ---------- 12) 长按首拍 + 30ms 重复也只作用选中通道 ----------
        //   先把 CH1 按到下限 -30（顺带验证 ±30 夹紧），再长按 U：
        //   ev_long 1 次 + ev_repeat 3 次 = 4 步，-30 -> -26；CH0 完全不动。
        for (i = 0; i < 32; i = i + 1) press_key(2);   // D 连按：-1 -> -30 后夹住
        $display("  12) 连按 D 32 次: vstep1=%0d (expect -30 下限)", vstep1);
        if (vstep1 !== -6'sd30) begin errors=errors+1; $display("  FAIL vstep1 下限没有夹紧"); end

        hold_key(3, DB_CNT + LONG_CNT + 3*FAST_CNT + 500);
        $display("  12) 长按 U(1+3 次事件): vstep1=%0d vstep0=%0d (expect -26/2)", vstep1, vstep0);
        if (vstep1 !== -6'sd26) begin
            errors=errors+1; $display("  FAIL 长按首拍/重复没有连续作用到选中通道"); end
        if (vstep0 !== 6'sd2) begin errors=errors+1; $display("  FAIL 长按误改了 CH0 的档位"); end

        //  顺带验证上限 +30：切回 CH0，连按 U 直到顶住
        sw_page = 1'b0;
        repeat (10) @(posedge clk);
        for (i = 0; i < 32; i = i + 1) press_key(3);
        $display("  12) 连按 U 32 次(CH0): vstep0=%0d (expect 30 上限)", vstep0);
        if (vstep0 !== 6'sd30) begin errors=errors+1; $display("  FAIL vstep0 上限没有夹紧"); end
        //  回落到 2，方便后续步骤的期望值稳定
        for (i = 0; i < 28; i = i + 1) press_key(2);
        //  恢复 SW2=CH1（第 11 步切到 CH1 的状态），否则第 14 步"菜单翻页/sel_ch"前提不成立
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        if (sel_ch !== 1'b1) begin errors=errors+1; $display("  FAIL 恢复不到 CH1 选中"); end

        // ---------- 13) SW7 拨上：U/D 仍是移动基线（优先级高于通道选择）----------
        sw_move = 1'b1;
        press_key(3);      // U：基线向上 16 像素
        $display("  13) SW7=1 短按 U: yoff=%0d vstep0=%0d vstep1=%0d (expect -16/2/-26)",
                 yoff, vstep0, vstep1);
        if (yoff !== -13'sd16) begin errors=errors+1; $display("  FAIL SW7 没有移动基线"); end
        if ((vstep0 !== 6'sd2) || (vstep1 !== -6'sd26)) begin
            errors=errors+1; $display("  FAIL SW7 打开时 U/D 仍然改了档位"); end
        sw_move = 1'b0;

        // ---------- 14) 菜单打开：SW2 仍是翻页，sel_ch 保持 ----------
        //   此时 SW2 拨上、sel_ch=1（第 11 步切到 CH1）。
        sw_menu = 1'b1;
        repeat (10) @(posedge clk);
        $display("  14) 打开菜单: menu_on=%b menu_page=%b sel_ch=%b (expect 1/1/1)",
                 menu_on, menu_page, sel_ch);
        if (menu_on !== 1'b1) begin errors=errors+1; $display("  FAIL SW0 没有打开菜单"); end
        if (menu_page !== 1'b1) begin errors=errors+1; $display("  FAIL SW2 拨上应显示 P1"); end

        sw_page = 1'b0;    // 菜单里用 SW2 翻到 P0
        repeat (10) @(posedge clk);
        $display("  14) 菜单里 SW2 拨下: menu_page=%b sel_ch=%b (expect 0/1)", menu_page, sel_ch);
        if (menu_page !== 1'b0) begin errors=errors+1; $display("  FAIL SW2 没能翻到 P0"); end
        if (sel_ch !== 1'b1) begin
            errors=errors+1; $display("  FAIL 菜单打开时 sel_ch 被 SW2 改掉了"); end

        sw_page = 1'b1;    // 再翻回 P1，sel_ch 仍应保持
        repeat (10) @(posedge clk);
        $display("  14) 菜单里 SW2 拨上: menu_page=%b sel_ch=%b (expect 1/1)", menu_page, sel_ch);
        if ((menu_page !== 1'b1) || (sel_ch !== 1'b1)) begin
            errors=errors+1; $display("  FAIL 菜单打开时 SW2 只应翻页"); end

        // 关菜单 + SW2 拨下 -> 通道选择重新跟随 SW2
        sw_page = 1'b0;
        sw_menu = 1'b0;
        repeat (10) @(posedge clk);
        $display("  14) 关菜单 SW2 拨下: menu_on=%b sel_ch=%b (expect 0/0)", menu_on, sel_ch);
        if (menu_on !== 1'b0) begin errors=errors+1; $display("  FAIL 菜单没关上"); end
        if (sel_ch !== 1'b0) begin
            errors=errors+1; $display("  FAIL 关菜单后 sel_ch 没有重新跟随 SW2"); end

        // ---------- 15) 通道显示使能不受 SW2/U/D 影响 ----------
        //   ch0_en/ch1_en 只由菜单项 0/1 控制，通道选择和档位按键都不许碰。
        $display("  15) ch0_en=%b ch1_en=%b (expect 1/1)", ch0_en, ch1_en);
        if ((ch0_en !== 1'b1) || (ch1_en !== 1'b1)) begin
            errors=errors+1; $display("  FAIL 通道显示使能被通道选择/档位按键改掉了"); end

        // ---------- 16) 菜单项 0/1 对通道使能的控制权没有丢 ----------
        //   打开菜单、光标移到 0 号项（CH0 开关），U 键翻转 ch0_en：
        //   证明 sel_ch 只决定"U/D 改哪一路的档位"，没有夺走菜单对使能的控制。
        sw_menu = 1'b1;
        repeat (10) @(posedge clk);
        while (menu_sel != 4'd0) press_key(0);      // R：光标移到 0 号项
        press_key(3);                               // U：CH0 关
        $display("  16) 菜单项0 第一次 U: ch0_en=%b (expect 0)", ch0_en);
        if (ch0_en !== 1'b0) begin errors=errors+1; $display("  FAIL 菜单项 0 不能关 CH0"); end
        if (ch1_en !== 1'b1) begin errors=errors+1; $display("  FAIL 菜单项 0 误改了 CH1"); end
        press_key(3);                               // U：CH0 开回来
        $display("  16) 菜单项0 第二次 U: ch0_en=%b (expect 1)", ch0_en);
        if (ch0_en !== 1'b1) begin errors=errors+1; $display("  FAIL 菜单项 0 不能开 CH0"); end
        sw_menu = 1'b0;
        repeat (10) @(posedge clk);

        // ---------- 17) 菜单 P1：CH0/CH1 各自一套参数，共 8 项 ----------
        //   SW0 拨上 + SW2 拨上 = P1 信号源页；光标范围 0..7（P0 才是 0..8）。
        //   每一项 U/D 只改它自己那一路的参数，另一路必须纹丝不动。
        //   进入本步时：CH0 为正弦/50Hz/满幅/0 度，CH1 为方波/50Hz/半幅/0 度
        //   （前面的 0~16 步都没碰过这 8 个寄存器）。
        sw_menu = 1'b1;
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        $display("  17) 打开菜单 P1: menu_on=%b menu_page=%b menu_sel=%0d (expect 1/1/0)",
                 menu_on, menu_page, menu_sel);
        if ((menu_on !== 1'b1) || (menu_page !== 1'b1)) begin
            errors=errors+1; $display("  FAIL 没有进入 P1 信号源页"); end

        // 光标回绕：L 从 0 回到本页最后一项 7（若还是 P0 的 8 就是没扩页）
        press_key(1);
        $display("  17) P1 光标 L: menu_sel=%0d (expect 7)", menu_sel);
        if (menu_sel !== 4'd7) begin errors=errors+1; $display("  FAIL P1 光标回绕不是 7"); end
        press_key(0);
        $display("  17) P1 光标 R: menu_sel=%0d (expect 0)", menu_sel);
        if (menu_sel !== 4'd0) begin errors=errors+1; $display("  FAIL P1 光标回绕不是 0"); end

        // 0) CH0 WAV：0 -> 1 -> 2（CH1 的 wave1 必须还是 1）
        press_key(3); press_key(3);
        $display("  17) P1 项0 CH0 WAV U,U: wave0=%0d wave1=%0d (expect 2/1)", wave0, wave1);
        if ((wave0 !== 2'd2) || (wave1 !== 2'd1)) begin
            errors=errors+1; $display("  FAIL CH0 WAV 调整不对或串到了 CH1"); end

        // 1) CH0 FRE：3 -> 4
        press_key(0);
        press_key(3);
        $display("  17) P1 项1 CH0 FRE U: fsel0=%0d fsel1=%0d (expect 4/3)", fsel0, fsel1);
        if ((fsel0 !== 3'd4) || (fsel1 !== 3'd3)) begin
            errors=errors+1; $display("  FAIL CH0 FRE 调整不对或串到了 CH1"); end

        // 2) CH0 ATT：0 -> 1 -> 2
        press_key(0);
        press_key(3); press_key(3);
        $display("  17) P1 项2 CH0 ATT U,U: asel0=%0d asel1=%0d (expect 2/1)", asel0, asel1);
        if ((asel0 !== 2'd2) || (asel1 !== 2'd1)) begin
            errors=errors+1; $display("  FAIL CH0 ATT 调整不对或串到了 CH1"); end

        // 3) CH0 PHA：0 -> 1
        press_key(0);
        press_key(3);
        $display("  17) P1 项3 CH0 PHA U: phase0=%0d phase1=%0d (expect 1/0)", phase0, phase1);
        if ((phase0 !== 4'd1) || (phase1 !== 4'd0)) begin
            errors=errors+1; $display("  FAIL CH0 PHA 调整不对或串到了 CH1"); end

        // 4) CH1 WAV：1 -> 2 -> 3 -> 0（顺带验证 3 回绕到 0），CH0 的 2 不动
        press_key(0);
        press_key(3); press_key(3); press_key(3);
        $display("  17) P1 项4 CH1 WAV U,U,U: wave1=%0d wave0=%0d (expect 0/2)", wave1, wave0);
        if ((wave1 !== 2'd0) || (wave0 !== 2'd2)) begin
            errors=errors+1; $display("  FAIL CH1 WAV 调整/回绕不对，或串到了 CH0"); end

        // 5) CH1 FRE：3 -> 2（D 键），CH0 的 4 不动
        press_key(0);
        press_key(2);
        $display("  17) P1 项5 CH1 FRE D: fsel1=%0d fsel0=%0d (expect 2/4)", fsel1, fsel0);
        if ((fsel1 !== 3'd2) || (fsel0 !== 3'd4)) begin
            errors=errors+1; $display("  FAIL CH1 FRE 调整不对或串到了 CH0"); end

        // 6) CH1 ATT：1 -> 0（D 键），CH0 的 2 不动
        press_key(0);
        press_key(2);
        $display("  17) P1 项6 CH1 ATT D: asel1=%0d asel0=%0d (expect 0/2)", asel1, asel0);
        if ((asel1 !== 2'd0) || (asel0 !== 2'd2)) begin
            errors=errors+1; $display("  FAIL CH1 ATT 调整不对或串到了 CH0"); end

        // 7) CH1 PHA：0 -> 9（D 键，0 回绕到 9），CH0 的 1 不动
        press_key(0);
        press_key(2);
        $display("  17) P1 项7 CH1 PHA D: phase1=%0d phase0=%0d (expect 9/1)", phase1, phase0);
        if ((phase1 !== 4'd9) || (phase0 !== 4'd1)) begin
            errors=errors+1; $display("  FAIL CH1 PHA 调整/回绕不对，或串到了 CH0"); end

        // 光标在 7 再按 R 应回到 0（不是 8）
        press_key(0);
        $display("  17) P1 光标 7 再 R: menu_sel=%0d (expect 0)", menu_sel);
        if (menu_sel !== 4'd0) begin errors=errors+1; $display("  FAIL P1 光标 7->0 回绕不对"); end

        // ---------- 18) AD/DA 模式（gen_ena=0）：P1 不可用，光标范围回到 0..8 ----------
        sw_menu = 1'b0;
        sw_page = 1'b0;
        repeat (10) @(posedge clk);
        gen_ena = 1'b0;                     // AD/DA 模式：内置信号源整体失效
        sw_menu = 1'b1;
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        $display("  18) gen_ena=0 打开菜单 SW2 拨上: menu_on=%b menu_page=%b (expect 1/0)",
                 menu_on, menu_page);
        if (menu_on !== 1'b1) begin errors=errors+1; $display("  FAIL 菜单没打开"); end
        if (menu_page !== 1'b0) begin
            errors=errors+1; $display("  FAIL AD/DA 模式下不该能进 P1"); end
        press_key(1);                       // L：从 0 回绕到 P0 最后一项 8
        $display("  18) AD/DA 模式光标 L: menu_sel=%0d (expect 8)", menu_sel);
        if (menu_sel !== 4'd8) begin
            errors=errors+1; $display("  FAIL AD/DA 模式光标范围不是 0..8"); end
        $display("  18) 信号源参数: CH0 WAV=%0d FRE=%0d ATT=%0d PHA=%0d / CH1 WAV=%0d FRE=%0d ATT=%0d PHA=%0d",
                 wave0, fsel0, asel0, phase0, wave1, fsel1, asel1, phase1);
        if ((wave0 !== 2'd2) || (fsel0 !== 3'd4) || (asel0 !== 2'd2) || (phase0 !== 4'd1) ||
            (wave1 !== 2'd0) || (fsel1 !== 3'd2) || (asel1 !== 2'd0) || (phase1 !== 4'd9)) begin
            errors=errors+1; $display("  FAIL AD/DA 模式下信号源参数被改动了"); end
        sw_menu = 1'b0;
        sw_page = 1'b0;
        gen_ena = 1'b1;
        repeat (10) @(posedge clk);

        if (errors == 0) $display("[tb_scope_app] PASS");
        else             $display("[tb_scope_app] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
