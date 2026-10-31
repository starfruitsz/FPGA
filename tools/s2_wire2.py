# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/adda_scope_top.v'
lines = io.open(p, encoding='utf-8', newline='').read().split('\n')
crlf = any(l.endswith('\r') for l in lines)
lines = [l[:-1] if l.endswith('\r') else l for l in lines]

i = next(k for k, l in enumerate(lines) if '串口配置通道(特性4)' in l)
ins = [
'    //------------------------------------------------------------------',
'    // ADC 硬件抽象层(S1/S2): 并行基线模型 -> 归一化采样流',
'    //   换 SPI 型号时只改 IMPL 参数并在 hal/ 下实现驱动，应用层不动',
'    //------------------------------------------------------------------',
'    wire [15:0] adc_s_data;',
'    wire        adc_s_valid, adc_locked, adc_error;',
'',
'    adc_top #(',
'        .IMPL (1),      // 0=stub 1=par(基线) 2=spi',
'        .RES  (10),',
'        .ALIGN(0),      // 当前板载并行数据右对齐',
'        .CH   (1)',
'    ) u_adc (',
'        .clk      (sys_clk),',
'        .rst      (~sys_rst_n),',
'        .csr_addr (8\'d0),',
'        .csr_wdata(32\'d0),',
'        .csr_we   (1\'b0),',
'        .csr_rdata(),',
'        .adc_din  ({6\'d0, ad_date}),',
'        .spi_sclk (),',
'        .spi_cs_n (),',
'        .spi_mosi (),',
'        .spi_miso (1\'b0),',
'        .s_data   (adc_s_data),',
'        .s_ch     (),',
'        .s_valid  (adc_s_valid),',
'        .s_ready  (1\'b1),',
'        .locked   (adc_locked),',
'        .error    (adc_error)',
'    );',
'',
]
lines[i-1:i-1] = ins

for k, l in enumerate(lines):
    if l.strip() == '.ch0_in    (ad_date),':
        lines[k] = '                .ch0_in    (adc_s_data[9:0]),\n                .adc_valid (adc_s_valid),'
        break

io.open(p, 'w', encoding='utf-8', newline='').write(('\r\n' if crlf else '\n').join(lines))
print('adda_scope_top patched at line', i)
