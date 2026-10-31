# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/FPGA_TD/project_2025_11_07_TD.al'
s = io.open(p, encoding='utf-8', newline='').read()
print('before:', s.count('<File Path='))
if 'sparkroad_scope_top.v' not in s:
    block = '''            <File Path="../FPGA/src/sparkroad_scope_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="37"/>
                </FileInfo>
            </File>
'''
    anchor = '        </Verilog>'
    assert anchor in s
    s = s.replace(anchor, block + anchor, 1)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
print('after:', s.count('<File Path='))
# 同步 EG4
s2 = s.replace('<Name>project_2025_11_07_TD</Name>','<Name>EG4S20BG256_scope</Name>',1)
s2 = s2.replace('<Family>PH1</Family>','<Family>EG4</Family>',1)
s2 = s2.replace('<Device>PH1A60GEG324</Device>','<Device>EG4S20BG256</Device>',1)
s2 = s2.replace('<Speed>-3</Speed>','<Speed>-5</Speed>',1)
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/EG4S20BG256_scope.al','w',encoding='utf-8',newline='').write(s2)
paths = re.findall(r'<File Path="([^"]+)"', s2)
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/eg4/files.list','w',encoding='utf-8',newline='').write('\n'.join(paths)+'\n')
print('eg4:', len(paths))
