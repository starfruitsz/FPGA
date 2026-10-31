# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('采样率 ≈ 24MHz / K', '采样率 约 24MHz / K')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('replaced ≈ in listing')
