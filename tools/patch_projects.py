# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA_TD/project_2025_11_07_TD.al'
s = io.open(p, encoding='utf-8', newline='').read()
files = [
 ('../FPGA/src/adc/adc_top.v', 28),
 ('../FPGA/src/adc/hal/adc_par.v', 29),
 ('../FPGA/src/adc/hal/adc_stub.v', 30),
 ('../FPGA/src/adc/hal/adc_spi.v', 31),
 ('../FPGA/src/adc/abs/adc_norm.v', 32),
 ('../FPGA/src/adc/abs/adc_cfg.v', 33),
]
if 'adc_top.v' in s:
    print('already present')
else:
    block = ''
    for path, order in files:
        block += '''            <File Path="%s">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="%d"/>
                </FileInfo>
            </File>
''' % (path, order)
    anchor = '        </Verilog>'
    assert anchor in s
    s = s.replace(anchor, block + anchor, 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('6 entries added')

# check_ports 增加 adc 目录
p2 = r'C:/Users/Administrator/Desktop/task/tools/check_ports.py'
t = io.open(p2, encoding='utf-8', newline='').read()
if "os.path.join(ROOT,'adc')" not in t:
    t = t.replace("DIRS = [ROOT, os.path.join(ROOT,'vga')",
                  "DIRS = [ROOT, os.path.join(ROOT,'adc'), os.path.join(ROOT,'adc','hal'),\n        os.path.join(ROOT,'adc','abs'), os.path.join(ROOT,'vga')", 1)
    io.open(p2, 'w', encoding='utf-8', newline='').write(t)
    print('check_ports dirs extended')
else:
    print('check_ports already has adc')
