//==============================================================================
// 文件: sparkroad_vga_test.v   顶层(诊断)
// 用途: 只用 VGA 自检图案（彩条/灰阶/棋盘/边框/文字）驱动板上的 VGA 口。
//   不含采集、RAM、ADC，用来**分离"显示链路"和"示波器逻辑"**。
//   端口与 sparkroad_scope_top 完全一致（未用的输出接常量），
//   因此可以直接复用同一份 SparkRoad.adc 约束。
//==============================================================================
`timescale 1ns / 1ps

module sparkroad_vga_test (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key,
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
    output wire        ad7606_convst,
    input  wire        ad7606_busy,
    output wire        ad7606_cs_n,
    output wire        ad7606_sclk,
    input  wire        ad7606_douta,
    output wire        ad7606_reset,
    output wire        ad7606_ser
);
    wire [11:0] rgb;
    wire hs, vs, de;

    vga_test_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(1),
        .AUTO_FRAMES(120)
    ) u_test (
        .clk(clk), .rst(~rst_n), .key_in(key),
        .vga_rgb(rgb), .vga_hs(hs), .vga_vs(vs), .vga_de(de)
    );

    assign vga_r = {rgb[11:8], rgb[11:8]};
    assign vga_g = {rgb[7:4],  rgb[7:4]};
    assign vga_b = {rgb[3:0],  rgb[3:0]};
    assign vga_hs  = hs;
    assign vga_vs  = vs;
    assign vga_clk = clk;

    assign seg = 8'hFF;              // 共阳，全灭
    assign sel = 4'h0;

    // 未使用的接口接常量，满足约束文件
    assign uart_tx       = 1'b1;
    assign ad7606_convst = 1'b0;
    assign ad7606_cs_n   = 1'b1;
    assign ad7606_sclk   = 1'b1;
    assign ad7606_reset  = 1'b0;
    assign ad7606_ser    = 1'b1;
endmodule
