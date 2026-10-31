# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch18_scope_v2.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace(r'\chapter{示波器应用层增强（v2）}', r'\section{示波器应用层增强（v2）}')
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('chapter -> section')
