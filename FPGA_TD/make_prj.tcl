cd C:/Users/Administrator/Desktop/task/FPGA_TD
create_project -family ph1 -device PH1A60GEG324 project_2025_11_07_TD .
import_device ph1_60.db -package PH1A60GEG324 -speed 2
top_module adda
add_files -list ./files.list
exit
