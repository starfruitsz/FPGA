# -*- coding: utf-8 -*-
import shutil
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
shutil.copy2(src+'/doc/ch19_sparkroad.tex', dst+'/doc/ch19_sparkroad.tex')
shutil.copy2(src+'/doc/main.pdf', dst+'/doc/main.pdf')
shutil.copy2(src+'/doc/main.pdf', dst+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/doc/main.pdf', src+'/FPGA_project_analysis.pdf')
shutil.copy2(src+'/README.md', dst+'/README.md')
print('synced')
