//==============================================================================
// 层: 顶层(集成)  文件: vga_scope_top.v
// 功能: 双通道 VGA 示波器顶层 —— 只做装配，不含算法
//
// 分层:
//   HAL : vga_timing / vram_sdp / font_rom
//   ABS : grid_layer / trace_layer / text_layer / compositor
//   APP : scope_app / scope_capture / scope_ui / scope_meas / scope_cmd
//
// 特性开关(参数, 综合前配置, 0=关闭 1=开启):
//   FEAT_TRIG   触发对齐(特性1)   : 命中"电平穿越"时把写指针归零，波形不再漂
//   FEAT_MEAS   自动测量(特性2)   : 帧内统计峰峰值/过零次数，显示在文本第 2 行
//   FEAT_SCROLL 滚动显示(特性3)   : 以帧起始写指针为基准滚动，最新采样在最右
//   FEAT_UART   串口在线配置(特性4): 使能 cfg_* 端口(T/R/A/L/E/S 命令)
//
// 时序: 像素周期 = PIX_DIV 个 clk；BSRAM 同步读 1 拍；像素周期后半拍求值，
//       pix_ce 打入输出寄存器；hs/vs/de 延迟 2 拍(1 像素)对齐。
//==============================================================================
`timescale 1ns / 1ps

module vga_scope_top #(
    // ---- 视频时序(默认 640x480@59.5, 50MHz/2) ----
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
    // ---- 布局 ----
    parameter integer PLOT_H    = 448,
    parameter integer GRID_STEP = 64,
    parameter integer AXIS_Y    = 224,
    parameter integer TEXT_Y0   = 448,
    parameter integer TEXT_X0   = 8,
    // ---- 采样缓存 ----
    parameter integer DEPTH_LOG2 = 10,
    // ---- 特性开关 ----
    parameter integer FEAT_TRIG   = 1,
    parameter integer FEAT_MEAS   = 1,
    parameter integer FEAT_SCROLL = 1,
    parameter integer FEAT_UART   = 1,
    // ---- 颜色(RGB444) ----
    parameter [11:0] COL_BG     = 12'h012,
    parameter [11:0] COL_GRID   = 12'h151,
    parameter [11:0] COL_AXIS   = 12'h2A2,
    parameter [11:0] COL_CH0    = 12'h1F1,
    parameter [11:0] COL_CH1    = 12'hFF1,
    parameter [11:0] COL_TEXT   = 12'hFFF
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  ch0_in,
    input  wire [9:0]  ch1_in,
    input  wire        key_in,

    // ---- 串口在线配置(特性4) ----
    input  wire        cfg_tb_we,
    input  wire [15:0] cfg_tb,
    input  wire        cfg_run_we,
    input  wire        cfg_run,
    input  wire        cfg_ten_we,
    input  wire        cfg_ten,
    input  wire        cfg_lvl_we,
    input  wire [9:0]  cfg_lvl,
    input  wire        cfg_edg_we,
    input  wire        cfg_edg,
    input  wire        cfg_scr_we,
    input  wire        cfg_scr,

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
        .clk   (clk),
        .rst   (rst),
        .pix_ce(pix_ce),
        .hs    (hs),
        .vs    (vs),
        .de    (de),
        .px    (px),
        .py    (py)
    );

    // 帧起始脉冲(用于测量窗口/滚动基准)
    reg vs_d;
    always @(posedge clk) vs_d <= vs;
    wire frame = vs & (~vs_d);

    //------------------------------------------------------------------
    // APP: 配置/按键(串口配置受 FEAT_UART 控制)
    //------------------------------------------------------------------
    wire        run, arm;
    wire [15:0] tb_div;
    wire        trig_en, trig_edge, scroll_en;
    wire [9:0]  trig_level;

    scope_app u_app (
        .clk       (clk),
        .rst       (rst),
        .key_in    (key_in),
        .ext_tb_we (FEAT_UART ? cfg_tb_we  : 1'b0),
        .ext_tb    (cfg_tb),
        .ext_run_we(FEAT_UART ? cfg_run_we : 1'b0),
        .ext_run   (cfg_run),
        .ext_ten_we(FEAT_UART ? cfg_ten_we : 1'b0),
        .ext_ten   (cfg_ten),
        .ext_lvl_we(FEAT_UART ? cfg_lvl_we : 1'b0),
        .ext_lvl   (cfg_lvl),
        .ext_edg_we(FEAT_UART ? cfg_edg_we : 1'b0),
        .ext_edg   (cfg_edg),
        .ext_scr_we(FEAT_UART ? cfg_scr_we : 1'b0),
        .ext_scr   (cfg_scr),
        .tb_div    (tb_div),
        .run       (run),
        .arm       (arm),
        .trig_en   (trig_en),
        .trig_level(trig_level),
        .trig_edge (trig_edge),
        .scroll_en (scroll_en),
        .tb_idx    (),
        .ev_short_o(),
        .ev_long_o ()
    );

    //------------------------------------------------------------------
    // HAL: 采样缓存 + APP: 采集引擎
    //------------------------------------------------------------------
    wire [9:0] s0, s1;
    wire        we0, we1;
    wire [DEPTH_LOG2-1:0] wa0, wa1;

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap0 (
        .clk       (clk),
        .rst       (rst),
        .din       (ch0_in),
        .rate_div  (tb_div),
        .run       (run),
        .arm       (arm),
        .trig_en   (FEAT_TRIG ? trig_en : 1'b0),
        .trig_level(trig_level),
        .trig_edge (trig_edge),
        .we        (we0),
        .waddr     (wa0),
        .trig_det  ()
    );

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap1 (
        .clk       (clk),
        .rst       (rst),
        .din       (ch1_in),
        .rate_div  (tb_div),
        .run       (run),
        .arm       (arm),
        .trig_en   (FEAT_TRIG ? trig_en : 1'b0),
        .trig_level(trig_level),
        .trig_edge (trig_edge),
        .we        (we1),
        .waddr     (wa1),
        .trig_det  ()
    );

    // 读地址: 普通模式读 0..639；滚动模式以帧起始写指针为基准(最新在最右)
    wire [9:0] raddr;
    generate
        if (FEAT_SCROLL != 0) begin : g_scroll
            reg [DEPTH_LOG2-1:0] rd_base;
            always @(posedge clk) begin
                if (rst)
                    rd_base <= {DEPTH_LOG2{1'b0}};
                else if (frame)
                    rd_base <= wa0;
            end
            assign raddr = scroll_en ? (rd_base - 10'd640 + px[9:0]) : px[9:0];
        end
        else begin : g_noscroll
            assign raddr = px[9:0];
        end
    endgenerate

    vram_sdp #(.DW(10), .AW(DEPTH_LOG2)) u_ram0 (
        .clk  (clk),
        .we   (we0),
        .waddr(wa0),
        .wdata(ch0_in),
        .raddr(raddr),
        .rdata(s0)
    );

    vram_sdp #(.DW(10), .AW(DEPTH_LOG2)) u_ram1 (
        .clk  (clk),
        .we   (we1),
        .waddr(wa1),
        .wdata(ch1_in),
        .raddr(raddr),
        .rdata(s1)
    );

    reg [9:0] s0_prev;
    reg [9:0] s1_prev;
    always @(posedge clk) begin
        s0_prev <= s0;
        s1_prev <= s1;
    end

    //------------------------------------------------------------------
    // APP: 自动测量(特性2)
    //------------------------------------------------------------------
    wire [9:0]  vpp;
    wire [15:0] freq;

    generate
        if (FEAT_MEAS != 0) begin : g_meas
            scope_meas u_meas (
                .clk  (clk),
                .rst  (rst),
                .din  (ch0_in),
                .tick (1'b1),
                .frame(frame),
                .vpp  (vpp),
                .freq (freq)
            );
        end
        else begin : g_nomeas
            assign vpp  = 10'd0;
            assign freq = 16'd0;
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
    ) u_grid (
        .px(px), .py(py), .de(de), .hit(g_hit), .color(g_col)
    );

    wire        t0_hit, t1_hit;
    wire [11:0] t0_col, t1_col;

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH0)
    ) u_tr0 (
        .px(px), .py(py), .de(de), .en(1'b1),
        .s_now(s0), .s_prev(s0_prev), .hit(t0_hit), .color(t0_col)
    );

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH1)
    ) u_tr1 (
        .px(px), .py(py), .de(de), .en(1'b1),
        .s_now(s1), .s_prev(s1_prev), .hit(t1_hit), .color(t1_col)
    );

    wire        tx_hit;
    wire [11:0] tx_col;

    text_layer #(
        .TEXT_Y0(TEXT_Y0), .TEXT_X0(TEXT_X0), .COLS(32), .COL(COL_TEXT)
    ) u_text (
        .px(px), .py(py), .de(de),
        .val0({6'd0, ch0_in}),
        .val1({6'd0, ch1_in}),
        .val2(tb_div),
        .val3({6'd0, vpp}),
        .val4(freq),
        .hit(tx_hit),
        .color(tx_col)
    );

    wire [11:0] rgb_comb;

    compositor u_comp (
        .txt_hit(tx_hit),  .txt_col(tx_col),
        .ch1_hit(t1_hit),  .ch1_col(t1_col),
        .ch0_hit(t0_hit),  .ch0_col(t0_col),
        .grid_hit(g_hit),  .grid_col(g_col),
        .bg_col(COL_BG),
        .rgb(rgb_comb)
    );

    //------------------------------------------------------------------
    // 输出寄存
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

            if (pix_ce)
                rgb_r <= rgb_comb;
        end
    end

    assign vga_rgb = rgb_r;
    assign vga_hs  = hs2;
    assign vga_vs  = vs2;
    assign vga_de  = de2;

endmodule
