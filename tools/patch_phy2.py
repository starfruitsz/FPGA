# -*- coding: utf-8 -*-
import io
t = r'C:/Users/Administrator/Desktop/task/FPGA_TD/scope_eg4_56_Runs/phy_1/scope_eg4_56.tcl'
s = io.open(t, encoding='utf-8', errors='replace').read()
s = s.replace('open_project {scope_eg4_56.prj} -phy',
              'open_project {C:/Users/Administrator/Desktop/task/FPGA_TD/scope_eg4_56_Runs/phy_1/scope_eg4_56.prj} -phy')
s = s.replace('import_db {../syn_1/scope_eg4_56_gate.db}',
              'import_db {C:/Users/Administrator/Desktop/task/FPGA_TD/scope_eg4_56_Runs/syn_1/scope_eg4_56_gate.db}')
io.open(t,'w',encoding='utf-8').write(s)
print('paths patched')
