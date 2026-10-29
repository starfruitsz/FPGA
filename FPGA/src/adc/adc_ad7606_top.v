//==============================================================================
// 层: ADC 顶层(AD7606)  文件: adc_ad7606_top.v
// 功能: AD7606 串行模式的完整采集通道：CSR 配置 + SPI 时序 + 归一化。
//   输出统一采样流(默认 10bit，右对齐)：16bit 补码 -> 偏移二进制 -> 取高 10 位。
//   ch 只有 0..3（DOUTA 的 4 个通道）；如需 5..8 通道需再接 DOUTB。
//==============================================================================
`timescale 1ns / 1ps

module adc_ad7606_top #(
    parameter integer RES       = 10,
    parameter integer DW        = 16,
    parameter integer SDIV_DEF  = 4,     // SCLK 半周期默认值(可在 0x28 改)
    parameter integer OS_DEF    = 0,     // 过采样默认值(0x24)
    parameter integer RANGE_DEF = 1      // 1=±10V 0=±5V (0x20)
)(
    input  wire          clk,
    input  wire          rst,
    // CSR
    input  wire [7:0]    csr_addr,
    input  wire [31:0]   csr_wdata,
    input  wire          csr_we,
    output wire [31:0]   csr_rdata,
    // AD7606 引脚
    output wire          convst,
    output wire          cs_n,
    output wire          sclk,
    input  wire          douta,
    input  wire          busy,
    output wire          adc_reset,
    output wire          ser,
    output wire [2:0]    os,
    output wire          range,
    output wire          stby,
    // 采样流
    output wire [DW-1:0] s_data,
    output wire [1:0]    s_ch,
    output wire          s_valid,
    input  wire          s_ready,
    output wire          locked,
    output wire          error
);
    wire        enable;
    wire [15:0] rate;
    wire [7:0]  gain;
    wire [15:0] offset;
    wire [3:0]  ch_en;
    wire        fmt_align, fmt_signed;

    wire [15:0] cfg_sdiv;
    wire [2:0]  cfg_os;
    wire        cfg_range;

    wire [15:0] r_data;
    wire [1:0]  r_ch;
    wire        r_valid, r_ready;
    wire        b_locked, b_error;

    adc_cfg #(
        .IMPL(3), .RES(RES), .ALIGN(1), .CH(4), .DW(DW),
        .SDIV_DEF(SDIV_DEF), .OS_DEF(OS_DEF), .RANGE_DEF(RANGE_DEF)
    ) u_cfg (
        .clk(clk), .rst(rst),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_we(csr_we),
        .csr_rdata(csr_rdata),
        .status_locked(b_locked), .status_error(b_error),
        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed),
        .sdiv(cfg_sdiv), .os_sel(cfg_os), .range_sel(cfg_range)
    );

    adc_ad7606_spi #(
        .RW(16)
    ) u_drv (
        .clk(clk), .rst(rst), .enable(enable), .rate(rate),
        .sdiv(cfg_sdiv), .os_sel(cfg_os), .range_sel(cfg_range),
        .convst(convst), .cs_n(cs_n), .sclk(sclk), .douta(douta),
        .adc_reset(adc_reset), .ser(ser), .os(os), .range(range), .stby(stby),
        .busy(busy),
        .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
        .locked(b_locked), .error(b_error)
    );

    adc_norm #(
        .DW(DW), .RES(RES), .ALIGN(1), .SIGNED(1)
    ) u_norm (
        .clk(clk), .rst(rst),
        .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(r_ready),
        .s_data(s_data), .s_ch(s_ch), .s_valid(s_valid), .s_ready(s_ready)
    );

    assign locked = b_locked;
    assign error  = b_error;
endmodule
