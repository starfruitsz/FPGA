# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_cmd.v'
t = io.open(p, encoding='utf-8').read()
def strip(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    t = re.sub(r'//[^\n]*', ' ', t)
    return re.sub(r'\s+', ' ', t).strip()
s = strip(t)
i = s.find('串口命令解析器')
out = io.open(r'C:/Users/Administrator/Desktop/task/tools/dbg_strip.txt', 'w', encoding='utf-8')
out.write(u'idx=%d\n' % i)
out.write(s[max(0,i-200): i+300])
out.close()
print('idx', i)
