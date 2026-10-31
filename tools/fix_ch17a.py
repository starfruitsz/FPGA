# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch17_fixes.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace(r'\sig{sel <= \textasciitilde sel\_reg[3:0]}', r'\sig{sel <= ~sel_reg[3:0]}')
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('tilde fixed')
