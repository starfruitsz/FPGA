# -*- coding: utf-8 -*-
import io, re, glob
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
files = glob.glob(r'C:/Users/Administrator/Desktop/task/doc/*.tex')
print('files:', len(files))
for p in files:
    s = io.open(p, encoding='utf-8', newline='').read()
    def rep(m):
        body = m.group(2)
        body = body.replace('\\_', '_')
        return '\\' + m.group(1) + '{' + body + '}'
    s2 = pat.sub(rep, s)
    if 'ch16' in p:
        print('ch16 changed?', s2 != s, 'matches', len(pat.findall(s)))
