# -*- coding: utf-8 -*-
import io
paths = [l.strip() for l in io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/eg4_35.list', encoding='utf-8') if l.strip()]
lines = ['cd C:/Users/Administrator/Desktop/task/FPGA_TD',
         'create_project -family eg4 -device EG4S20BG256 scope_eg4_56 .']
for p in paths:
    lines.append('add_files ' + p)
lines.append('add_files ./eg4/SparkRoad.adc')
lines.append('top_module sparkroad_scope_top')
lines.append('exit')
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/make_eg4_56b.tcl','w',encoding='utf-8',newline='').write('\n'.join(lines)+'\n')
print('tcl lines', len(lines))
