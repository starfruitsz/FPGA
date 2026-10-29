//==============================================================================
// 层: 应用(配置)  文件: app/scope_app.v   [v2: 触发寄存器 + 会话状态 + 测量翻页]
// 功能:
//   1) 寄存器: 时基 tb_div、触发使能/模式/源/电平/边沿、预触发、保持时间、滚动
//   2) 会话状态: 0=STOP 1=IDLE 2=ARMED/FILL 3=DONE（供文本层显示）
//   3) 翻页: page 每 2 秒翻转，文本层据此切换测量显示页
//   4) 重触发: normal 模式捕获完成(cap_done)后自动 arm；single 等外部 arm
//   5) 串口下发的写优先于按键
//==============================================================================
`timescale 1ns / 1ps

module scope_app (
    input  wire        clk,
    input  wire        rst,
    input  wire        key_in,

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
    output reg         page,          // 0=时域页 1=测量页
    output wire [2:0]  state_o,
    output wire        ev_short_o,
    output wire        ev_long_o
);

    wire ev_short, ev_long;

    assign ev_short_o = ev_short;
    assign ev_long_o  = ev_long;

    //------------------------------------------------------------------
    // 按键去抖（复用已有模块）
    //------------------------------------------------------------------
    scope_ui #(
        .CLK_HZ (50_000_000),
        .DB_MS  (20),
        .LONG_MS(800)
    ) u_ui (
        .clk(clk), .rst(rst), .key_in(key_in),
        .ev_short(ev_short), .ev_long(ev_long)
    );

    //------------------------------------------------------------------
    // 时基档位表
    //------------------------------------------------------------------
    wire [2:0] nidx = (tb_idx == 3'd6) ? 3'd0 : (tb_idx + 3'd1);

    reg [15:0] tb_next;
    always @(*) begin
        case (nidx)
            3'd0: tb_next = 16'd49999;
            3'd1: tb_next = 16'd9999;
            3'd2: tb_next = 16'd1999;
            3'd3: tb_next = 16'd499;
            3'd4: tb_next = 16'd99;
            3'd5: tb_next = 16'd9;
            3'd6: tb_next = 16'd0;
            default: tb_next = 16'd49999;
        endcase
    end

    //------------------------------------------------------------------
    // 翻页计数：每 2 秒翻转一次(50MHz x 2s = 100,000,000)
    //------------------------------------------------------------------
    reg [26:0] page_cnt;
    always @(posedge clk) begin
        if (rst) begin
            page_cnt <= 27'd0;
            page     <= 1'b0;
        end
        else if (page_cnt == 27'd99_999_999) begin
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

    // 上电后自动 arm 一次，避免一直停在 IDLE 不采集
    reg boot;
    always @(posedge clk)
        if (rst) boot <= 1'b0;
        else     boot <= 1'b1;
    always @(posedge clk) begin
        if (rst) begin
            tb_idx     <= 3'd0;
            tb_div     <= 16'd49999;
            run        <= 1'b1;
            arm        <= 1'b0;
            trig_en    <= 1'b0;
            trig_mode  <= 2'd0;      // 默认自动
            trig_src   <= 1'b0;      // 默认 CH0
            trig_level <= 10'd512;
            trig_edge  <= 1'b0;
            pre_trig   <= 10'd0;
            holdoff    <= 16'd0;
            scroll_en  <= 1'b0;
        end
        else begin
            arm <= 1'b0;
            if (!boot) arm <= 1'b1;   // 上电自动采集一次

            // ---- 按键 ----
            if (ev_short) begin
                tb_idx <= nidx;
                tb_div <= tb_next;
                arm    <= 1'b1;
            end
            if (ev_long) begin
                run <= ~run;
                arm <= 1'b1;
            end

            // ---- 串口(后写优先) ----
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

            // ---- 正常模式：捕获完成自动重触发（连续刷新） ----
            if (cap_done && (trig_mode == 2'd1) && run)
                arm <= 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 会话状态输出（给文本层/调试用）
    //------------------------------------------------------------------
    assign state_o = (!run)                       ? 3'd0 :   // STOP
                     (cap_state == 2'd3)          ? 3'd3 :   // DONE
                     (cap_state == 2'd0)          ? 3'd1 :   // IDLE
                                                    3'd2 ;   // ARMED / FILL

endmodule
