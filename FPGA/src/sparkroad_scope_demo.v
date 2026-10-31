//==============================================================================
// 文件: sparkroad_scope_demo.v   顶层(演示)
// 用途: 不接 AD7606 时演示示波器 —— 用内部 50Hz 正弦代替 ADC 数据。
//   只是 sparkroad_scope_top 的一层包装：把 DEMO_SINE 置 1，其余完全一样。
//   引脚与 sparkroad_scope_top 完全相同，可直接用同一份 .adc 约束。
//   生产用顶层仍是 sparkroad_scope_top（DEMO_SINE 默认 0）。
//==============================================================================
`timescale 1ns / 1ps

module sparkroad_scope_demo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_l,        // H14
    input  wire        key_u,        // J13
    input  wire        key_d,        // G12
    input  wire        key_r,        // L12
    input  wire [8:0]  sw,           // SW0..SW8（SW8=N8 选工作模式）
    output wire        uart_tx,
    input  wire        uart_rx,
    // 并口 AD/DA 模块（24 脚，AD0/DA0 为最低位）
    input  wire        ad0,
    input  wire        ad1,
    input  wire        ad2,
    input  wire        ad3,
    input  wire        ad4,
    input  wire        ad5,
    input  wire        ad6,
    input  wire        ad7,
    input  wire        ad8,
    input  wire        ad9,
    output wire        adclk,        // ADCLK = 24MHz/8 = 3MHz
    output wire        da0,
    output wire        da1,
    output wire        da2,
    output wire        da3,
    output wire        da4,
    output wire        da5,
    output wire        da6,
    output wire        da7,
    output wire        da8,
    output wire        da9,
    output wire        daclk,        // DACLK = 24MHz/8 = 3MHz
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_clk,
    output wire [7:0]  seg,
    output wire [3:0]  sel,
    output wire [15:0] led
);
    sparkroad_scope_top #(
        .CLK_HZ(24_000_000),
        .TX_MODE(0),
        .DEMO_SINE(1)          // <<< 演示：内部 50Hz 正弦
    ) u_top (
        .clk(clk), .rst_n(rst_n),
        .key_l(key_l), .key_u(key_u), .key_d(key_d), .key_r(key_r), .sw(sw),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .ad0(ad0), .ad1(ad1), .ad2(ad2), .ad3(ad3), .ad4(ad4),
        .ad5(ad5), .ad6(ad6), .ad7(ad7), .ad8(ad8), .ad9(ad9),
        .adclk(adclk),
        .da0(da0), .da1(da1), .da2(da2), .da3(da3), .da4(da4),
        .da5(da5), .da6(da6), .da7(da7), .da8(da8), .da9(da9),
        .daclk(daclk),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel), .led(led)
    );
endmodule