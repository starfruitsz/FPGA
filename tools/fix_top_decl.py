# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/vga_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
block = """    wire [9:0] s0, s1;
    wire        we0, we1;
    wire [DEPTH_LOG2-1:0] wa0, wa1;
    wire        done0, done1, trig_det0;
    wire [DEPTH_LOG2-1:0] rd_base0, rd_base1;
    wire [1:0]  state0, state1;
"""
assert block in s, 'block not found'
s = s.replace(block, '', 1)
anchor = '    scope_app u_app ('
assert anchor in s
s = s.replace(anchor, block + '\n' + anchor, 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('declarations moved before scope_app')
