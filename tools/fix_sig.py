# -*- coding: utf-8 -*-
import io, re, glob, sys
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
changed = 0
for p in glob.glob(r'C:/Users/Administrator/Desktop/task/doc/*.tex'):
    if p.endswith(('_t3.tex','_t4.tex','_t5.tex','_t6.tex','_test.tex','_test2.tex')):
        continue
    s = io.open(p, encoding='utf-8', newline='').read()
    def rep(m):
        body = m.group(2)
        body = body.replace('\\_', '_').replace('\\{','{').replace('\\}','}')
        return '\\' + m.group(1) + '{' + body + '}'
    s2 = pat.sub(rep, s)
    if s2 != s:
        io.open(p, 'w', encoding='utf-8', newline='').write(s2)
        changed += 1
        print('fixed', p.split('/')[-1])
print('files changed:', changed)
