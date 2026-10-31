module divider
#(
    parameter cnt_max=15'd24999   //500分频
)

(
    input wire sys_clk,
    input wire sys_rst_n,
    
    //output wire clk_flag
    output reg clk0,
    output reg clk1
    
);

reg [14:0] cnt;

always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n==1'b0)
        cnt<=15'd0;
    else if(cnt==cnt_max)
        cnt<=15'd0;
    else 
        cnt<=cnt+15'd1;

/*always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n==1'b0)
        clk_flag<=1'b0;
    else if(cnt==cnt_max-1)
        clk_flag<=1'b1;
    else 
        clk_flag<=1'b0;*/

always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n==1'b0)
        clk0<=1'b0;
    else if(cnt==cnt_max)
        clk0<=~clk0;
    else 
        clk0<=clk0;

always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n==1'b0)
        clk1<=1'b0;
    else if(cnt==cnt_max)
        clk1<=~clk1;
    else 
        clk1<=clk1;

endmodule