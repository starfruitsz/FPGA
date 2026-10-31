module rtl
( 
    input wire clk, 
    input wire rst_n, 
    input wire [9:0]ad_data, 
    
    output wire sign, 
    output wire [9:0]volt 
); 

parameter CNT_DATA_MAX=11'd1024; 

reg clk_sample; 
reg median_en; 
reg [10:0]cnt_median; 
reg [29:0]data_sum_m; 
reg [13:0]data_median; 
reg [30:0]volt_reg; 

wire [30:0]data_p; 
wire [30:0]data_n; 

assign sign=(ad_data<data_median)? 1'b1:1'b0;  
//assign sign=1'b1; 

//中值使能信号 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        median_en<=1'b0; 
    else if(cnt_median==CNT_DATA_MAX) 
        median_en<=1'b1; 
    else 
        median_en<=median_en; 
 
//中值数据累加计数器 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        cnt_median<=11'b0; 
    else if(!median_en) 
        cnt_median<=cnt_median+1'b1; 
 
//1024 次中值数据累加总和 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_sum_m<=30'b0; 
    else if(cnt_median==CNT_DATA_MAX) 
        data_sum_m<=30'b0; 
    else 
        data_sum_m<=data_sum_m+ad_data; 
 
//中值数据 
always @(posedge clk or negedge rst_n) 
    if(!rst_n)
        data_median<=12'b0; 
    else if(cnt_median==CNT_DATA_MAX) 
        data_median<=data_sum_m/CNT_DATA_MAX; 
    else 
        data_median<=data_median; 
 
//根据中值计算出的正向电压 AD 和负向电压 AD 的分辨率（放大 2^13*100 倍） 
assign data_p=(median_en==1'b1)?3276800/((1024-data_median)*2):0; 
assign data_n=(median_en==1'b1)?3276800/((data_median+1)*2):0; 
 
//处理后的稳定数据 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        volt_reg<=1'b0; 
    else if(median_en) 
        if((ad_data>(data_median-3)) && (ad_data<(data_median+3))) 
            volt_reg<=1'b0; 
        else if(ad_data<data_median) 
            volt_reg<=(data_n*(data_median-ad_data)) >> 13; 
        else if(ad_data>data_median) 
            volt_reg<=(data_p*(ad_data-data_median)) >> 13; 
    else 
        volt_reg<=1'b0; 
 
assign volt=volt_reg; 
 
endmodule 