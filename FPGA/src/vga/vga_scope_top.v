//==============================================================================
// 层: 顶层(集成)  文件: vga_scope_top.v   [v2: 触发状态机 / 扩展测量 / 双页文本]
// 装配 HAL/ABS/APP，不含算法。像素流水线与 v1 相同：
//   像素周期 = PIX_DIV 个 clk；BSRAM 同步读 1 拍；后半拍求值，pix_ce 打寄存器；
//   hs/vs/de 固定延迟 2 拍（=1 像素）对齐。
// 新增连线：
//   - 触发源选择(trig_src) → capture.trig_din
//   - capture.state/rd_base → 显示读地址(触发基准) 与状态显示
//   - meas 扩展输出 → 文本第 2 页
//==============================================================================
`timescale 1ns / 1ps

module vga_scope_top #(
    parameter integer H_VIS     = 640,
    parameter integer H_FP      = 16,
    parameter integer H_SYNC    = 96,
    parameter integer H_BP      = 48,
    parameter integer V_VIS     = 480,
    parameter integer V_FP      = 10,
    parameter integer V_SYNC    = 2,
    parameter integer V_BP      = 33,
    parameter integer H_POL     = 0,
    parameter integer V_POL     = 0,
    parameter integer PIX_DIV   = 2,
    parameter integer PLOT_H    = 448,
    parameter integer GRID_STEP = 64,
    parameter integer AXIS_Y    = 224,
    parameter integer TEXT_Y0   = 448,
    parameter integer TEXT_X0   = 8,
    parameter integer DEPTH_LOG2 = 10,
    parameter integer FEAT_TRIG   = 1,
    parameter integer FEAT_MEAS   = 1,
    parameter integer FEAT_SCROLL = 1,
    parameter integer FEAT_UART   = 1,
    parameter [11:0] COL_BG   = 12'h012,
    parameter [11:0] COL_GRID = 12'h151,
    parameter [11:0] COL_AXIS = 12'h2A2,
    parameter [11:0] COL_CH0  = 12'h1F1,
    parameter [11:0] COL_CH1  = 12'hFF1,
    parameter [11:0] COL_TEXT = 12'hFFF
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  ch0_in,
    input  wire [9:0]  ch1_in,
    input  wire        key_in,

    // 串口配置
    input  wire        cfg_tb_we,    input wire [15:0] cfg_tb,
    input  wire        cfg_run_we,   input wire        cfg_run,
    input  wire        cfg_ten_we,   input wire        cfg_ten,
    input  wire        cfg_lvl_we,   input wire [9:0]  cfg_lvl,
    input  wire        cfg_edg_we,   input wire        cfg_edg,
    input  wire        cfg_scr_we,   input wire        cfg_scr,
    input  wire        cfg_tmode_we, input wire [1:0]  cfg_tmode,
    input  wire        cfg_tsrc_we,  input wire        cfg_tsrc,
    input  wire        cfg_pre_we,   input wire [9:0]  cfg_pre,
    input  wire        cfg_hold_we,  input wire [15:0] cfg_hold,

    output wire [11:0] vga_rgb,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_de
);

    //------------------------------------------------------------------
    // HAL: 时序
    //------------------------------------------------------------------
    wire        pix_ce;
    wire        hs, vs, de;
    wire [11:0] px, py;

    vga_timing #(
        .H_VIS(H_VIS), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_VIS(V_VIS), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .H_POL(H_POL), .V_POL(V_POL), .PIX_DIV(PIX_DIV)
    ) u_timing (
        .clk(clk), .rst(rst), .pix_ce(pix_ce),
        .hs(hs), .vs(vs), .de(de), .px(px), .py(py)
    );

    reg vs_d;
    always @(posedge clk) vs_d <= vs;
    wire frame = vs & (~vs_d);

    //------------------------------------------------------------------
    // APP: 配置与状态
    //------------------------------------------------------------------
    wire        run, arm;
    wire [15:0] tb_div;
    wire        trig_en, trig_src, trig_edge, scroll_en;
    wire [1:0]  trig_mode;
    wire [9:0]  trig_level, pre_trig;
    wire [15:0] holdoff;
    wire        page;
    wire [2:0]  state_o;

    wire [9:0] s0, s1;
    wire        we0, we1;
    wire [DEPTH_LOG2-1:0] wa0, wa1;
    wire        done0, done1, trig_det0;
    wire [DEPTH_LOG2-1:0] rd_base0, rd_base1;
    wire [1:0]  state0, state1;

    scope_app u_app (
        .clk(clk), .rst(rst), .key_in(key_in),
        .ext_tb_we(cfg_tb_we),       .ext_tb(cfg_tb),
        .ext_run_we(cfg_run_we),     .ext_run(cfg_run),
        .ext_ten_we(cfg_ten_we),     .ext_ten(cfg_ten),
        .ext_lvl_we(cfg_lvl_we),     .ext_lvl(cfg_lvl),
        .ext_edg_we(cfg_edg_we),     .ext_edg(cfg_edg),
        .ext_scr_we(cfg_scr_we),     .ext_scr(cfg_scr),
        .ext_tmode_we(FEAT_UART ? cfg_tmode_we : 1'b0), .ext_tmode(cfg_tmode),
        .ext_tsrc_we (FEAT_UART ? cfg_tsrc_we  : 1'b0), .ext_tsrc(cfg_tsrc),
        .ext_pre_we  (FEAT_UART ? cfg_pre_we   : 1'b0), .ext_pre(cfg_pre),
        .ext_hold_we (FEAT_UART ? cfg_hold_we  : 1'b0), .ext_hold(cfg_hold),
        .cap_done(done0), .cap_state(state0),
        .tb_div(tb_div), .run(run), .arm(arm),
        .trig_en(trig_en), .trig_mode(trig_mode), .trig_src(trig_src),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .scroll_en(scroll_en), .tb_idx(), .page(page), .state_o(state_o),
        .ev_short_o(), .ev_long_o()
    );

    //------------------------------------------------------------------
    // APP: 采集（两通道共用参数，触发源可选 CH0/CH1）
    //------------------------------------------------------------------

    wire [9:0] trig_din = trig_src ? ch1_in : ch0_in;

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap0 (
        .clk(clk), .rst(rst),
        .din(ch0_in), .trig_din(trig_din),
        .rate_div(tb_div), .run(run), .arm(arm),
        .trig_en(FEAT_TRIG ? trig_en : 1'b0),
        .trig_mode(trig_mode), .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .we(we0), .waddr(wa0), .trig_det(trig_det0), .done(done0),
        .rd_base(rd_base0), .state(state0)
    );

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap1 (
        .clk(clk), .rst(rst),
        .din(ch1_in), .trig_din(trig_din),
        .rate_div(tb_div), .run(run), .arm(arm),
        .trig_en(FEAT_TRIG ? trig_en : 1'b0),
        .trig_mode(trig_mode), .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .we(we1), .waddr(wa1), .trig_det(), .done(done1),
        .rd_base(rd_base1), .state(state1)
    );

    //------------------------------------------------------------------
    // 读地址：触发基准 + 像素列；滚动模式改用“帧起始写指针”
    //------------------------------------------------------------------
    wire [9:0] raddr;
    generate
        if (FEAT_SCROLL != 0) begin : g_scroll
            reg [DEPTH_LOG2-1:0] rd_base_s;
            always @(posedge clk) begin
                if (rst)                    rd_base_s <= {DEPTH_LOG2{1'b0}};
                else if (frame)             rd_base_s <= wa0;
            end
            assign raddr = scroll_en ? (rd_base_s - 10'd640 + px[9:0])
                                     : (rd_base0 + px[9:0]);
        end
        else begin : g_noscroll
            assign raddr = rd_base0 + px[9:0];
        end
    endgenerate

    vram_sdp #(.DW(10), .AW(DEPTH_LOG2)) u_ram0 (
        .clk(clk), .we(we0), .waddr(wa0), .wdata(ch0_in),
        .raddr(raddr), .rdata(s0)
    );
    vram_sdp #(.DW(10), .AW(DEPTH_LOG2)) u_ram1 (
        .clk(clk), .we(we1), .waddr(wa1), .wdata(ch1_in),
        .raddr(raddr), .rdata(s1)
    );

    reg [9:0] s0_prev, s1_prev;
    always @(posedge clk) begin
        s0_prev <= s0;
        s1_prev <= s1;
    end

    //------------------------------------------------------------------
    // APP: 测量（扩展）
    //------------------------------------------------------------------
    wire [9:0]  vpp, vmax, vmin, vmean;
    wire [15:0] freq, period;
    wire [7:0]  duty;

    generate
        if (FEAT_MEAS != 0) begin : g_meas
            scope_meas u_meas (
                .clk(clk), .rst(rst), .din(ch0_in), .tick(we0),   // 用采样节拍统计(不是系统时钟), .frame(frame),
                .vpp(vpp), .vmax(vmax), .vmin(vmin), .vmean(vmean),
                .freq(freq), .period(period), .duty(duty)
            );
        end
        else begin : g_nomeas
            assign vpp = 10'd0; assign vmax = 10'd0; assign vmin = 10'd0; assign vmean = 10'd0;
            assign freq = 16'd0; assign period = 16'd0; assign duty = 8'd0;
        end
    endgenerate

    //------------------------------------------------------------------
    // ABS: 图层
    //------------------------------------------------------------------
    wire        g_hit;
    wire [11:0] g_col;

    grid_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .STEP(GRID_STEP), .AXIS_Y(AXIS_Y),
        .COL_GRID(COL_GRID), .COL_AXIS(COL_AXIS)
    ) u_grid (.px(px), .py(py), .de(de), .hit(g_hit), .color(g_col));

    wire t0_hit, t1_hit;
    wire [11:0] t0_col, t1_col;

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH0)
    ) u_tr0 (.px(px), .py(py), .de(de), .en(1'b1),
             .s_now(s0), .s_prev(s0_prev), .hit(t0_hit), .color(t0_col));

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH1)
    ) u_tr1 (.px(px), .py(py), .de(de), .en(1'b1),
             .s_now(s1), .s_prev(s1_prev), .hit(t1_hit), .color(t1_col));

    // 文本值：按 page 切换两组测量
    wire [15:0] tv0 = page ? {6'd0, vmax}  : {6'd0, ch0_in};
    wire [15:0] tv1 = page ? {6'd0, vmin}  : {6'd0, ch1_in};
    wire [15:0] tv2 = page ? {6'd0, vmean} : tb_div;
    wire [15:0] tv3 = page ? period        : {6'd0, vpp};
    wire [15:0] tv4 = page ? {8'd0, duty}  : freq;

    wire        tx_hit;
    wire [11:0] tx_col;

    text_layer #(
        .TEXT_Y0(TEXT_Y0), .TEXT_X0(TEXT_X0), .COLS(32), .COL(COL_TEXT)
    ) u_text (
        .px(px), .py(py), .de(de), .page(page),
        .val0(tv0), .val1(tv1), .val2(tv2), .val3(tv3), .val4(tv4),
        .hit(tx_hit), .color(tx_col)
    );

    wire [11:0] rgb_comb;
    compositor u_comp (
        .txt_hit(tx_hit), .txt_col(tx_col),
        .ch1_hit(t1_hit), .ch1_col(t1_col),
        .ch0_hit(t0_hit), .ch0_col(t0_col),
        .grid_hit(g_hit), .grid_col(g_col),
        .bg_col(COL_BG), .rgb(rgb_comb)
    );

    //------------------------------------------------------------------
    // 输出寄存（2 拍 = 1 像素对齐）
    //------------------------------------------------------------------
    reg [11:0] rgb_r;
    reg        hs1, hs2, vs1, vs2, de1, de2;

    always @(posedge clk) begin
        if (rst) begin
            rgb_r <= COL_BG;
            hs1 <= 1'b1; hs2 <= 1'b1;
            vs1 <= 1'b1; vs2 <= 1'b1;
            de1 <= 1'b0; de2 <= 1'b0;
        end
        else begin
            hs1 <= hs; hs2 <= hs1;
            vs1 <= vs; vs2 <= vs1;
            de1 <= de; de2 <= de1;
            if (pix_ce) rgb_r <= rgb_comb;
        end
    end

    assign vga_rgb = rgb_r;
    assign vga_hs  = hs2;
    assign vga_vs  = vs2;
    assign vga_de  = de2;

endmodule
