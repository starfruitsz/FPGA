# -*- coding: utf-8 -*-
import shutil
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
pairs=[
 ('FPGA/src/sparkroad_scope_top.v','FPGA/src/sparkroad_scope_top.v'),
 ('FPGA/src/adc/pins/board_pins.csv','FPGA/src/adc/pins/board_pins.csv'),
 ('FPGA_TD/eg4/SparkRoad.adc','FPGA_TD/eg4/SparkRoad.adc'),
 ('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),
 ('doc/SparkRoad-V_pinmap.md','doc/SparkRoad-V_pinmap.md'),
]
for a,b in pairs:
    shutil.copy2(src+'/'+a, dst+'/'+b)
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
print('synced')
