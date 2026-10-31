# -*- coding: utf-8 -*-
import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
def cp(a,b):
    os.makedirs(os.path.dirname(b), exist_ok=True)
    shutil.copy2(a,b)
for a,b in [
 ('FPGA_TD/scope_eg4.al','FPGA_TD/scope_eg4.al'),
 ('FPGA_TD/make_scope_eg4.tcl','FPGA_TD/make_scope_eg4.tcl'),
 ('FPGA_TD/eg4_35.list','FPGA_TD/eg4_35.list'),
 ('FPGA_TD/eg4/README.md','FPGA_TD/eg4/README.md'),
 ('tools/install_td56.ps1','tools/install_td56.ps1'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('README.md','README.md'),
]:
    cp(src+'/'+a, dst+'/'+b)
cp(src+'/doc/main.pdf', dst+'/doc/main.pdf')
cp(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
cp(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
print('synced')
