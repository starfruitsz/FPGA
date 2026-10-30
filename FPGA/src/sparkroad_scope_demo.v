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
    input  wire [3:0]  sw,           // SW0..SW3
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
    sparkroad_scope_top #(
        .CLK_HZ(24_000_000),
        .TX_MODE(0),
        .DEMO_SINE(1)          // <<< 演示：内部 50Hz 正弦
    ) u_top (
        .clk(clk), .rst_n(rst_n),
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