# -*- coding: utf-8 -*-
import io

# 1) scope_capture: 增加 sample_valid 端口 + tick 门控
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_capture.v'
s = io.open(p, encoding='utf-8', newline='').read()
old = "    input  wire [15:0]             rate_div,"
new = old + "\n    input  wire                    sample_valid,   // ADC 采样有效(来自 HAL)"
assert old in s
s = s.replace(old, new, 1)
old2 = "    wire tick = (rate_cnt == rate_div);"
new2 = "    wire tick = sample_valid && (rate_cnt == rate_div);"
assert old2 in s
s = s.replace(old2, new2, 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('scope_capture patched')

# 2) vga_scope_top: adc_valid 端口 + 两个 capture 连接
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/vga_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
old = "    input  wire [9:0]  ch1_in,"
new = old + "\n    input  wire        adc_valid,   // ADC 采样有效(S2: 由 adc_top 提供)"
assert old in s
s = s.replace(old, new, 1)
old2 = "        .rate_div(tb_div), .run(run), .arm(arm),"
new2 = "        .rate_div(tb_div), .sample_valid(adc_valid), .run(run), .arm(arm),"
assert s.count(old2) == 2, s.count(old2)
s = s.replace(old2, new2)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('vga_scope_top patched')

# 3) adda_scope_top: 例化 adc_top，ch0 走 HAL 流
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/adda_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
anchor = "    //------------------------------------------------------------------\n    // 串口配置通道(特性4)"
assert anchor in s
adc = """    //------------------------------------------------------------------
    // ADC 硬件抽象层(S1/S2): 并行基线模型 -> 归一化采样流
    //   换 SPI 型号时只改 IMPL 参数并在 hal/ 下实现驱动，应用层不动
    //------------------------------------------------------------------
    wire [15:0] adc_s_data;
    wire        adc_s_valid, adc_locked, adc_error;

    adc_top #(
        .IMPL (1),      // 0=stub 1=par(基线) 2=spi
        .RES  (10),
        .ALIGN(0),      // 当前板载并行数据右对齐
        .CH   (1)
    ) u_adc (
        .clk      (sys_clk),
        .rst      (~sys_rst_n),
        .csr_addr (8'd0),
        .csr_wdata(32'd0),
        .csr_we   (1'b0),
        .csr_rdata(),
        .adc_din  ({6'd0, ad_date}),
        .spi_sclk (),
        .spi_cs_n (),
        .spi_mosi (),
        .spi_miso (1'b0),
        .s_data   (adc_s_data),
        .s_ch     (),
        .s_valid  (adc_s_valid),
        .s_ready  (1'b1),
        .locked   (adc_locked),
        .error    (adc_error)
    );

"""
s = s.replace(anchor, adc + anchor, 1)
old3 = "                .ch0_in    (ad_date),"
new3 = "                .ch0_in    (adc_s_data[9:0]),\n                .adc_valid (adc_s_valid),"
assert old3 in s
s = s.replace(old3, new3, 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('adda_scope_top patched')
