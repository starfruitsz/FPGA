# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/PROJECT_STATE.md'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('对应提交待填（连续发送版本）', '对应提交：当前分支最新提交（连续发送版本）')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('placeholder fixed')

import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
for a,b in [
 ('FPGA/src/sparkroad_scope_top.v','FPGA/src/sparkroad_scope_top.v'),
 ('FPGA/src/adda.v','FPGA/src/adda.v'),
 ('FPGA/src/vga/adda_scope_top.v','FPGA/src/vga/adda_scope_top.v'),
 ('FPGA_TD/scope_eg4_60.al','FPGA_TD/scope_eg4_60.al'),
 ('FPGA_TD/full_flow60.tcl','FPGA_TD/full_flow60.tcl'),
 ('FPGA_TD/eg4/bit/scope_eg4_60.bit','FPGA_TD/eg4/bit/scope_eg4_60.bit'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('PROJECT_STATE.md','PROJECT_STATE.md'),
 ('README.md','README.md'),
]:
    os.makedirs(os.path.dirname(dst+'/'+b), exist_ok=True)
    shutil.copy2(src+'/'+a, dst+'/'+b)
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
# 删除旧版本工程/比特
for old in ['FPGA_TD/scope_eg4_59.al','FPGA_TD/eg4/bit/scope_eg4_59.bit','FPGA_TD/full_flow59.tcl','FPGA_TD/scope_eg4_59_Runs']:
    p = dst+'/'+old
    if os.path.isdir(p):
        shutil.rmtree(p, ignore_errors=True)
    elif os.path.exists(p):
        os.remove(p)
print('synced')
