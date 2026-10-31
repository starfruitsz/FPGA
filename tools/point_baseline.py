# -*- coding: utf-8 -*-
import io
D = r'C:/Users/Administrator/Desktop/task/doc/'
repl = [
 ('ch02_adda.tex', r'\lstinputlisting[style=vcode]{../FPGA/src/adda.v}', r'\lstinputlisting[style=vcode]{baseline/adda.v}'),
 ('ch04_eso.tex', r'\lstinputlisting[style=vcode]{../FPGA/src/eso.v}', r'\lstinputlisting[style=vcode]{baseline/eso.v}'),
 ('ch05_divider.tex', r'\lstinputlisting[style=vcode]{../FPGA/src/divider.v}', r'\lstinputlisting[style=vcode]{baseline/divider.v}'),
 ('ch09_seg.tex', r'\lstinputlisting[style=vcode]{../FPGA/src/seg.v}', r'\lstinputlisting[style=vcode]{baseline/seg.v}'),
 ('ch10_bcd.tex', r'\lstinputlisting[style=vcode]{../FPGA/src/bcd.v}', r'\lstinputlisting[style=vcode]{baseline/bcd.v}'),
 ('ch13_cst.tex', r'\lstinputlisting[style=cfgcode]{../FPGA/src/project_2025_11_07.cst}', r'\lstinputlisting[style=cfgcode]{baseline/project_2025_11_07.cst}'),
]
for f, old, new in repl:
    p = D + f
    s = io.open(p, encoding='utf-8', newline='').read()
    if old not in s:
        print('MISS', f); continue
    s = s.replace(old, new)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('OK  ', f)
