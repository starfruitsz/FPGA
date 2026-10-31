# -*- coding: utf-8 -*-
import io

# ch19 更新
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('1657 / 19600 & 8.45', '1632 / 19600 & 8.33')
s = s.replace('848 / 19600 & 4.33', '832 / 19600 & 4.24')
s = s.replace('20.79\\,ns（约 48\\,MHz）', '21.182\\,ns（约 47\\,MHz）')
s = s.replace('应能看到约 1\\,ms 一帧的数据', '应能看到连续的数据流（默认连续发送）')
s = s.replace('每 1\\,ms 上报一帧', '默认连续发送（可参数改为 1ms 一帧）')
s = s.replace('scope\\_eg4\\_59', 'scope\\_eg4\\_60')
s = s.replace('scope\\_eg4\\_59.bit', 'scope\\_eg4\\_60.bit')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('ch19 updated')

# PROJECT_STATE 更新
p = r'C:/Users/Administrator/Desktop/task/PROJECT_STATE.md'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('对应提交 46bc0f5', '对应提交待填（连续发送版本）')
s = s.replace('scope_eg4_59.al', 'scope_eg4_60.al')
s = s.replace('scope_eg4_59.bit', 'scope_eg4_60.bit')
s = s.replace('scope_eg4_59_Runs', 'scope_eg4_60_Runs')
s = s.replace('156.8K', '156.8K')
s = s.replace('1657 / 19600（8.45%）', '1632 / 19600（8.33%）')
s = s.replace('848 / 19600（4.33%）', '832 / 19600（4.24%）')
s = s.replace('20.79ns（约 48MHz，约束 41.667ns）', '21.182ns（约 47MHz，约束 41.667ns）')
s = s.replace('uart_tx 每 1ms 上报 16bit', 'uart_tx 默认连续发送 16bit 帧（TX_MODE=0；=1 时每 1ms 一帧）')
s = s.replace('full_flow59.tcl', 'full_flow60.tcl')
s = s.replace('"每 1ms 上报一帧"', '"默认连续，可参数改为 1ms 一帧"')
s = s.replace('每 1ms 发一帧', '默认连续发送')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('PROJECT_STATE updated')

# README 更新
p = r'C:/Users/Administrator/Desktop/task/README.md'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace('scope_eg4_59.al', 'scope_eg4_60.al')
s = s.replace('scope_eg4_59.bit', 'scope_eg4_60.bit')
s = s.replace('LUT 1657/19600（8.45%）', 'LUT 1632/19600（8.33%）')
s = s.replace('REG 848', 'REG 832')
s = s.replace('20.79ns ≈ 48MHz', '21.182ns ≈ 47MHz')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('README updated')
