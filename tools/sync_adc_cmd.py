# -*- coding: utf-8 -*-
import io, os, shutil
src = r'C:/Users/Administrator/Desktop/task'
dst = r'C:/Users/Administrator/Desktop/task/_remote'
def copytree(a, b):
    for root, dirs, files in os.walk(a):
        rel = os.path.relpath(root, a)
        out = os.path.join(b, rel) if rel != '.' else b
        os.makedirs(out, exist_ok=True)
        for f in files:
            shutil.copy2(os.path.join(root, f), os.path.join(out, f))
copytree(os.path.join(src, 'FPGA/src/adc'), os.path.join(dst, 'FPGA/src/adc'))
pairs = [
 ('FPGA/src/vga/app/scope_cmd.v','FPGA/src/vga/app/scope_cmd.v'),
 ('FPGA/project_2025_11_07.gprj','FPGA/project_2025_11_07.gprj'),
 ('FPGA_TD/project_2025_11_07_TD.al','FPGA_TD/project_2025_11_07_TD.al'),
 ('FPGA_TD/EG4S20BG256_scope.al','FPGA_TD/EG4S20BG256_scope.al'),
 ('FPGA_TD/eg4/files.list','FPGA_TD/eg4/files.list'),
 ('doc/SparkRoad-V_pinmap.md','doc/SparkRoad-V_pinmap.md'),
 ('tools/check_ports.py','tools/check_ports.py'),
 ('ADC_HAL_plan.md','ADC_HAL_plan.md'),
]
for a,b in pairs:
    shutil.copy2(os.path.join(src,a), os.path.join(dst,b))
print('synced')
