module bcd
( 
    input wire clk, 
    input wire rst_n, 
    input wire [9:0]data, 
    
    output reg [3:0]unit, 
    output reg [3:0]ten, 
    output reg [3:0]hun 
); 
 
reg [4:0]cnt_shift; 
reg [21:0]data_shift; 
reg shift_flag; //移位标志信号 
 
always @(posedge clk or negedge rst_n) //0-11 循环 
    if(!rst_n) 
        cnt_shift<=1'b0; 
    else if(cnt_shift==5'd11 && shift_flag) 
        cnt_shift<=1'b0; 
    else if(shift_flag) 
        cnt_shift<=cnt_shift+1'b1; 
    else 
        cnt_shift<=cnt_shift; 
 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_shift<=1'b0; 
    else if(!cnt_shift) 
        data_shift<={12'b0,data}; //目标 BCD 码三个数 12 位+10 位待转换数据 
    else if(cnt_shift<=10 && (!shift_flag)) //低判断 
        begin 
            data_shift[13:10]<=(data_shift[13:10]>4)? (data_shift[13:10]+2'd3):(data_shift[13:10]); //大于 4 就加 3，否则不变 
            data_shift[17:14]<=(data_shift[17:14]>4)? (data_shift[17:14]+2'd3):(data_shift[17:14]); 
            data_shift[21:18]<=(data_shift[21:18]>4)? (data_shift[21:18]+2'd3):(data_shift[21:18]);  
        end
    else if(cnt_shift<=5'd10 && shift_flag) //高移位 
        data_shift<=data_shift<<1; 
    else 
        data_shift<=data_shift; 
 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        shift_flag<=1'b0; 
    else 
        shift_flag<=~shift_flag; //移位标志信号 
 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        begin 
            unit<=1'b0; 
            ten<=1'b0; 
            hun<=1'b0; 
        end 
    else if(cnt_shift==5'd11) 
        begin 
            unit<=data_shift[13:10]; 
            ten<=data_shift[17:14]; 
            hun<=data_shift[21:18]; 
        end 
 
endmodule  