//==============================================================================
// 层: 应用(配置)  文件: app/scope_app.v   [v3: 4 键菜单 + 通道/垂直档位/垂直位置]
// 功能:
//   1) 寄存器: 时基 tb_div、触发使能/模式/源/电平/边沿、预触发、保持时间、滚动
//   2) 会话状态: 0=STOP 1=IDLE 2=ARMED/FILL 3=DONE（供文本层显示）
//   3) 翻页: page 每 2 秒翻转，文本层据此切换测量显示页
//   4) 重触发: normal 模式捕获完成(cap_done)后自动 arm；single 等外部 arm
//   5) 串口下发的写优先于按键
//   6) 4 键操作（L/R/U/D，低有效）：
//        正常模式:  U短=垂直放大  D短=垂直缩小  L短=水平放大  R短=水平缩小
//        （长按功能已全部改由拨动开关承担，按键只剩短按）
//        菜单模式:  L/R=移动光标  U/D=调整当前项
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
    input  wire        sw_run,       // SW1 电平: 1=运行 0=冻结
    input  wire        sw_page,      // SW2 电平: 1=信号源页 0=示波器页
    input  wire        sw_roll,      // SW3 电平: 1=滚动模式 0=触发刷新

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
    output reg  [2:0]  tb_idx,
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
    output reg         roll,          // 1=滚动模式 0=触发刷新
    output reg  [1:0]  hzoom,         // 水平缩放: 0=1x 1=2x 2=4x 3=适应全屏
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
    wire ev_us, ev_ul, ev_ds, ev_dl, ev_ls, ev_ll, ev_rs, ev_rl;

    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(800)) u_uiU (
        .clk(clk), .rst(rst), .key_in(key_n[3]), .ev_short(ev_us), .ev_long(ev_ul));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(800)) u_uiD (
        .clk(clk), .rst(rst), .key_in(key_n[2]), .ev_short(ev_ds), .ev_long(ev_dl));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(800)) u_uiL (
        .clk(clk), .rst(rst), .key_in(key_n[1]), .ev_short(ev_ls), .ev_long(ev_ll));
    scope_ui #(.CLK_HZ(CLK_HZ), .DB_MS(20), .LONG_MS(800)) u_uiR (
        .clk(clk), .rst(rst), .key_in(key_n[0]), .ev_short(ev_rs), .ev_long(ev_rl));

    assign ev_short_o = ev_ls;     // 兼容旧接口
    assign ev_long_o  = ev_ll;

    //------------------------------------------------------------------
    // 时基档位表（7 档，双向）
    //------------------------------------------------------------------
    function [15:0] tb_val;
        input [2:0] i;
        begin
            case (i)
                3'd0: tb_val = 16'd49999;
                3'd1: tb_val = 16'd9999;
                3'd2: tb_val = 16'd1999;
                3'd3: tb_val = 16'd499;
                3'd4: tb_val = 16'd99;
                3'd5: tb_val = 16'd9;
                3'd6: tb_val = 16'd0;
                default: tb_val = 16'd49999;
            endcase
        end
    endfunction

    wire [2:0] tb_next = (tb_idx >= 3'd6) ? 3'd0 : (tb_idx + 3'd1);
    wire [2:0] tb_prev = (tb_idx == 3'd0) ? 3'd6 : (tb_idx - 3'd1);

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
    reg sw_run_d, sw_roll_d;

    always @(posedge clk)
        if (rst) boot <= 1'b0;
        else     boot <= 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            sw_run_d   <= 1'b0;
            sw_roll_d  <= 1'b0;
            tb_idx     <= 3'd0;
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
            roll       <= 1'b0;
            hzoom      <= 2'd0;
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
                if (ev_us) begin
                    if (vs0 > 3'd2) vs0 <= vs0 - 3'd1;      // 放大
                end
                if (ev_ds) begin
                    if (vs0 < 3'd7) vs0 <= vs0 + 3'd1;      // 缩小
                end
                // 左右短按 = 水平缩放（只改显示，不重新采集）
                if (ev_ls) begin
                    if (hzoom > 2'd0) hzoom <= hzoom - 2'd1;
                end
                if (ev_rs) begin
                    if (hzoom < 2'd3) hzoom <= hzoom + 2'd1;
                end
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
                            4'd6: begin
                                if (ev_us && (hzoom < 2'd3)) hzoom <= hzoom + 2'd1;  // U=放大
                                if (ev_ds && (hzoom > 2'd0)) hzoom <= hzoom - 2'd1;
                            end
                            4'd7: begin
                                if (ev_us) begin tb_idx <= tb_next; tb_div <= tb_val(tb_next); end
                                if (ev_ds) begin tb_idx <= tb_prev; tb_div <= tb_val(tb_prev); end
                                arm <= 1'b1;
                            end
                            4'd8: begin roll <= ~roll; arm <= 1'b1; end
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
            run       <=  sw_run;
            roll      <=  sw_roll;
            // 菜单页完全由 SW2 决定（长按功能已移除）
            menu_page <=  sw_page && gen_ena;

            // 开关从"冻结"拨到"运行"时重新采集一次
            sw_run_d <= sw_run;
            if (sw_run & ~sw_run_d) arm <= 1'b1;
            if (sw_roll & ~sw_roll_d) arm <= 1'b1;
            sw_roll_d <= sw_roll;

            //================= 串口(后写优先) =================
            if (ext_tb_we)    begin tb_div     <= ext_tb;    arm <= 1'b1; end
            if (ext_run_we)   begin run        <= ext_run;   arm <= 1'b1; end
            if (ext_ten_we)   begin trig_en    <= ext_ten;   arm <= 1'b1; end
            if (ext_lvl_we)   begin trig_level <= ext_lvl;   end
            if (ext_edg_we)   begin trig_edge  <= ext_edg;   end
            if (ext_scr_we)   begin scroll_en  <= ext_scr;   end
            if (ext_tmode_we) begin trig_mode  <= ext_tmode; arm <= 1'b1; end
            if (ext_tsrc_we)  begin trig_src   <= ext_tsrc;  arm <= 1'b1; end
            if (ext_pre_we)   begin pre_trig   <= ext_pre;   arm <= 1'b1; end
            if (ext_hold_we)  begin holdoff    <= ext_hold;  end

            // 正常模式：捕获完成自动重触发
            if (cap_done && (trig_mode == 2'd1) && run)
                arm <= 1'b1;
        end
    end

    assign state_o = (!run)                       ? 3'd0 :
                     (cap_state == 2'd3)          ? 3'd3 :
                     (cap_state == 2'd0)          ? 3'd1 :
                                                    3'd2 ;

endmodule