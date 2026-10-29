//==============================================================================
// 层: 集成顶层  文件: adda_scope_top.v
// 功能: 原 AD/DA 工程(adda) + VGA 示波器(vga_scope_top) + 串口配置接收
//
// 连接:
//   CH0 = ad_date (外部 ADC 码值)
//   CH1 = ad_out  (送 DAC 的数据，即控制量/回环量)
//   串口: 复用同一个 rx 引脚
//         - adda 内部 uart_rx 解析二进制 A/B 参数帧(原有功能)
//         - 这里再加一路 uart_rx + scope_cmd 解析 ASCII 命令(特性4):
//           T<hex4> 时基  R<0/1> 运行  A<0/1> 触发  L<hex3> 电平
//           E<0/1> 边沿  S<0/1> 滚动           每条命令以 CR/LF 结尾
//
// 特性开关: 见 vga_scope_top 的 FEAT_TRIG/FEAT_MEAS/FEAT_SCROLL/FEAT_UART
//==============================================================================
`timescale 1ns / 1ps

//
// ============================ 怎么读这个文件 ============================
// 这是新的“工程总顶层”，把三部分装在一起：
//   1) 原有 AD/DA 工程 adda（一行都没改）；
//   2) VGA 显示（示波器或屏幕自检，由 TEST_MODE 选择）；
//   3) 串口配置通道（第二路 uart_rx + ASCII 命令解析）。
// 注意：VGA 显示只“看” ad_date / ad_out，不干涉原来的信号通路。
// ======================================================================
module adda_scope_top #(
    // [P5] 串口上报方式（透传给 adda）
    parameter integer UART_MODE = 1,   // 0=连续发送  1=按标志位定时发送
    parameter integer REPORT_MS = 26   // 标志位模式下的上报周期(ms)
)( 
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire [9:0]  ad_date,
    input  wire        key_in,
    input  wire        ad_clk,
    input  wire        da_clk,

    input  wire        rx,

    output wire        ad_clk1,
    output wire        da_clk1,
    output wire [9:0]  ad_out,
    output wire [3:0]  sel,
    output wire [7:0]  seg,
    output wire        tx,
    output wire        led0,
    output wire        led6,
    output wire        led7,

    // VGA 输出(RGB444，按 DAC 位数取高位)
    output wire [11:0] vga_rgb,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_de
);

    //==================================================================
    // 特性开关(一处配置, 0=关闭 1=开启)
    //==================================================================
//------------------------------------------------------------------
// [特性开关] 四个 1bit 开关，直接传给 vga_scope_top 的参数。
// 改这里比改内部代码安全得多：关掉某个特性，对应逻辑不会进入网表。
//------------------------------------------------------------------
    localparam integer FEAT_TRIG   = 1;   // 特性1 触发对齐
    localparam integer FEAT_MEAS   = 1;   // 特性2 自动测量
    localparam integer FEAT_SCROLL = 1;   // 特性3 滚动显示
    localparam integer FEAT_UART   = 1;   // 特性4 串口在线配置

    //==================================================================
    // 屏幕自检开关: 1 = VGA 口输出自检图案(不依赖 AD/DA)，0 = 正常示波器
    // 自检画面约 2s 自动切换，短按按键手动切换(彩条/灰阶/棋盘/边框+方块/文字)
    //==================================================================
//------------------------------------------------------------------
// [屏幕自检开关] 1 = VGA 口输出测试图案（彩条/灰阶/棋盘/边框/文字），
// 0 = 正常示波器。调试屏幕时先置 1，确认屏幕没问题后再改回 0。
//------------------------------------------------------------------
    localparam integer TEST_MODE   = 0;

    //------------------------------------------------------------------
    // 原工程
    //------------------------------------------------------------------
//------------------------------------------------------------------
// [原有工程] 端口一一对应，内部逻辑完全没有改动。
// ad_out 既送给 DAC，也送给示波器的 CH1，用来观察控制量。
//------------------------------------------------------------------
    adda #(
        .UART_MODE(UART_MODE),
        .REPORT_MS(REPORT_MS)
    ) u_adda (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .ad_date  (ad_date),
        .key_in   (key_in),
        .ad_clk   (ad_clk),   // P9 已回撤：保留端口(本设计未使用)
        .da_clk   (da_clk),
        .rx       (rx),
        .ad_clk1  (ad_clk1),
        .da_clk1  (da_clk1),
        .ad_out   (ad_out),
        .sel      (sel),
        .seg      (seg),
        .tx       (tx),
        .led0     (led0),
        .led6     (led6),
        .led7     (led7)
    );

    //------------------------------------------------------------------
    // 串口配置通道(特性4): 独立的 uart_rx + ASCII 命令解析
    //------------------------------------------------------------------
    wire [7:0] cfg_data;
    wire       cfg_valid;

//------------------------------------------------------------------
// [串口配置通道] 同一根 rx 引脚上再挂一个接收器，专门解析 ASCII 命令。
// 原来的二进制 A/B 参数帧仍由 adda 内部的 uart_rx 处理，两者互不干扰。
//------------------------------------------------------------------
    uart_rx #(
        .UART_BPS (115200),
        .CLK_FREQ (50_000_000)
    ) u_cfg_rx (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx       (rx),
        .po_data  (cfg_data),
        .po_flag  (cfg_valid)
    );

    wire        c_tb_we, c_run_we, c_ten_we, c_edg_we, c_scr_we, c_lvl_we;
    wire [15:0] c_tb;
    wire        c_run, c_ten, c_edg, c_scr;
    wire [9:0]  c_lvl;
    wire        c_tmode_we, c_tsrc_we, c_pre_we, c_hold_we;
    wire [1:0]  c_tmode;
    wire        c_tsrc;
    wire [9:0]  c_pre;
    wire [15:0] c_hold;

//------------------------------------------------------------------
// [APP] 把字节流解析成“写使能 + 数值”，送给 vga_scope_top 的 cfg_* 端口。
//------------------------------------------------------------------
    scope_cmd u_cmd (
        .clk     (sys_clk),
        .rst     (~sys_rst_n),
        .rx_data (cfg_data),
        .rx_valid(cfg_valid),
        .tb_we   (c_tb_we),
        .tb_val  (c_tb),
        .run_we  (c_run_we),
        .run_val (c_run),
        .ten_we  (c_ten_we),
        .ten_val (c_ten),
        .lvl_we  (c_lvl_we),
        .lvl_val (c_lvl),
        .edg_we  (c_edg_we),
        .edg_val (c_edg),
        .scr_we  (c_scr_we),
        .scr_val (c_scr),
        .tmode_we(c_tmode_we),
        .tmode_val(c_tmode),
        .tsrc_we (c_tsrc_we),
        .tsrc_val(c_tsrc),
        .pre_we  (c_pre_we),
        .pre_val (c_pre),
        .hold_we (c_hold_we),
        .hold_val(c_hold)
    );

    //------------------------------------------------------------------
    // 示波器
    //------------------------------------------------------------------
//------------------------------------------------------------------
// [二选一] TEST_MODE=1 用自检顶层，否则用示波器顶层。
// 两者都输出同样的 vga_rgb/hs/vs/de，所以引脚约束完全通用。
// 用 generate 而不是两个都例化：没被选中的那一份不会占用任何资源。
//------------------------------------------------------------------
    generate
        if (TEST_MODE != 0) begin : g_test
            // ---- 屏幕自检: 只依赖 sys_clk / 复位 / 按键 ----
            vga_test_top u_test (
                .clk    (sys_clk),
                .rst    (~sys_rst_n),
                .key_in (key_in),
                .vga_rgb(vga_rgb),
                .vga_hs (vga_hs),
                .vga_vs (vga_vs),
                .vga_de (vga_de)
            );
        end
        else begin : g_scope
            vga_scope_top #(
                .FEAT_TRIG  (FEAT_TRIG),
                .FEAT_MEAS  (FEAT_MEAS),
                .FEAT_SCROLL(FEAT_SCROLL),
                .FEAT_UART  (FEAT_UART)
            ) u_scope (
                .clk       (sys_clk),
                .rst       (~sys_rst_n),
                .ch0_in    (ad_date),
                .ch1_in    (ad_out),
                .key_in    (key_in),
                .cfg_tb_we (c_tb_we),
                .cfg_tb    (c_tb),
                .cfg_run_we(c_run_we),
                .cfg_run   (c_run),
                .cfg_ten_we(c_ten_we),
                .cfg_ten   (c_ten),
                .cfg_lvl_we(c_lvl_we),
                .cfg_lvl   (c_lvl),
                .cfg_edg_we(c_edg_we),
                .cfg_edg   (c_edg),
                .cfg_scr_we(c_scr_we),
                .cfg_scr   (c_scr),
                .cfg_tmode_we(c_tmode_we),
                .cfg_tmode (c_tmode),
                .cfg_tsrc_we(c_tsrc_we),
                .cfg_tsrc  (c_tsrc),
                .cfg_pre_we(c_pre_we),
                .cfg_pre   (c_pre),
                .cfg_hold_we(c_hold_we),
                .cfg_hold  (c_hold),
                .vga_rgb   (vga_rgb),
                .vga_hs    (vga_hs),
                .vga_vs    (vga_vs),
                .vga_de    (vga_de)
            );
        end
    endgenerate

endmodule
