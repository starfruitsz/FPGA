# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
old = """  \\item \\textbf{数码管共阳}：段码低电平有效、位码高电平有效。顶层已用
        \\sig{assign seg = \\textasciitilde seg\\_i} 与 \\sig{assign sel = \\textasciitilde sel\\_i} 取反；"""
new = """  \\item \\textbf{数码管共阳}：段码低电平有效、位码高电平有效。顶层已取反：
        \\begin{lstlisting}[style=vsnip]
assign sel = ~sel_i;
assign seg = ~seg_i;
        \\end{lstlisting}"""
assert old in s, 'pattern not found'
s = s.replace(old, new, 1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('fixed tilde lines')
