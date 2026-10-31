# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adda.v'
lines = io.open(p, encoding='utf-8', newline='').read().split('\n')
crlf = any(l.endswith('\r') for l in lines)
lines = [l[:-1] if l.endswith('\r') else l for l in lines]

def idx_of(sub, start=0, exact=False):
    for i in range(start, len(lines)):
        if (lines[i].strip() == sub) if exact else (sub in lines[i]):
            return i
    return -1

# 1) 参数区替换
i = idx_of('// 参数区:')
j = idx_of('parameter CNT_MAX', i)
assert i > 0 and j > i, (i, j)
new_params = [
'// 参数区:',
'//   CNT_DATA_MAX : rtl 中值累加样本数(1024 次), 本模块仅作占位, 未使用',
'//   UART_MODE    : [P5 开关] 0 = 连续发送(pi_flag 恒 1)',
'//                            1 = 按定时标志位发送(默认)',
'//   CLK_FREQ     : 系统时钟频率, 用于把 REPORT_MS 换算成计数值',
'//   REPORT_MS    : [P5 可配置] 标志位模式下的上报周期(毫秒)',
'//   CNT_MAX      : 由 REPORT_MS 推导: 50MHz 下 26ms -> 1,299,999',
'//                  例: 10ms -> 499,999; 100ms -> 4,999,999',
'//                  计数器已加宽到 32bit, 支持更长周期',
'//------------------------------------------------------------------------------',
'    parameter CNT_DATA_MAX = 11\'d1024, ',
'    parameter integer UART_MODE = 1,          // 0=连续 1=标志位',
'    parameter integer CLK_FREQ  = 50_000_000, ',
'    parameter integer REPORT_MS = 26,         // 上报周期(ms)',
'    parameter integer CNT_MAX   = (CLK_FREQ/1000)*REPORT_MS - 1',
]
# 保留 i-1 的分隔线，替换 i..j
lines[i:j+1] = new_params

# 2) 计数器位宽
i = idx_of('reg [24:0] cnt;', 0, exact=True)
assert i > 0
lines[i] = 'reg [31:0] cnt;          // [P5] 加宽到 32bit，支持更长上报周期'

# 3) 计数器复位常量
for k, l in enumerate(lines):
    if l.strip() == "cnt <= 25'b0;":
        lines[k] = l.replace("25'b0", "32'd0")

# 4) 块 3/4 注释更新
i = idx_of('[块 3] 26ms 自由计数器')
j = idx_of('不再占满带宽。', i)
assert i > 0 and j >= i
lines[i:j+1] = [
'// [块 3] 上报定时计数器: 0 ~ CNT_MAX 循环，CNT_MAX 由 REPORT_MS 推导。',
'// [修复 P5] 该计数器为块 4 提供定时标志；UART_MODE=0 时会被综合优化掉。',
'//   默认 REPORT_MS=26 → 约 38 帧/秒；改参数即可调上报速率。',
]
i = idx_of('[块 4] pi_flag')
j = idx_of('该逻辑不再是死代码', i)
assert i > 0 and j >= i
lines[i:j+1] = [
'// [块 4] 上报脉冲: 计数到 CNT_MAX-1 时产生单周期 pi_flag，送块 4b 的 tx_req。',
'//   UART_MODE=1 时每 REPORT_MS 触发一帧；UART_MODE=0 时该脉冲不使用。',
]

# 5) 插入块 4b（tx_req）
i = idx_of('[块 5] 16bit 串口指令组帧')
assert i > 0
ins = [
'//------------------------------------------------------------------------------',
'// [块 4b] 发送请求选择（P5 开关）',
'//   UART_MODE=0: 连续发送，pi_flag 恒为 1（原来的行为）',
'//   UART_MODE=1: 每 REPORT_MS 毫秒发一帧（由块 3/4 定时，默认 26ms）',
'//   UART_MODE 是常数参数，综合时未被选中的一路会被常量折叠。',
'//------------------------------------------------------------------------------',
"wire tx_req = (UART_MODE != 0) ? pi_flag : 1'b1;",
'',
]
lines[i-1:i-1] = ins

# 6) uart_tx pi_flag
i = idx_of('.pi_flag(pi_flag)')
assert i > 0
lines[i] = '    .pi_flag(tx_req),   // [P5] UART_MODE=1 按 REPORT_MS 定时；=0 连续发送 '

nl = '\r\n' if crlf else '\n'
io.open(p, 'w', encoding='utf-8', newline='').write(nl.join(lines))
print('adda.v rebuilt, lines =', len(lines))
