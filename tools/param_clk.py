# -*- coding: utf-8 -*-
import io

# 1) scope_app: CLK_HZ 参数化
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_app.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""module scope_app (
    input  wire        clk,""", """module scope_app #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire        clk,""")
s = s.replace("""    scope_ui #(
        .CLK_HZ (50_000_000),""", """    scope_ui #(
        .CLK_HZ (CLK_HZ),""")
s = s.replace("""    reg [26:0] page_cnt;""", """    localparam integer PAGE_MAX = 2*CLK_HZ - 1;
    reg [26:0] page_cnt;""")
s = s.replace("""        else if (page_cnt == 27'd99_999_999) begin""", """        else if (page_cnt == PAGE_MAX[26:0]) begin""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('scope_app parameterized')

# 2) vga_scope_top: CLK_HZ 参数并传给 scope_app
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/vga_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""    parameter integer DEPTH_LOG2 = 10,""", """    parameter integer DEPTH_LOG2 = 10,
    parameter integer CLK_HZ     = 50_000_000,""")
s = s.replace("""    scope_app u_app (
        .clk(clk), .rst(rst), .key_in(key_in),""", """    scope_app #(
        .CLK_HZ(CLK_HZ)
    ) u_app (
        .clk(clk), .rst(rst), .key_in(key_in),""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('vga_scope_top parameterized')
