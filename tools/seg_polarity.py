# -*- coding: utf-8 -*-
import io

# 1) 顶层：数码管极性（共阳，段低有效、位高有效）
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/sparkroad_scope_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""    seg u_seg (
        .clk    (clk),
        .rst_n  (rst_n),
        .point  (4'b0000),
        .data   (adc_data[9:0]),
        .seg_en (1'b1),
        .sign   (1'b0),
        .sel    (sel),
        .seg    (seg)
    );""", """    // 板上数码管为共阳：段码低有效、位码高有效，故输出取反
    wire [3:0] sel_i;
    wire [7:0] seg_i;

    seg u_seg (
        .clk    (clk),
        .rst_n  (rst_n),
        .point  (4'b0000),
        .data   (adc_data[9:0]),
        .seg_en (1'b1),
        .sign   (1'b0),
        .sel    (sel_i),
        .seg    (seg_i)
    );

    assign sel = ~sel_i;
    assign seg = ~seg_i;""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('seg polarity fixed')
