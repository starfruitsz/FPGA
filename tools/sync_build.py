# -*- coding: utf-8 -*-
import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
for a,b in [
 ('FPGA_TD/scope_eg4_59.al','FPGA_TD/scope_eg4_59.al'),
 ('FPGA_TD/full_flow59.tcl','FPGA_TD/full_flow59.tcl'),
 ('FPGA_TD/eg4/SparkRoad.sdc','FPGA_TD/eg4/SparkRoad.sdc'),
 ('FPGA_TD/eg4/bit/scope_eg4_59.bit','FPGA_TD/eg4/bit/scope_eg4_59.bit'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('README.md','README.md'),
]:
    os.makedirs(os.path.dirname(dst+'/'+b), exist_ok=True)
    shutil.copy2(src+'/'+a, dst+'/'+b)
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
old = dst+'/FPGA_TD/scope_eg4_56.al'
if os.path.exists(old): os.remove(old)
print('synced')
