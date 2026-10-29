# -*- coding: utf-8 -*-
import io, glob
rep = {'\u2460':'(1)','\u2461':'(2)','\u2462':'(3)','\u2463':'(4)','\u2464':'(5)'}
n = 0
for p in glob.glob(r'C:/Users/Administrator/Desktop/task/doc/*.tex'):
    name = p.replace('\\','/').split('/')[-1]
    if name.startswith('_'):
        continue
    s = io.open(p, encoding='utf-8', newline='').read()
    s2 = s
    for k, v in rep.items():
        if k in s2:
            s2 = s2.replace(k, v)
            n += 1
    if s2 != s:
        io.open(p,'w',encoding='utf-8',newline='').write(s2)
        print('fixed', name)
print('replacements:', n)
