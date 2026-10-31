# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
anchor = r'\subsection{TD 工程操作步骤}'
assert anchor in s
ins = io.open(r'C:/Users/Administrator/Desktop/task/tools/ch19_manual_ins.txt', encoding='utf-8').read()
s = s.replace(anchor, ins + anchor, 1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('inserted manual subsection')
