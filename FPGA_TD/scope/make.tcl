cd C:/Users/Administrator/Desktop/task/FPGA_TD/scope
create_project -family ph1 -device PH1A60GEG324 scope_check .
import_device ph1_60.db -package PH1A60GEG324
add_files -list ./files_scope.list
top_module adda_scope_top
exit
