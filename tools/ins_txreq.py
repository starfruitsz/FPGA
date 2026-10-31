# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adda.v'
lines = io.open(p, encoding='utf-8', newline='').read().split('\n')
crlf = any(l.endswith('\r') for l in lines)
lines = [l[:-1] if l.endswith('\r') else l for l in lines]

idx = None
for i, l in enumerate(lines):
    if '[块 5] 16bit 串口指令组帧' in l:
        idx = i
        break
assert idx is not None
# 在块 5 的分隔线之前插入（idx-1 是 "//----"）
ins = [
'//------------------------------------------------------------------------------',
'// [块 4b] 发送请求选择（P5 开关）',
'//   UART_MODE=0: 连续发送，pi_flag 恒为 1（原来的行为）',
'//   UART_MODE=1: 每 REPORT_MS 毫秒发一帧（由块 3/4 定时，默认 26ms）',
'//   UART_MODE 是常数参数，综合时未被选中的一路会被常量折叠掉。',
'//------------------------------------------------------------------------------',
'wire tx_req = (UART_MODE != 0) ? pi_flag : 1\'b1;',
'',
]
lines[idx-1:idx-1] = ins
nl = '\r\n' if crlf else '\n'
io.open(p, 'w', encoding='utf-8', newline='').write(nl.join(lines))
print('tx_req inserted at line', idx)
