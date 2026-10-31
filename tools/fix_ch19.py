# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
def rep(m):
    body = m.group(2).replace('\\_', '_').replace('\\{', '{').replace('\\}', '}')
    return '\\' + m.group(1) + '{' + body + '}'
s2 = pat.sub(rep, s)
io.open(p, 'w', encoding='utf-8', newline='').write(s2)
print('ch19 escapes fixed')
