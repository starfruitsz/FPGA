# -*- coding: utf-8 -*-
"""由 board_pins.csv 生成 Anlogic TD 约束(.adc)与引脚表。
用法: python gen_adc_pins.py [csv] [out.adc]
默认: FPGA/src/adc/pins/board_pins.csv -> FPGA_TD/eg4/SparkRoad.adc
"""
import io, os, sys

ROOT = r'C:/Users/Administrator/Desktop/task'
csv_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'FPGA/src/adc/pins/board_pins.csv')
out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'FPGA_TD/eg4/SparkRoad.adc')

rows = []
for line in io.open(csv_path, encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    parts = [p.strip() for p in line.split(',')]
    if len(parts) < 3:
        print('SKIP', line)
        continue
    name, width, pins = parts[0], int(parts[1]), parts[2]
    note = parts[3] if len(parts) > 3 else ''
    plist = [p for p in pins.split('|') if p]
    if len(plist) != width:
        print('ERROR width mismatch:', name, width, len(plist))
        sys.exit(1)
    rows.append((name, width, plist, note))

seen = {}
for name, width, plist, note in rows:
    for i, pin in enumerate(plist):
        sig = name if width == 1 else '%s[%d]' % (name, i)
        if pin in seen:
            print('ERROR duplicate pin', pin, 'used by', seen[pin], 'and', sig)
            sys.exit(1)
        seen[pin] = sig

lines = ['#### SparkRoad-V (EG4S20BG256) 引脚约束',
         '#### 由 tools/gen_adc_pins.py 从 board_pins.csv 生成，请勿手改',
         '']
for name, width, plist, note in rows:
    lines.append('#### %s %s' % (name, note))
    for i, pin in enumerate(plist):
        sig = name if width == 1 else '%s[%d]' % (name, i)
        lines.append('set_pin_assignment {%s} { LOCATION = %s; IOSTANDARD = LVCMOS33; }' % (sig, pin))
    lines.append('')

io.open(out_path, 'w', encoding='utf-8', newline='').write('\n'.join(lines) + '\n')
print('written', out_path)
print('signals=%d pins=%d' % (sum(1 for _ in rows), len(seen)))
