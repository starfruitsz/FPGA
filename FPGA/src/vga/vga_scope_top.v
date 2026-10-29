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

//
// ============================ 怎么读这个文件 ============================
// 这是示波器的“总装车间”：自己不算任何算法，只负责三件事——
//   1) 例化各层模块，把线接对；
//   2) 提供所有可配置参数（分辨率、颜色、布局、特性开关）；
//   3) 处理好“像素流水线”的时序对齐（本文件最容易看晕的地方，见下面说明）。
//
// 【像素流水线】BSRAM 是同步读，地址给出去要等 1 拍才有数据，所以：
//   第 1 拍(前半像素)：给 RAM 地址，同时图层用上一拍的数据算？——不行，会错位。
//   本设计的做法：一个像素占 2 个系统时钟(50MHz/2=25MHz)，
//   前半拍把地址给 RAM，后半拍数据出来后再算颜色，然后在 pix_ce 时打进出寄存器。
//   为了与像素数据对齐，hs/vs/de 也固定延迟 2 拍(正好 1 个像素)。
// 初学者如果只记一句话：**颜色和同步信号必须同时到达，否则画面会整体偏移**。
// ======================================================================
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

//------------------------------------------------------------------
// [HAL] 时序发生器：给出当前像素坐标 px/py、有效区 de、同步 hs/vs，
// 以及像素节拍 pix_ce（每 2 个系统时钟为 1）。
// 所有参数从本模块的 parameter 原样传下去，换分辨率只改顶层参数。
//------------------------------------------------------------------
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
//------------------------------------------------------------------
// [帧起始脉冲] 用场同步 vs 的上升沿表示“新的一帧开始了”。
// 它用来：① 自动测量的统计窗口清零；② 滚动模式锁存写指针基准。
// 只打一拍 vs_d 再做 (vs & ~vs_d) 就得到一个时钟宽的脉冲，这是边沿检测的标准写法。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [APP] 设置面板：时基、运行/冻结、触发、滚动，全部由它保存。
// FEAT_UART 决定串口写入是否生效：关闭时把 we 强制接 0（综合会整块优化掉）。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [APP] 两路采集引擎：CH0 采 ad_date，CH1 采 ad_out。
// 两路共用同一个 tb_div 与 run/arm，所以采样时刻严格同步，
// 屏幕上看到的两条波形才是同一时间轴的。
// FEAT_TRIG=0 时把 trig_en 接 0，触发逻辑不生效（但模块本身还在，代价很小）。
//------------------------------------------------------------------
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
//------------------------------------------------------------------
// [读地址] 普通模式：读地址就是像素列号 px（显示缓冲区前 640 点）。
// 滚动模式：以“帧起始时的写指针”为基准，读 rd_base-640+px，
// 这样最右边永远是最新采样，画面看起来是从左往右滚动。
// 用 generate 的好处：FEAT_SCROLL=0 时整段滚动逻辑不进入网表。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [HAL] 采样缓存：每个通道一块 1024x10 的 BSRAM。
// 写：地址/数据来自采集引擎；读：地址用上面算出的 raddr。
// 注意读写都用同一个 clk，属于“简单双口”，综合器会自动识别成 BSRAM。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// s_prev 保存“上一列”的采样值。
// RAM 读出来的是当前列的 s_now，把它打一拍就得到上一列的值，
// 两者都送进 trace_layer，才能在相邻两点之间补出一根竖线。
//------------------------------------------------------------------
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
//------------------------------------------------------------------
// [APP] 自动测量：统计一帧内的峰峰值与过零次数，结果显示在文本第二行。
// FEAT_MEAS=0 时用 generate 换成常量 0，模块不例化。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [ABS] 图层 1：60 多根网格线 + 零电平轴。
//------------------------------------------------------------------
    grid_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .STEP(GRID_STEP), .AXIS_Y(AXIS_Y),
        .COL_GRID(COL_GRID), .COL_AXIS(COL_AXIS)
    ) u_grid (
        .px(px), .py(py), .de(de), .hit(g_hit), .color(g_col)
    );

    wire        t0_hit, t1_hit;
    wire [11:0] t0_col, t1_col;

//------------------------------------------------------------------
// [ABS] 图层 2/3：两路波形。注意 scale 参数 7/16 把 0..1023 映射到 0..447。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [ABS] 图层 4：底部两行文字。val0..val4 分别显示 AD/U/TB/VP/FR 的十六进制值。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// [ABS] 合成器：按“文字 > CH1 > CH0 > 网格 > 背景”的优先级选出最终颜色。
//------------------------------------------------------------------
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
//------------------------------------------------------------------
// [输出寄存] 这里是全设计最关键的 2 拍对齐：
//   rgb_r 只在 pix_ce 时更新（每像素一次）；
//   hs/vs/de 每拍都移入下一级，两级后正好延迟 2 个时钟 = 1 个像素；
//   于是输出到管脚时，颜色和同步信号是同一像素的，画面才不会斜。
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
