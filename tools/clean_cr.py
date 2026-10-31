# -*- coding: utf-8 -*-
import io, os
root = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga'
fixed = 0
for r, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.v'): continue
        p = os.path.join(r, f)
        b = io.open(p, 'rb').read()
        if b'\r' not in b: continue
        nb = b.replace(b'\r\n', b'\n').replace(b'\r', b'')
        if nb != b:
            io.open(p, 'wb').write(nb)
            print('cleaned', f, 'CR removed')
            fixed += 1
print('files cleaned:', fixed)
