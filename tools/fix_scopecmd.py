# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/vga/app/scope_cmd.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""    reg [3:0]  ndig;
    reg [3:0]  nib;
    reg        is_hex;""", """    reg [3:0]  ndig;
    reg [3:0]  nib;
    reg        is_hex;
    reg        have_cmd;   // [修复] 第一个字符一律当命令字母，避免 A/C/E 被当十六进制数字""")
s = s.replace("""            cmd<=0; acc<=0; ndig<=0;""", """            cmd<=0; acc<=0; ndig<=0; have_cmd<=1'b0;""")
s = s.replace("""                else if (is_hex && (ndig != 4'd4)) begin
                    acc  <= {acc[11:0], nib};
                    ndig <= ndig + 4'd1;
                end
                else begin
                    cmd  <= rx_data;
                    acc  <= 16'd0;
                    ndig <= 4'd0;
                end""", """                else if (have_cmd && is_hex && (ndig != 4'd4)) begin
                    acc  <= {acc[11:0], nib};
                    ndig <= ndig + 4'd1;
                end
                else if (!have_cmd) begin
                    cmd      <= rx_data;
                    acc      <= 16'd0;
                    ndig     <= 4'd0;
                    have_cmd <= 1'b1;
                end
                else begin
                    // 命令后出现非十六进制字符：忽略
                end""")
s = s.replace("""                    cmd  <= 8'd0;
                    acc  <= 16'd0;
                    ndig <= 4'd0;
                end""", """                    cmd      <= 8'd0;
                    acc      <= 16'd0;
                    ndig     <= 4'd0;
                    have_cmd <= 1'b0;
                end""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('scope_cmd first-char rule patched')
