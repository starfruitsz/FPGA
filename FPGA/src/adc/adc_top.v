//==============================================================================
// 层: ADC 顶层(工厂)  文件: adc_top.v
// 功能: 按 IMPL 选择型号驱动，统一归一化后输出应用层采样流。
//   新增型号: 在 generate 里加一个分支 + 在 hal/ 下加驱动文件。
//   配置: 通过 CSR 总线(adc_cfg)，新增参数只加地址不改端口。
//==============================================================================
`timescale 1ns / 1ps

module adc_top #(
    parameter integer IMPL  = 1,     // 0=stub 1=par 2=spi
    parameter integer RES   = 10,    // 有效分辨率
    parameter integer ALIGN = 0,     // 0=右对齐 1=左对齐
    parameter integer CH    = 1,     // 通道数
    parameter integer DW    = 16,    // 归一化位宽
    parameter integer RW    = 16     // 原始流位宽
)(
    input  wire          clk,
    input  wire          rst,
    // CSR
    input  wire [7:0]    csr_addr,
    input  wire [31:0]   csr_wdata,
    input  wire          csr_we,
    output wire [31:0]   csr_rdata,
    // 并行 ADC 引脚
    input  wire [15:0]   adc_din,
    // SPI ADC 引脚
    output wire          spi_sclk,
    output wire          spi_cs_n,
    output wire          spi_mosi,
    input  wire          spi_miso,
    // 归一化采样流
    output wire [DW-1:0] s_data,
    output wire [1:0]    s_ch,
    output wire          s_valid,
    input  wire          s_ready,
    output wire          locked,
    output wire          error
);
    wire          enable;
    wire [15:0]   rate;
    wire [7:0]    gain;
    wire [15:0]   offset;
    wire [3:0]    ch_en;
    wire          fmt_align, fmt_signed;

    wire [RW-1:0] r_data;
    wire [1:0]    r_ch;
    wire          r_valid;
    wire          r_ready;
    wire          b_locked, b_error;

    adc_cfg #(
        .IMPL(IMPL), .RES(RES), .ALIGN(ALIGN), .CH(CH), .DW(DW)
    ) u_cfg (
        .clk(clk), .rst(rst),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_we(csr_we),
        .csr_rdata(csr_rdata),
        .status_locked(b_locked), .status_error(b_error),
        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed)
    );

    generate
        if (IMPL == 2) begin : g_spi
            adc_spi #(
                .RW(RW), .BITS(RES)
            ) u_spi (
                .clk(clk), .rst(rst), .enable(enable), .rate(rate),
                .sclk(spi_sclk), .cs_n(spi_cs_n), .mosi(spi_mosi), .miso(spi_miso),
                .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
                .locked(b_locked), .error(b_error)
            );
        end
        else if (IMPL == 1) begin : g_par
            adc_par #(
                .RW(RW), .RES(RES)
            ) u_par (
                .clk(clk), .rst(rst), .enable(enable), .rate(rate),
                .adc_din(adc_din),
                .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
                .locked(b_locked), .error(b_error)
            );
            assign spi_sclk = 1'b0;
            assign spi_cs_n = 1'b1;
            assign spi_mosi = 1'b0;
        end
        else begin : g_stub
            adc_stub #(
                .RW(RW)
            ) u_stub (
                .clk(clk), .rst(rst), .enable(enable), .rate(rate),
                .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
                .locked(b_locked), .error(b_error)
            );
            assign spi_sclk = 1'b0;
            assign spi_cs_n = 1'b1;
            assign spi_mosi = 1'b0;
        end
    endgenerate

    adc_norm #(
        .DW(DW), .RES(RES), .ALIGN(ALIGN)
    ) u_norm (
        .clk(clk), .rst(rst),
        .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
        .s_data(s_data), .s_ch(s_ch), .s_valid(s_valid), .s_ready(s_ready)
    );

    assign locked = b_locked;
    assign error  = b_error;
endmodule
