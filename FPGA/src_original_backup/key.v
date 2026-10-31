module key 
( 
    input wire key_in, 
    input wire sys_clk, 
    input wire sys_rst_n, 
 
    output reg key_out 
); 
    
reg [19:0] cnt_20ms; 

parameter CNT_MAX=20'd999_999; 

always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        cnt_20ms<=20'd0; 
    else if(key_in==1'b1) //没按下保持 0 
        cnt_20ms<=20'd0; 
    else if(key_in==1'b0 && cnt_20ms==CNT_MAX) //非抖动确定按下，保持计数值 
        cnt_20ms<=cnt_20ms; 
    else 
        cnt_20ms<=cnt_20ms+1'b1; //按下后计数 20ms 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        key_out <= 1'b1; 
    else if(cnt_20ms == CNT_MAX - 1'b1) 
        key_out <= ~key_out; 
    else 
        key_out <= key_out; 
 
endmodule 