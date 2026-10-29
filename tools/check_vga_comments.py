# -*- coding: utf-8 -*-
"""校验：vga 源码只新增注释（去注释后逐字符一致）"""
import io, os, re, difflib

A = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga_snapshot'
B = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga'

def strip(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    t = re.sub(r'//[^\n]*', ' ', t)
    return re.sub(r'\s+', ' ', t).strip()

bad = 0; n = 0
for root, _, files in os.walk(B):
    for f in files:
        if not f.endswith('.v'): continue
        pb = os.path.join(root, f)
        rel = os.path.relpath(pb, B)
        pa = os.path.join(A, rel)
        if not os.path.exists(pa):
            print('NO SNAPSHOT', rel); continue
        a = strip(io.open(pa, encoding='utf-8').read())
        b = strip(io.open(pb, encoding='utf-8').read())
        n += 1
        if a != b:
            bad += 1
            print('DIFF', rel)
            for tag,i1,i2,j1,j2 in difflib.SequenceMatcher(None, a, b).get_opcodes():
                if tag != 'equal':
                    print('   ', tag, repr(a[i1:i2])[:80], '=>', repr(b[j1:j2])[:80])
print('checked', n, 'files, code diff =', bad)
