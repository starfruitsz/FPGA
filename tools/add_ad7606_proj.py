# -*- coding: utf-8 -*-
import io, re
# 1) Gowin gprj
p = r'C:/Users/Administrator/Desktop/task/FPGA/project_2025_11_07.gprj'
s = io.open(p, encoding='utf-8', newline='').read()
files = ['src/adc/adc_ad7606_top.v','src/adc/hal/adc_ad7606_spi.v']
add = ''.join('      <File path="%s" type="file.verilog" enable="1"/>\n' % f for f in files if f not in s)
if add:
    s = s.replace('</FileList>', add + '</FileList>', 1)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
    print('gprj +', add.count('<File'))
else:
    print('gprj already ok')

# 2) TD al
p = r'C:/Users/Administrator/Desktop/task/FPGA_TD/project_2025_11_07_TD.al'
s = io.open(p, encoding='utf-8', newline='').read()
if 'adc_ad7606_top.v' not in s:
    block = ''
    for i,(path,order) in enumerate([('../FPGA/src/adc/adc_ad7606_top.v',34),('../FPGA/src/adc/hal/adc_ad7606_spi.v',35)]):
        block += '''            <File Path="%s">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="%d"/>
                </FileInfo>
            </File>
''' % (path, order)
    s = s.replace('        </Verilog>', block + '        </Verilog>', 1)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
    print('al +2 files')
else:
    print('al already ok')

# 3) EG4 .al 重新从 TD .al 生成（换器件字段）
src = io.open(p, encoding='utf-8', newline='').read()
s2 = src.replace('<Name>project_2025_11_07_TD</Name>','<Name>EG4S20BG256_scope</Name>',1)
s2 = s2.replace('<Family>PH1</Family>','<Family>EG4</Family>',1)
s2 = s2.replace('<Device>PH1A60GEG324</Device>','<Device>EG4S20BG256</Device>',1)
s2 = s2.replace('<Speed>-3</Speed>','<Speed>-5</Speed>',1)
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/EG4S20BG256_scope.al','w',encoding='utf-8',newline='').write(s2)
paths = re.findall(r'<File Path="([^"]+)"', s2)
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/eg4/files.list','w',encoding='utf-8',newline='').write('\n'.join(paths)+'\n')
print('eg4 files:', len(paths))
