# -*- coding: utf-8 -*-
import io
# adc_par: 去掉零宽度复制
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/hal/adc_par.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("    assign r_data  = {{(RW-16){1'b0}}, adc_din};", "    assign r_data  = adc_din;   // RW=16 时直接对应；RW>16 自动零扩展")
io.open(p, 'w', encoding='utf-8', newline='').write(s)

# adc_stub: 同样处理
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/hal/adc_stub.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("            r_data  <= {{(RW-16){1'b0}}, cnt};   // 16bit 锯齿，高位补 0", "            r_data  <= cnt;                     // 16bit 锯齿(赋值自动零扩展)")
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('zero-width replication removed')
