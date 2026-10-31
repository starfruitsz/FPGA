# -*- coding: utf-8 -*-
import io
paths = [l.strip() for l in io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/all.list', encoding='utf-8') if l.strip()]
lines = ['cd C:/Users/Administrator/Desktop/task/FPGA_TD', 'open_project EG4S20BG256_scope56.al']
for p in paths:
    lines.append('add_files ' + p)
lines.append('save_project_as -name EG4S20BG256_scope56 -dir . -force')
lines.append('exit')
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/add_all56.tcl','w',encoding='utf-8',newline='').write('\n'.join(lines)+'\n')
print('tcl lines:', len(lines))
