# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace(r'\file{board\_pins.csv}', r'\file{board_pins.csv}')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('fixed file ref')
