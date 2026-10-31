# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/tools/check_ports.py'
s = io.open(p, encoding='utf-8', newline='').read()
if "os.path.join(ROOT,'adc','app')" not in s:
    s = s.replace("os.path.join(ROOT,'adc','abs')", "os.path.join(ROOT,'adc','abs'), os.path.join(ROOT,'adc','app')", 1)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
    print('checker dirs updated')
else:
    print('already')
