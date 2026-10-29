# -*- coding: utf-8 -*-
"""解析 Gowin pin 报告的 All Package Pins，列出可用(未使用)的 IO 引脚"""
import io, re

html = io.open(r'C:/Users/Administrator/Desktop/task/FPGA/impl/pnr/project_2025_11_07.pin.html',
               encoding='utf-8', errors='ignore').read()
i = html.find('All Package Pins', 5000)
seg = html[i:]
# 只取表格行
rows = re.findall(r'<tr[^>]*>(.*?)</tr>', seg, flags=re.S)
data = []
for r in rows:
    cells = re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', r, flags=re.S)
    cells = [re.sub(r'<[^>]+>', '', c).strip() for c in cells]
    if len(cells) >= 15 and re.match(r'^[A-Z]+\d+/\d+$', cells[0]):
        data.append(cells)

print('parsed rows:', len(data))
free = []
for c in data:
    loc, sig, dr, site, iotype, bankv = c[0], c[1], c[2], c[3], c[4], c[14]
    m = re.match(r'^([A-Z]+\d+)/(\d+)$', loc)
    if not m: continue
    pin, bank = m.group(1), int(m.group(2))
    if sig != '-': continue
    if not site.startswith('IO'): continue
    if iotype != 'LVCMOS33': continue
    free.append((bank, pin, site))

from collections import defaultdict
by = defaultdict(list)
for b, p, s in free:
    by[b].append((p, s))

for b in sorted(by):
    print('bank', b, 'free:', len(by[b]))
    print('   ', ', '.join('%s(%s)' % (p, s) for p, s in by[b][:24]))
