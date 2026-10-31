# -*- coding: utf-8 -*-
import shutil
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
for a,b in [('doc/ch19_sparkroad.tex','doc/ch19_sparkroad.tex'),('doc/SparkRoad-V_pinmap.md','doc/SparkRoad-V_pinmap.md')]:
    shutil.copy2(src+'/'+a, dst+'/'+b)
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
print('synced')
