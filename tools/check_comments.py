# -*- coding: utf-8 -*-
import io, os, re, sys, difflib

pairs = []
base = r'C:/Users/Administrator/Desktop/task/FPGA/src'
bak  = r'C:/Users/Administrator/Desktop/task/FPGA/src_original_backup'
for root, dirs, files in os.walk(base):
    for f in files:
        if f.endswith(('.v','.cst')):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, base)
            b = os.path.join(bak, rel)
            if os.path.exists(b):
                pairs.append((p, b))

def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    t = re.sub(r'//[^\n]*', ' ', t)
    return re.sub(r'\s+', ' ', t).strip()

bad = 0
for p, b in sorted(pairs):
    a1 = strip_comments(io.open(b, encoding='utf-8', newline='').read())
    a2 = strip_comments(io.open(p, encoding='utf-8', newline='').read())
    if a1 != a2:
        bad += 1
        print('DIFF', os.path.relpath(p, base))
        sm = difflib.SequenceMatcher(None, a1, a2)
        for tag,i1,i2,j1,j2 in sm.get_opcodes():
            if tag != 'equal':
                print('   ', tag, repr(a1[max(0,i1-40):i2+40])[:160], '=>', repr(a2[max(0,j1-40):j2+40])[:160])
    else:
        print('SAME  code  ', os.path.relpath(p, base))
print('total', len(pairs), 'bad', bad)
