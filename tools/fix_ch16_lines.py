# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/doc/ch16_self_test.tex'
s = io.open(p, encoding='utf-8', newline='').read()
# 去掉小节标题里的行号范围（注释增删后行号会变，改为按块名索引）
s2 = re.sub(r'(\\subsubsection\{块 \d+[^}]*?)（\d+--\d+ 行）\}', r'\1}', s)
# 在 16.2 开头补一句说明
note = ('\\noindent 说明：下文按“块序号”索引，各小节序号与源码里的 \\sig{[块 N]} 注释一一对应；'
        '源码中的中文注释已细化到每个语句块内部，行号随注释增删会变化，故不在此标注具体行号。\n\n')
s2 = s2.replace('\\subsubsection{块 1：时序例化}', note + '\\subsubsection{块 1：时序例化}', 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s2)
print('remaining line ranges:', len(re.findall(r'\\subsubsection\{块 \d+[^}]*（\d+--\d+ 行）', s2)))
