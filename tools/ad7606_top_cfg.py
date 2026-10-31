# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/adc_ad7606_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""module adc_ad7606_top #(
    parameter integer RES     = 10,
    parameter integer DW      = 16,
    parameter integer SPI_DIV = 4
)(""", """module adc_ad7606_top #(
    parameter integer RES       = 10,
    parameter integer DW        = 16,
    parameter integer SDIV_DEF  = 4,     // SCLK 半周期默认值(可在 0x28 改)
    parameter integer OS_DEF    = 0,     // 过采样默认值(0x24)
    parameter integer RANGE_DEF = 1      // 1=±10V 0=±5V (0x20)
)(""")
s = s.replace("""    wire [15:0] r_data;""", """    wire [15:0] cfg_sdiv;
    wire [2:0]  cfg_os;
    wire        cfg_range;

    wire [15:0] r_data;""")
s = s.replace("""    adc_cfg #(
        .IMPL(3), .RES(RES), .ALIGN(1), .CH(4), .DW(DW)
    ) u_cfg (""", """    adc_cfg #(
        .IMPL(3), .RES(RES), .ALIGN(1), .CH(4), .DW(DW),
        .SDIV_DEF(SDIV_DEF), .OS_DEF(OS_DEF), .RANGE_DEF(RANGE_DEF)
    ) u_cfg (""")
s = s.replace("""        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed)
    );""", """        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed),
        .sdiv(cfg_sdiv), .os_sel(cfg_os), .range_sel(cfg_range)
    );""")
s = s.replace("""    adc_ad7606_spi #(
        .RW(16), .SPI_DIV(SPI_DIV)
    ) u_drv (
        .clk(clk), .rst(rst), .enable(enable), .rate(rate),""", """    adc_ad7606_spi #(
        .RW(16)
    ) u_drv (
        .clk(clk), .rst(rst), .enable(enable), .rate(rate),
        .sdiv(cfg_sdiv), .os_sel(cfg_os), .range_sel(cfg_range),""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('ad7606 top updated')
