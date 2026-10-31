# -*- coding: utf-8 -*-
import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
for a,b in [
 ('FPGA_TD/scope_eg4_56.al','FPGA_TD/scope_eg4_56.al'),
 ('FPGA_TD/make_eg4_56b.tcl','FPGA_TD/make_eg4_56b.tcl'),
 ('TD56_open_project.jpg','TD56_open_project.jpg'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('README.md','README.md'),
]:
    shutil.copy2(src+'/'+a, dst+'/'+b)
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
# 删除旧工程文件（已由 scope_eg4_56.al 取代）
old = dst+'/FPGA_TD/scope_eg4.al'
if os.path.exists(old):
    os.remove(old)
print('synced')
