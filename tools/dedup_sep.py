# -*- coding: utf-8 -*-
import io, re
for p in [r'C:/Users/Administrator/Desktop/task/FPGA/src/eso.v']:
    s = io.open(p, encoding='utf-8', newline='').read()
    # 合并重复的分隔线
    s2 = re.sub(r'(//-{60,}\r?\n)(\s*//-{60,}\r?\n)+', r'\1', s)
    if s2 != s:
        io.open(p, 'w', encoding='utf-8', newline='').write(s2)
        print('deduped', p.split('/')[-1])
    else:
        print('no change', p.split('/')[-1])
