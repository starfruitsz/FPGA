//==============================================================================
// 文件: sparkroad_scope_pll.v   顶层(PLL 60Hz 版)
// 目的: 24MHz 晶振做不出标准 640x480@60（需要 25.175MHz），
//       用 Eagle 片内 PLL 把 24MHz 倍频到 25.2MHz：
//           VCO    = 24MHz x 21 = 504MHz
//           CLKOUT = 504MHz / 20 = 25.2MHz
//       25.2MHz / (800 x 525) = 60.00Hz -> 行频 31.5kHz、场频 60Hz，标准时序。
//       整个设计跑 25.2MHz（串口/消抖/ADC 都按 CLK_HZ 参数换算）。
// 说明: 原 24MHz 版本 sparkroad_scope_top 保持不变（24MHz -> 57.14Hz）。
//==============================================================================
`timescale 1ns / 1ps

module sparkroad_scope_pll (
    input  wire        clk,          // 24MHz (K14)
    input  wire        rst_n,        // BUTTON_C
    input  wire        key_l,        // BUTTON_L (H14)
    input  wire        key_u,        // BUTTON_U (J13)
    input  wire        key_d,        // BUTTON_D (G12)
    input  wire        key_r,        // BUTTON_R (L12)
    input  wire [7:0]  sw,           // SW0..SW7 拨动开关
    output wire        uart_tx,
    input  wire        uart_rx,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_clk,
    output wire [7:0]  seg,
    output wire [3:0]  sel,
    output wire [15:0] led,
    output wire        ad7606_convst,
    input  wire        ad7606_busy,
    output wire        ad7606_cs_n,
    output wire        ad7606_sclk,
    input  wire        ad7606_douta,
    output wire        ad7606_reset,
    output wire        ad7606_ser
);

    //------------------------------------------------------------------
    // PLL: 24MHz -> 25.2MHz
    //------------------------------------------------------------------
    wire [4:0] pll_clk;
    wire       pll_lock;

    EG_PHY_PLL #(
        .REFCLK_DIV   (1),
        .FBCLK_DIV    (21),
        .CLKC0_DIV    (20),
        .CLKC0_CPHASE (1),
        .CLKC0_ENABLE ("ENABLE"),
        .FEEDBK_MODE  ("NORMAL"),
        .FEEDBK_PATH  ("VCO_PHASE_0"),
        .PLLRST_ENA   ("ENABLE"),
        .STDBY_ENABLE ("ENABLE")
    ) u_pll (
        .clkc     (pll_clk),
        .extlock  (pll_lock),
        .refclk   (clk),
        .reset    (~rst_n),
        .fbclk    (1'b0),
        .stdby    (1'b0),
        .load_reg (1'b0),
        .psdone   (),
        .psclk    (1'b0),
        .psdown   (1'b0),
        .psstep   (1'b0),
        .psclksel (3'b000),
        .do       (),
        .dclk     (1'b0),
        .dcs      (1'b0),
        .dwe      (1'b0),
        .di       (8'd0),
        .daddr    (6'd0)
    );

    wire sys_clk   = pll_clk[0];
    wire sys_rst_n = rst_n & pll_lock;      // PLL 锁定前保持复位

    //------------------------------------------------------------------
    // 示波器（演示：内部 50Hz 正弦），整体跑 25.2MHz
    //------------------------------------------------------------------
    sparkroad_scope_top #(
        .CLK_HZ    (25_200_000),
        .TX_MODE   (0),
        .DEMO_SINE (1)
    ) u_top (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_l(key_l), .key_u(key_u), .key_d(key_d), .key_r(key_r), .sw(sw),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel), .led(led),
        .ad7606_convst(ad7606_convst), .ad7606_busy(ad7606_busy),
        .ad7606_cs_n(ad7606_cs_n), .ad7606_sclk(ad7606_sclk),
        .ad7606_douta(ad7606_douta), .ad7606_reset(ad7606_reset),
        .ad7606_ser(ad7606_ser)
    );

endmodule