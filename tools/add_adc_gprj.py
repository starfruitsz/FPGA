# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/project_2025_11_07.gprj'
s = io.open(p, encoding='utf-8', newline='').read()
files = [
 'src/adc/adc_top.v',
 'src/adc/hal/adc_par.v',
 'src/adc/hal/adc_stub.v',
 'src/adc/hal/adc_spi.v',
 'src/adc/abs/adc_norm.v',
 'src/adc/abs/adc_cfg.v',
]
add = ''.join('      <File path="%s" type="file.verilog" enable="1"/>\n' % f for f in files)
anchor = '</FileList>'
assert anchor in s, 'no FileList end'
if 'src/adc/adc_top.v' not in s:
    s = s.replace(anchor, add + anchor, 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('gprj updated, +%d files' % len(files))
else:
    print('gprj already contains adc files')
