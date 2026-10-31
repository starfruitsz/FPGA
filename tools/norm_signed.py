# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/abs/adc_norm.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""module adc_norm #(
    parameter integer DW    = 16,
    parameter integer RES   = 12,
    parameter integer ALIGN = 1
)(""", """module adc_norm #(
    parameter integer DW     = 16,
    parameter integer RES    = 12,
    parameter integer ALIGN  = 1,
    parameter integer SIGNED = 0     // 1=输入为补码，先转偏移二进制
)(""")
s = s.replace("""    localparam [DW-1:0] MASK = (1 << RES) - 1;
    wire [DW-1:0] norm = ALIGN ? (r_data >> (DW - RES)) : (r_data & MASK);""",
"""    localparam [DW-1:0] MASK = (1 << RES) - 1;
    // 补码 -> 偏移二进制：翻转最高位
    wire [DW-1:0] src  = SIGNED ? (r_data ^ {1'b1, {(DW-1){1'b0}}}) : r_data;
    wire [DW-1:0] norm = ALIGN ? (src >> (DW - RES)) : (src & MASK);""")
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('adc_norm SIGNED added')
