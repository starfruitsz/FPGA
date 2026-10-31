# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
repl = [
 ('CA + CB & A7 & 两根并在一起接 A7', 'CA + CB & A7 & 两根并接 A7（排针 3）'),
 ('BUSY & A8 & 输入', 'BUSY & A8 & 输入（排针 5）'),
 ('CS & A10 & 输出，低有效', 'CS & A10 & 输出，低有效（排针 7）'),
 ('RD/SCLK & A9 & 输出', 'RD/SCLK & A9 & 输出（排针 8）'),
 ('D7/DOUTA & A5 & 输入', 'D7/DOUTA & A5 & 输入（排针 10）'),
 ('RST & A6 & 输出，高有效', 'RST & A6 & 输出，高有效（排针 11）'),
 ('SER & 3.3V & 必须为高，串行模式', 'SER & 3.3V & 必须为高，串行模式（排针 1 或 17）'),
]
for a,b in repl:
    if a in s:
        s = s.replace(a,b,1)
    else:
        print('missing:', a[:30])
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('physical pin notes added')
