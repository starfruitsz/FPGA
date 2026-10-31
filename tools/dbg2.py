# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/doc/ch16_self_test.tex'
s = io.open(p, encoding='utf-8', newline='').read()
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
def rep(m):
    body = m.group(2)
    body = body.replace('\\_', '_').replace('\\{','{').replace('\\}','}')
    return '\\' + m.group(1) + '{' + body + '}'
s2 = pat.sub(rep, s)
print('changed?', s2 != s)
i = s.find('pix_')
print(repr(s[i-30:i+30]))
