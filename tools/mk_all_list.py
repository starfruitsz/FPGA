# -*- coding: utf-8 -*-
import io, re
al = io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/project_2025_11_07_TD.al', encoding='utf-8').read()
paths = re.findall(r'<File Path="([^"]+)"', al)
extra = [
 '../FPGA/src/adc/adc_top.v','../FPGA/src/adc/adc_ad7606_top.v','../FPGA/src/adc/hal/adc_par.v',
 '../FPGA/src/adc/hal/adc_stub.v','../FPGA/src/adc/hal/adc_spi.v','../FPGA/src/adc/hal/adc_ad7606_spi.v',
 '../FPGA/src/adc/abs/adc_norm.v','../FPGA/src/adc/abs/adc_cfg.v','../FPGA/src/adc/app/adc_cmd.v',
 '../FPGA/src/sparkroad_scope_top.v']
for e in extra:
    if e not in paths: paths.append(e)
io.open(r'C:/Users/Administrator/Desktop/task/FPGA_TD/all.list','w',encoding='utf-8',newline='').write('\n'.join(paths)+'\n')
print('all.list:', len(paths))
