cd C:/Users/Administrator/Desktop/task/FPGA_TD/eg4
create_project -family eg4 -device EG4S20BG256 EG4S20BG256_scope .
import_device eg4_20.db -package BG256 -speed 5
add_files -list ./files.list
top_module adda_scope_top
exit
