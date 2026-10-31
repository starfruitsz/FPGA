# -*- coding: utf-8 -*-
import io, re
# ch19: 工程名更新
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('scope\\_eg4.al', 'scope\\_eg4\\_56.al')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('ch19 project name updated')

# README: 工程名更新
p = r'C:/Users/Administrator/Desktop/task/README.md'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('scope_eg4.al', 'scope_eg4_56.al')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('README updated')
