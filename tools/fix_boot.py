# -*- coding: utf-8 -*-
import io

# --- scope_app: boot 寄存器 + 上电自动 arm ---
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_app.v'
lines = io.open(p, encoding='utf-8', newline='').read().split('\n')
crlf = any(l.endswith('\r') for l in lines)
lines = [l[:-1] if l.endswith('\r') else l for l in lines]

i = next(k for k, l in enumerate(lines) if '主寄存器块' in l)
# 在注释块结束的分隔线之后插入
j = next(k for k in range(i, len(lines)) if lines[k].strip().startswith('//----'))
boot = [
'',
'    // 上电后自动 arm 一次，避免一直停在 IDLE 不采集',
'    reg boot;',
'    always @(posedge clk)',
'        if (rst) boot <= 1\'b0;',
'        else     boot <= 1\'b1;',
]
lines[j+1:j+1] = boot

k = next(k for k in range(len(lines)) if lines[k].strip() == 'arm <= 1\'b0;' and 'boot' not in lines[k])
lines.insert(k+1, "            if (!boot) arm <= 1'b1;   // 上电自动采集一次")

io.open(p, 'w', encoding='utf-8', newline='').write(('\r\n' if crlf else '\n').join(lines))
print('scope_app patched')

# --- top: tick 用采样节拍 ---
p2 = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/vga_scope_top.v'
s = io.open(p2, encoding='utf-8', newline='').read()
assert ".tick(1'b1)" in s
s = s.replace(".tick(1'b1)", ".tick(we0),   // 用采样节拍统计(不是系统时钟)")
io.open(p2, 'w', encoding='utf-8', newline='').write(s)
print('top tick patched')
