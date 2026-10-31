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
    wire [2:0]  vs0, vs1;
    wire [3:0]  pos0, pos1;
    wire        roll;
    wire [6:0]  hscale;              // 横轴缩放系数 S(1..102)
    wire signed [12:0] yoff;
    wire        menu_page;
    wire [3:0]  phase_idx;
    wire [1:0]  wave;
    wire [2:0]  fsel;
    wire [1:0]  asel;
    wire        menu_on;
    wire [3:0]  menu_sel;

    scope_app #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst(rst), .key_n(key_n), .gen_ena(gen_ena),
        .sw_menu(sw_menu), .sw_run(sw_run), .sw_page(sw_page),
        .sw_roll(sw_roll), .sw_roll2(sw_roll2), .sw_hzfree(1'b0), .sw_move(1'b0),
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
        .ch0_en(ch0_en), .ch1_en(ch1_en),
        .vs0(vs0), .vs1(vs1), .pos0(pos0), .pos1(pos1),
        .roll(roll), .hscale(hscale), .yoff(yoff), .menu_page(menu_page), .phase_idx(phase_idx),
        .wave(wave), .fsel(fsel), .asel(asel),
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
        $display("  默认: scroll_en=%b roll=%b vs0=%0d S=%0d menu_on=%b",
                 scroll_en, roll, vs0, hscale, menu_on);
        if ((scroll_en !== 1'b0) || (roll !== 1'b0)) begin
            errors=errors+1; $display("  FAIL 复位后滚动状态应为 0"); end
        if (hscale !== 7'd64) begin
            errors=errors+1; $display("  FAIL 复位后 S 应为 64(1:1)"); end

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

        // ---------- 2) 短按 L/R：乘性小步（约 ±1/8）----------
        s_exp = ref_out(7'd64);
        press_key(0);      // R 短按 = 缩小
        $display("  2) 短按 R: S=%0d (expect %0d = 64+64/8)", hscale, s_exp);
        if (hscale !== s_exp) begin errors=errors+1; $display("  FAIL 短按 R 的乘性步进"); end

        s_exp = ref_in(s_exp);
        press_key(1);      // L 短按 = 放大
        $display("  2) 短按 L: S=%0d (expect %0d)", hscale, s_exp);
        if (hscale !== s_exp) begin errors=errors+1; $display("  FAIL 短按 L 的乘性步进"); end

        s_exp = ref_out(s_exp);
        press_key(0);
        if (hscale !== s_exp) begin errors=errors+1; $display("  FAIL 第二次 R 的乘性步进"); end
        // 只是短按一次走一步：不能出现"一次跳好几档"

        // ---------- 3) 长按 U：500ms 处垂直放大一档 ----------
        hold_key(3, DB_CNT + LONG_CNT + 500);
        $display("  3) 长按 U %0d 拍: vs0=%0d (expect 3，长按一档)",
                 DB_CNT + LONG_CNT + 500, vs0);
        if (vs0 !== 3'd3) begin errors=errors+1; $display("  FAIL 长按 U 没有动作"); end

        // ---------- 4) 长按 R：500ms 后每 30ms 一小步 ----------
        //   事件：ev_long(500ms) + 3 个 ev_repeat(530/560/590ms) = 4 次缩小
        s_exp = hscale;
        for (i = 0; i < 4; i = i + 1) s_exp = ref_out(s_exp);
        hold_key(0, DB_CNT + LONG_CNT + 3*FAST_CNT + 500);
        $display("  4) 长按 R %0d 拍: S=%0d (expect %0d，4 次乘性小步)",
                 DB_CNT + LONG_CNT + 3*FAST_CNT + 500, hscale, s_exp);
        if (hscale !== s_exp) begin
            errors=errors+1; $display("  FAIL 长按 R 没有连续步进（台阶/次数不对）"); end

        // ---------- 5) S 夹紧 1..102 ----------
        for (i = 0; i < 12; i = i + 1) press_key(0);    // 一直缩小
        $display("  5) 连按 R 12 次: S=%0d (expect 102 上限)", hscale);
        if (hscale !== 7'd102) begin errors=errors+1; $display("  FAIL S 上限没有夹紧"); end
        press_key(0);
        if (hscale !== 7'd102) begin errors=errors+1; $display("  FAIL 已到 102 还能继续涨"); end

        for (i = 0; i < 40; i = i + 1) press_key(1);    // 一直放大
        $display("  5) 连按 L 40 次: S=%0d (expect 1 下限)", hscale);
        if (hscale !== 7'd1) begin errors=errors+1; $display("  FAIL S 下限没有夹紧"); end
        press_key(1);
        if (hscale !== 7'd1) begin errors=errors+1; $display("  FAIL 已到 1 还能继续降"); end
        press_key(0);
        if (hscale !== 7'd2) begin errors=errors+1; $display("  FAIL 从 1 往回按没有反应"); end

        // 先把 S 拉回 1:1 附近，让 HSC 的乘性步进能看出真实变化（而不是 1/2 的边界值）
        while (hscale < 7'd60) press_key(0);

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

        if (errors == 0) $display("[tb_scope_app] PASS");
        else             $display("[tb_scope_app] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
