# -*- coding: utf-8 -*-
import io

# 1) sparkroad_scope_top: 新增 TX_MODE，默认连续
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/sparkroad_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""module sparkroad_scope_top #(
    parameter integer CLK_HZ = 24_000_000
)(""", """module sparkroad_scope_top #(
    parameter integer CLK_HZ = 24_000_000,
    parameter integer TX_MODE = 0        // 0=连续发送(默认) 1=每 1ms 一帧
)(""")
s = s.replace("""    //------------------------------------------------------------------
    // 串口上报：每 1ms 发一帧(16bit)
    //------------------------------------------------------------------
    localparam integer SEND_DIV = CLK_HZ / 1000;""", """    //------------------------------------------------------------------
    // 串口上报：TX_MODE=0 连续发送(默认)；TX_MODE=1 每 1ms 一帧
    //------------------------------------------------------------------
    localparam integer SEND_DIV = CLK_HZ / 1000;""")
s = s.replace("""    uart_tx #(
        .UART_BPS (115200),
        .CLK_FREQ (CLK_HZ)
    ) u_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .pi_data  (adc_data),
        .pi_flag  (tx_pulse),
        .tx       (uart_tx)
    );""", """    wire tx_req = (TX_MODE == 0) ? 1'b1 : tx_pulse;

    uart_tx #(
        .UART_BPS (115200),
        .CLK_FREQ (CLK_HZ)
    ) u_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .pi_data  (adc_data),
        .pi_flag  (tx_req),
        .tx       (uart_tx)
    );""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('sparkroad TX_MODE=0 added')

# 2) adda.v: 默认连续
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adda.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("parameter integer UART_MODE = 1,          // 0=连续 1=标志位",
              "parameter integer UART_MODE = 0,          // 默认连续发送 0=连续 1=标志位")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('adda UART_MODE=0')

# 3) adda_scope_top: 默认连续
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/adda_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("parameter integer UART_MODE = 1,   // 0=连续发送  1=按标志位定时发送",
              "parameter integer UART_MODE = 0,   // 默认连续发送  0=连续 1=按标志位定时")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('adda_scope_top UART_MODE=0')
