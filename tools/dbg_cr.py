# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_cmd.v'
raw = io.open(p, 'rb').read()
print('len', len(raw), 'CR count', raw.count(b'\r'), 'LF count', raw.count(b'\n'))
# 找孤立 CR
i = -1
while True:
    i = raw.find(b'\r', i+1)
    if i < 0: break
    nxt = raw[i+1:i+2]
    if nxt != b'\n':
        print('lone CR at', i, repr(raw[max(0,i-40):i+40]))
        break
# 找 0x0b/0x0c 等
for b in (b'\x0b', b'\x0c'):
    print(b, raw.count(b))
