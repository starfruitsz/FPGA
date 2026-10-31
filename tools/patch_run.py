# -*- coding: utf-8 -*-
import io
t = r'C:/Users/Administrator/Desktop/task/FPGA_TD/scope_eg4_56_Runs/syn_1/scope_eg4_56.tcl'
s = io.open(t, encoding='utf-8', errors='replace').read()
old = 'import_device  -package'
assert old in s, 'pattern missing'
s = s.replace(old, 'import_device eagle_s20.db -package EG4S20BG256', 1)
io.open(t,'w',encoding='utf-8').write(s)
print('patched')
