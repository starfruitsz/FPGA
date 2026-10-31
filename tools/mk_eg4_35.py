# -*- coding: utf-8 -*-
import io
paths = [l.strip() for l in io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/all.list', encoding='utf-8') if l.strip()]
keep = [p for p in paths if 'fifo_top' not in p and 'gowin_pll' not in p]
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/eg4_35.list','w',encoding='utf-8',newline='').write('\n'.join(keep)+'\n')
lines = ['cd C:/Users/Administrator/Desktop/task/FPGA_TD',
         'create_project -family eg4 -device EG4S20BG256 scope_eg4 .']
for p in keep:
    lines.append('add_files ' + p)
lines.append('top_module sparkroad_scope_top')
lines.append('exit')
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/make_scope_eg4.tcl','w',encoding='utf-8',newline='').write('\n'.join(lines)+'\n')
print('files:', len(keep))
