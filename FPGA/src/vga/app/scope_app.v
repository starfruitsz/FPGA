//==============================================================================
// 层: 应用(配置)  文件: app/scope_app.v   [v3: 4 键菜单 + 通道/垂直档位/垂直位置]
// 功能:
//   1) 寄存器: 时基 tb_div、触发使能/模式/源/电平/边沿、预触发、保持时间、滚动
//   2) 会话状态: 0=STOP 1=IDLE 2=ARMED/FILL 3=DONE（供文本层显示）
//   3) 翻页: page 每 2 秒翻转，文本层据此切换测量显示页
//   4) 重触发: normal 模式捕获完成(cap_done)后自动 arm；single 等外部 arm
//   5) 串口下发的写优先于按键
//   6) 4 键操作（L/R/U/D，低有效）：
//        正常模式:  U=垂直放大  D=垂直缩小  L=水平放大  R=水平缩小
//                  短按走一小步；长按 500ms 后进入连续模式，每 30ms 走
//                  一小步（scope_ui 的 FAST_MS），按住就是丝滑连续变化
//        菜单模式:  L/R=移动光标  U/D=调整当前项（长按 U 仍是退出菜单，不重复）
//   7) 横轴缩放是连续的：7bit 系数 S(1..102)，顶层按 pxz=(px*S)>>6 取采样地址。
//      S=64 为 1:1，S 越小放大越多，S=102 约等于"适应全屏"（1024 点缓冲的上限）。
//      L/R 与菜单 HSC 项都按乘性规则 S <- S ± S/8 调整（夹紧 1..102）。
//   7) 开关语义：SW1 拨上=冻结、拨下=运行（v1.5 起反转）；
//      滚动状态只有一份：scroll_en。SW3 电平变化时写入，菜单 ROL 项与串口 S
//      命令也能改；roll 只是 scroll_en 的别名（给菜单显示/LED 用）。
//      时基仍然完全手动，滚动模式不改 tb_div（不做自动限速）。
//      菜单项: 0=CH0开关 1=CH1开关 2=CH0档位 3=CH1档位 4=CH0位置 5=CH1位置
//              6=波形 7=频率
//==============================================================================
`timescale 1ns / 1ps

module scope_app #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  key_n,        // {U,D,L,R} 低有效
    input  wire        gen_ena,      // 1=内置信号源可用 0=外部 ADC，信号源菜单失效
    // ---- 拨动开关（分摊长按功能）----
    input  wire        sw_menu,      // SW0 电平: 1=菜单打开 0=关闭
    input  wire        sw_run,       // SW1 电平: 1=冻结 0=运行（v1.5 反转）
    input  wire        sw_page,      // SW2 电平: 1=信号源页 0=示波器页
    input  wire        sw_roll,      // SW3 电平: 1=滚动模式 0=触发刷新
    input  wire        sw_roll2,     // SW5 电平: 滚动开关（1=非滚动 0=滚动）
    input  wire        sw_hzfree,    // SW6 电平: 1=横轴缩放不设上限(只受理论极限)
    input  wire        sw_move,      // SW7 电平: 1=U/D 改为上下移动基线

    // ---- 串口下发 ----
    input  wire        ext_tb_we,    input wire [15:0] ext_tb,
    input  wire        ext_run_we,   input wire        ext_run,
    input  wire        ext_ten_we,   input wire        ext_ten,
    input  wire        ext_lvl_we,   input wire [9:0]  ext_lvl,
    input  wire        ext_edg_we,   input wire        ext_edg,
    input  wire        ext_scr_we,   input wire        ext_scr,
    input  wire        ext_tmode_we, input wire [1:0]  ext_tmode,
    input  wire        ext_tsrc_we,  input wire        ext_tsrc,
    input  wire        ext_pre_we,   input wire [9:0]  ext_pre,
    input  wire        ext_hold_we,  input wire [15:0] ext_hold,

    // ---- 采集状态反馈 ----
    input  wire        cap_done,
    input  wire [1:0]  cap_state,

    // ---- 输出 ----
    output reg  [15:0] tb_div,
    output reg         run,
    output reg         arm,
    output reg         trig_en,
    output reg  [1:0]  trig_mode,
    output reg         trig_src,      // 0=CH0 1=CH1
    output reg  [9:0]  trig_level,
    output reg         trig_edge,
    output reg  [9:0]  pre_trig,
    output reg  [15:0] holdoff,
    output reg         scroll_en,
    output reg  [3:0]  tb_idx,
    output reg         page,
    output wire [2:0]  state_o,
    output wire        ev_short_o,
    output wire        ev_long_o,

    // ---- 按键配置输出 ----
    output reg         ch0_en,
    output reg         ch1_en,
    output reg  [2:0]  vs0,           // 0..7 垂直档位（右移位数，越小波形越高）
    output reg  [2:0]  vs1,
    output reg  [3:0]  pos0,          // 垂直位置档位 0..9（5=居中）
    output reg  [3:0]  pos1,
    output wire        roll,          // 滚动状态别名，恒等于 scroll_en
    output reg  [6:0]  hscale,        // 横轴缩放系数 S(1..102): pxz=(px*S)>>6，64=1:1
    output reg  signed [12:0] yoff,   // 基线偏移(像素)，SW7 打开时由 U/D 调整
    output reg         menu_page,     // 0=示波器设置 1=信号源设置
    output reg  [3:0]  phase_idx,     // 信号源相位档 0..9 (每档 36 度)
    output reg  [1:0]  wave,          // 函数发生器波形
    output reg  [2:0]  fsel,          // 函数发生器频率档
    output reg  [1:0]  asel,          // 函数发生器幅度档
    output reg         menu_on,
    output reg  [3:0]  menu_sel
);

    //------------------------------------------------------------------
    // 4 键去抖
    //------------------------------------------------------------------
    wire ev_us, ev_ul, ev_ur, ev_ds, ev_dl, ev_dr;   // U 键：短按/长按首拍/长按重复
    wire ev_ls, ev_ll, ev_lr, ev_rs, ev_rl, ev_rr;   // L/R 键：短按/长按首拍/长按重复

    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(500), .FAST_MS(30)) u_uiU (
        .clk(clk), .rst(rst), .key_in(key_n[3]),
        .ev_short(ev_us), .ev_long(ev_ul), .ev_repeat(ev_ur));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(500), .FAST_MS(30)) u_uiD (
        .clk(clk), .rst(rst), .key_in(key_n[2]),
        .ev_short(ev_ds), .ev_long(ev_dl), .ev_repeat(ev_dr));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(500), .FAST_MS(30)) u_uiL (
        .clk(clk), .rst(rst), .key_in(key_n[1]),
        .ev_short(ev_ls), .ev_long(ev_ll), .ev_repeat(ev_lr));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(500), .FAST_MS(30)) u_uiR (
        .clk(clk), .rst(rst), .key_in(key_n[0]),
        .ev_short(ev_rs), .ev_long(ev_rl), .ev_repeat(ev_rr));

    assign ev_short_o = ev_ls;     // 兼容旧接口
    assign ev_long_o  = ev_ll;

    //------------------------------------------------------------------
    // 横轴缩放系数 S（1..102）
    //   顶层按 pxz = (px * S) >> 6 取采样地址：
    //     S = 64  -> 1:1（一个采样点占一个像素）
    //     S < 64  -> 放大（S=32 即 2 倍，S=1 时 640 像素只覆盖 10 个点）
    //     S = 102 -> 约"适应全屏"（640 像素覆盖 1018 个点，已接近 1024 的缓冲深度）
    //   按键不做"档位跳变"，而是乘性步进 S <- S ± S/8（约 ±12.5%），
    //   配合长按 30ms 的快速重复，屏幕上的缩放就是连续丝滑的。
    //------------------------------------------------------------------
    localparam [6:0] HSC_MIN = 7'd1;     // 最大放大（约 64 倍）
    localparam [6:0] HSC_MAX = 7'd102;   // 最大缩小（约等于适应全屏，受 1024 点缓冲限制）
    localparam [6:0] HSC_1X  = 7'd64;    // 1:1

    // 放大：S <- S - S/8；S 很小时 S/8=0，步长保底 1，保证按键始终有反应
    function [6:0] hsc_in;
        input [6:0] s;
        reg   [6:0] d;
        begin
            d = {3'b000, s[6:3]};
            if (d == 7'd0) d = 7'd1;
            hsc_in = (s > d) ? (s - d) : HSC_MIN;
        end
    endfunction

    // 缩小：S <- S + S/8，夹紧到 HSC_MAX
    function [6:0] hsc_out;
        input [6:0] s;
        reg   [6:0] d;
        begin
            d = {3'b000, s[6:3]};
            if (d == 7'd0) d = 7'd1;
            hsc_out = ((s + d) > HSC_MAX) ? HSC_MAX : (s + d);
        end
    endfunction

    //------------------------------------------------------------------
    // 时基档位表（16 档，2 倍步进，双向）
    //   tb_div = (50000 >> i) - 1：i=0 最慢(504S/s)，i=15 最快(全速)
    //   25.2MHz 下每格(64px)对应的时间从 127ms 一直覆盖到 2.5us，
    //   即"横轴量程跨越秒到毫秒"。
    //------------------------------------------------------------------
    function [15:0] tb_val;
        input [3:0] i;
        begin
            case (i)
                4'd0 : tb_val = 16'd49999;
                4'd1 : tb_val = 16'd24999;
                4'd2 : tb_val = 16'd12499;
                4'd3 : tb_val = 16'd6249;
                4'd4 : tb_val = 16'd3124;
                4'd5 : tb_val = 16'd1561;
                4'd6 : tb_val = 16'd780;
                4'd7 : tb_val = 16'd389;
                4'd8 : tb_val = 16'd194;
                4'd9 : tb_val = 16'd96;
                4'd10: tb_val = 16'd47;
                4'd11: tb_val = 16'd23;
                4'd12: tb_val = 16'd11;
                4'd13: tb_val = 16'd5;
                4'd14: tb_val = 16'd2;
                4'd15: tb_val = 16'd0;
            endcase
        end
    endfunction

    wire [3:0] tb_next = (tb_idx == 4'd15) ? 4'd0 : (tb_idx + 4'd1);
    wire [3:0] tb_prev = (tb_idx == 4'd0) ? 4'd15 : (tb_idx - 4'd1);

    //------------------------------------------------------------------
    // 翻页计数：每 2 秒翻转一次
    //------------------------------------------------------------------
    localparam integer PAGE_MAX = 2*CLK_HZ - 1;
    reg [26:0] page_cnt;
    always @(posedge clk) begin
        if (rst) begin
            page_cnt <= 27'd0;
            page     <= 1'b0;
        end
        else if (page_cnt == PAGE_MAX[26:0]) begin
            page_cnt <= 27'd0;
            page     <= ~page;
        end
        else begin
            page_cnt <= page_cnt + 27'd1;
        end
    end

    //------------------------------------------------------------------
    // 主寄存器块
    //------------------------------------------------------------------
    reg boot;
    reg sw_run_d, sw_roll_d, sw_roll2_d;

    always @(posedge clk)
        if (rst) boot <= 1'b0;
        else     boot <= 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            sw_run_d   <= 1'b0;
            sw_roll_d  <= 1'b0;
            sw_roll2_d <= 1'b0;
            tb_idx     <= 4'd0;
            tb_div     <= 16'd49999;
            run        <= 1'b1;
            arm        <= 1'b0;
            trig_en    <= 1'b0;
            trig_mode  <= 2'd1;      // 默认连续刷新（跟踪模式）
            trig_src   <= 1'b0;
            trig_level <= 10'd512;
            trig_edge  <= 1'b0;
            pre_trig   <= 10'd0;
            holdoff    <= 16'd0;
            scroll_en  <= 1'b0;

            ch0_en     <= 1'b1;
            ch1_en     <= 1'b1;
            vs0        <= 3'd4;
            vs1        <= 3'd4;
            pos0       <= 4'd5;
            pos1       <= 4'd5;
            hscale     <= HSC_1X;
            yoff       <= 13'sd0;
            menu_page  <= 1'b0;
            phase_idx  <= 4'd0;
            wave       <= 2'd0;
            fsel       <= 3'd3;        // 50 Hz
            asel       <= 2'd0;        // 100%
            menu_on    <= 1'b0;
            menu_sel   <= 4'd0;
        end
        else begin
            arm <= 1'b0;
            if (!boot) arm <= 1'b1;

            //================= 按键 =================
            if (!menu_on) begin
                // ---- 正常模式 ----
                //   短按 ev_*s、长按首拍 ev_*l、长按重复 ev_*r 做的是同一件事：
                //   短按 = 走一小步；长按 500ms 后进入连续模式，之后每 30ms 走一小步。
                // SW7 打开时：U/D 改为上下移动基线（夹紧在"屏内必须还剩波形"的范围）
                if (sw_move) begin
                    if (ev_us | ev_ul | ev_ur) yoff <= (yoff > -13'sd1200) ? (yoff - 13'sd16) : yoff;
                    if (ev_ds | ev_dl | ev_dr) yoff <= (yoff <  13'sd1200) ? (yoff + 13'sd16) : yoff;
                end
                else begin
                    if (ev_us | ev_ul | ev_ur) begin
                        if (vs0 > 3'd2) vs0 <= vs0 - 3'd1;      // 放大
                    end
                    if (ev_ds | ev_dl | ev_dr) begin
                        if (vs0 < 3'd7) vs0 <= vs0 + 3'd1;      // 缩小
                    end
                end
                // 左右按键 = 横轴连续缩放（只改显示，不重新采集）
                //   左 = 放大（S 减小），右 = 缩小（S 增大），每次乘性步进约 ±1/8。
                //   长按 500ms 后每 30ms 再来一步，所以按住不放是丝滑变化，而不是台阶。
                //   SW6(sw_hzfree) 已无意义：S 的 1..102 本身就覆盖了 1/64x..1.6x，
                //   端口保留只为不动物理引脚定义。
                if (ev_ls | ev_ll | ev_lr) hscale <= hsc_in(hscale);
                if (ev_rs | ev_rl | ev_rr) hscale <= hsc_out(hscale);
            end
            else begin
                // ---- 菜单模式 ----
                // 光标范围随页面变化：P0 有 9 项(0..8)，P1 有 4 项(0..3)
                if (ev_ls) menu_sel <= (menu_sel == 4'd0) ? (menu_page ? 4'd3 : 4'd8)
                                                         : (menu_sel - 4'd1);
                if (ev_rs) menu_sel <= (menu_sel == (menu_page ? 4'd3 : 4'd8)) ? 4'd0
                                                                              : (menu_sel + 4'd1);
                if (ev_ul) menu_on  <= 1'b0;                // 退出菜单

                if (ev_us | ev_ds) begin
                    if (!menu_page || !gen_ena) begin
                        // ---- P0: 示波器设置 ----
                        case (menu_sel)
                            4'd0: begin ch0_en <= ~ch0_en; arm <= 1'b1; end
                            4'd1: begin ch1_en <= ~ch1_en; arm <= 1'b1; end
                            4'd2: begin
                                if (ev_us && (vs0 > 3'd2)) vs0 <= vs0 - 3'd1;
                                if (ev_ds && (vs0 < 3'd7)) vs0 <= vs0 + 3'd1;
                            end
                            4'd3: begin
                                if (ev_us && (vs1 > 3'd2)) vs1 <= vs1 - 3'd1;
                                if (ev_ds && (vs1 < 3'd7)) vs1 <= vs1 + 3'd1;
                            end
                            4'd4: begin
                                if (ev_us && (pos0 > 4'd0)) pos0 <= pos0 - 4'd1;  // U=上移
                                if (ev_ds && (pos0 < 4'd9)) pos0 <= pos0 + 4'd1;  // D=下移
                            end
                            4'd5: begin
                                if (ev_us && (pos1 > 4'd0)) pos1 <= pos1 - 4'd1;
                                if (ev_ds && (pos1 < 4'd9)) pos1 <= pos1 + 4'd1;
                            end
                            // 菜单 HSC：与 L/R 完全相同的乘性规则
                            4'd6: begin
                                if (ev_us) hscale <= hsc_in(hscale);        // U=放大(S 减小)
                                if (ev_ds) hscale <= hsc_out(hscale);       // D=缩小(S 增大)
                            end
                            4'd7: begin
                                if (ev_us) begin tb_idx <= tb_next; tb_div <= tb_val(tb_next); end
                                if (ev_ds) begin tb_idx <= tb_prev; tb_div <= tb_val(tb_prev); end
                                arm <= 1'b1;
                            end
                            // 菜单 ROL：与 SW3、串口 S 共用同一个 scroll_en
                            4'd8: begin scroll_en <= ~scroll_en; arm <= 1'b1; end
                            default: ;
                        endcase
                    end
                    else begin
                        // ---- P1: 信号源设置 ----
                        case (menu_sel)
                            4'd0: begin
                                if (ev_us) wave <= wave + 2'd1;
                                if (ev_ds) wave <= wave - 2'd1;
                            end
                            4'd1: begin
                                if (ev_us) fsel <= fsel + 3'd1;
                                if (ev_ds) fsel <= fsel - 3'd1;
                            end
                            4'd2: begin
                                if (ev_us) asel <= asel + 2'd1;
                                if (ev_ds) asel <= asel - 2'd1;
                            end
                            4'd3: begin
                                if (ev_us) phase_idx <= (phase_idx == 4'd9) ? 4'd0 : (phase_idx + 4'd1);
                                if (ev_ds) phase_idx <= (phase_idx == 4'd0) ? 4'd9 : (phase_idx - 4'd1);
                            end
                            default: ;
                        endcase
                    end
                end
            end

            //================= 拨动开关（电平语义，优先级最高）=================
            //   拨到开 = 开，拨到关 = 关，不需要拨两次
            menu_on   <=  sw_menu;
            run       <= ~sw_run;      // SW1 语义：拨上=冻结、拨下=运行
            // 菜单页完全由 SW2 决定（长按功能已移除）
            menu_page <=  sw_page && gen_ena;

            // 运行/冻结状态一变就重新采集一次（不论方向）
            sw_run_d <= sw_run;
            if (sw_run != sw_run_d) arm <= 1'b1;

            // SW3 是滚动开关，但只在电平"变化"的那一刻写进 scroll_en：
            //   拨上(1) = 纸带式自由滚动（采集自由循环写，最右列最新）
            //   拨下(0) = 触发 + 乒乓换页（采满一屏才切换到新半区）
            // 如果像旧版那样每拍 scroll_en <= sw_roll，菜单 ROL 项和串口 S
            // 命令写进去的值下一拍就被覆盖，等于永远改不动 —— 这就是缺陷 1。
            // 改成"变化时写入"后：开关位置仍然决定电平语义（拨上即开、拨下即关），
            // 之后菜单/串口改的值会一直保持，直到下一次拨动 SW3。
            // 滚动开关 = SW5(P6)，语义：拨上(1)=非滚动、拨下(0)=滚动
            //   （SW3/T6 那一路实测无反应，已不再使用，端口保留但不参与逻辑）
            if ((!boot) || (sw_roll2 != sw_roll2_d)) begin
                scroll_en  <= ~sw_roll2;    // 上电首拍直接采用开关位置，之后每次变化跟随
                sw_roll2_d <= sw_roll2;
                arm        <= 1'b1;         // 切换显示模式后重新采一屏
            end
            sw_roll_d <= sw_roll;           // 仅保持旧信号不悬空

            //================= 串口(后写优先) =================
            if (ext_tb_we)    begin tb_div     <= ext_tb;    arm <= 1'b1; end
            if (ext_run_we)   begin run        <= ext_run;   arm <= 1'b1; end
            if (ext_ten_we)   begin trig_en    <= ext_ten;   arm <= 1'b1; end
            if (ext_lvl_we)   begin trig_level <= ext_lvl;   end
            if (ext_edg_we)   begin trig_edge  <= ext_edg;   end
            if (ext_scr_we)   begin scroll_en  <= ext_scr;   end     // S0/S1 与 SW3、菜单 ROL 同源
            if (ext_tmode_we) begin trig_mode  <= ext_tmode; arm <= 1'b1; end
            if (ext_tsrc_we)  begin trig_src   <= ext_tsrc;  arm <= 1'b1; end
            if (ext_pre_we)   begin pre_trig   <= ext_pre;   arm <= 1'b1; end
            if (ext_hold_we)  begin holdoff    <= ext_hold;  end

            // 正常模式：捕获完成自动重触发
            if (cap_done && (trig_mode == 2'd1) && run)
                arm <= 1'b1;
        end
    end

    // roll 只是 scroll_en 的别名：菜单 ROL 显示、顶层 dbg_status 都看这一份状态，
    // 显示读地址通路也只认 scroll_en，三处不会再出现"菜单改了、显示没动"的分裂。
    assign roll = scroll_en;

    assign state_o = (!run)                       ? 3'd0 :
                     (cap_state == 2'd3)          ? 3'd3 :
                     (cap_state == 2'd0)          ? 3'd1 :
                                                    3'd2 ;

endmodule