# -*- coding: utf-8 -*-
import io, os, shutil
src = r'C:/Users/Administrator/Desktop/task'
dst = r'C:/Users/Administrator/Desktop/task/_remote'
def cp(a,b):
    os.makedirs(os.path.dirname(b), exist_ok=True)
    shutil.copy2(a,b)
pairs = [
 ('FPGA/src/sparkroad_scope_top.v','FPGA/src/sparkroad_scope_top.v'),
 ('FPGA/src/vga/app/scope_app.v','FPGA/src/vga/app/scope_app.v'),
 ('FPGA/src/vga/vga_scope_top.v','FPGA/src/vga/vga_scope_top.v'),
 ('FPGA/project_2025_11_07.gprj','FPGA/project_2025_11_07.gprj'),
 ('FPGA_TD/project_2025_11_07_TD.al','FPGA_TD/project_2025_11_07_TD.al'),
 ('FPGA_TD/EG4S20BG256_scope.al','FPGA_TD/EG4S20BG256_scope.al'),
 ('FPGA_TD/eg4/files.list','FPGA_TD/eg4/files.list'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('doc/main.tex','doc/main.tex'),
 ('README.md','README.md'),
]
for a,b in pairs:
    cp(os.path.join(src,a), os.path.join(dst,b))
shutil.copy2(os.path.join(src,'doc/main.pdf'), os.path.join(dst,'doc/main.pdf'))
shutil.copy2(os.path.join(src,'doc/main.pdf'), os.path.join(dst,'FPGA_project_analysis.pdf'))
shutil.copy2(os.path.join(src,'doc/main.pdf'), os.path.join(src,'FPGA_project_analysis.pdf'))
print('synced')
