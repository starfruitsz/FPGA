# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/doc/ch16_self_test.tex'
s = io.open(p, encoding='utf-8', newline='').read()
print('len', len(s))
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
ms = pat.findall(s)
print('matches', len(ms))
print(ms[:5])
