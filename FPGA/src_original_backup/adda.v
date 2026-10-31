module adda 
#( 
    parameter CNT_DATA_MAX=11'd1024, 
    parameter CNT_MAX = 25'd12_999_9 
) 

(
    input wire sys_clk, 
    input wire sys_rst_n, 
    input wire [9:0] ad_date, 
    input wire key_in, 
    input ad_clk, 
    input da_clk, 
    input wire rx, 
    
    output wire ad_clk1, 
    output wire da_clk1, 
    output reg [9:0] ad_out, 
    output wire[3:0] sel, 
    output wire[7:0] seg, 
    output wire tx, 
    output reg led0, 
    output reg led6, 
    output reg led7 
); 
    
wire key_out; 
wire [9:0] volt; 
wire sign; 
reg signed [9:0] date_y; 
wire signed [9:0] date_u; 
wire [7:0] po_data; 
wire po_flag; 
reg [7:0] seg_date; 
wire [7:0] ad_pingj0; 
wire [7:0] ad_pingj1; 
reg po_flag2; 
reg po_flag3; //16位信号完整接收标志位 

reg pi_flag; 
reg [24:0] cnt; 
reg [15:0] rx_date; 

reg [11:0] c_date; 
reg [11:0] k_date; 
reg c_flag; 
reg k_flag; 

initial 
    begin 
        po_flag2=1'b0;
    end 
 
assign ad_pingj0={ad_date[7:0]}; 
assign ad_pingj1={6'b000000,ad_date[9:8]}; 
//assign ad_pingj2={8'b1010_1010}; 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        date_y<=10'd0; 
    else 
        date_y<=ad_date-10'd512; //0-1024 变 -512-512 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        ad_out<=10'd0; 
    else if(key_out==1'b0) 
        begin 
            ad_out<=~ad_date; //按下输出 ad 读数 
            led0<=1'b1; 
        end 
    else 
        begin 
            ad_out<=~date_u+10'd512; //按下输出控制量，0 灯亮 
            led0<=1'b0; 
        end 
 
//always@(posedge sys_clk or negedge sys_rst_n) 
// if(sys_rst_n==1'b0) 
// seg_date<=8'd0; 
// else 
// seg_date<=po_data/256*100+po_data%256/16*10+po_data%16; 
// //八位最大 255，因转换 10 进制最大 99 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        cnt <= 25'b0; 
    else if(cnt == CNT_MAX) 
        cnt <= 25'b0; 
    else 
        cnt <= cnt + 1'b1; 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        pi_flag <= 1'b0; 
    else if(cnt == CNT_MAX-1'b0) //tx 发送过快后分配 
        pi_flag <= 1'b1; 
    else 
        pi_flag <= 1'b0; 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        rx_date<=16'd0; 
    else if((po_flag == 1'b1)&&(po_flag2==1'b0)) 
        begin 
            rx_date<={po_data,8'd0}; //先赋高八位 
            po_flag2<=1'b1; 
        end 
    else if((po_flag == 1'b1)&&(po_flag2==1'b1)) 
        begin 
            rx_date<={rx_date[15:8],po_data}; //再赋低八位拼接十六位 
            po_flag2<=1'b0; 
        end 
    else 
        begin 
            rx_date<=rx_date; 
            po_flag2<=po_flag2; 
        end 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        po_flag3 <= 1'b0; 
    else if((po_flag==1'b1)&&(po_flag2==1'b1)) 
        po_flag3 <= 1'b1; 
    else 
        po_flag3 <= 1'b0; //16 位拼接标志 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        led6<=1'b1; 
    else if((rx_date[15:12]==4'HB)&&(po_flag3==1'B1)) //前四位为参数标志位，后12位为数据位
        begin 
            led6<=~led6; //K 接收标志位有效后 led6 跳变 
            k_flag<=1'b1; 
            k_date<=rx_date[11:0]; //Bxxx，xxx 为 adrc 的 k 
        end 
    else 
        begin 
            led6<=led6; 
            //k_flag<=1'b0; 
            k_date<=k_date; 
        end 
 
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        led7<=1'b1; 
    else if((rx_date[15:12]==4'HA)&&(po_flag3==1'B1)) //前四位为参数标志位，后12位为数据位
        begin 
            led7<=~led7; //C 接收标志位有效后 led7 跳变 
            c_flag<=1'b1; 
            c_date<=rx_date[11:0]; //Axxx，xxx 为 adrc 的 c 
        end 
    else 
        begin 
            led7<=led7; 
            //c_flag<=1'b0; 
            c_date<=c_date; 
        end 
 
 
key key_inst 
( 
    .key_in(key_in), 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .key_out(key_out) 
); 
 
seg seg_inst 
( 
    .clk(sys_clk), 
    .rst_n(sys_rst_n), 
    .point(4'b0100), 
    .data(ad_date), //gai 
    .seg_en(1'b1), 
    .sign(sign), 
    .sel(sel), 
    .seg(seg) 
); 
rtl adc_inst 
( 
    .clk(sys_clk), 
    .rst_n(sys_rst_n), 
    .ad_data(ad_date), 
    .sign(sign), 
    .volt(volt) 
); 
eso eso_inst 
( 
    .ad_clk(ad_clk1), 
    .sys_rst_n(sys_rst_n), 
    .e_in(date_y), 
    .u_out(date_u), 
    .out_da(date_u), 
    .c_flag(c_flag), 
    .k_flag(k_flag), 
    .c_date(c_date), 
    .k_date(k_date) 
); 
 
uart_rx
#(
    .UART_BPS(115200),
    .CLK_FREQ(50_000_000)
)
uart_rx_inst 
( 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .rx(rx), 
    .po_data(po_data), 
    .po_flag(po_flag) 
); 
 
uart_tx
#(
    .UART_BPS(115200),
    .CLK_FREQ(50_000_000)
)
uart_tx_inst 
( 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    //.pi_data(rx_date),//tx 先发低八位，所以 tx 值跟实际 rx_date 顺序颠倒，不影响 rx_date数值 
    .pi_data({ad_pingj0,ad_pingj1}), 
    .pi_flag(1'b1), 
    
    .tx(tx) 
); 
 
/*Gowin_PLL pll_inst(
    .clkout0(ad_clk1), //output clkout0
    .clkout1(da_clk1), //output clkout1
    .clkin(sys_clk) //input clkin
); */

divider 
#(
    .cnt_max(24999)
)
divider_inst(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .clk0(ad_clk1),
    .clk1(da_clk1)
);



/*fifo_top fifo_top_inst1(
		.Data(ad_date), //input [9:0] Data
		.WrClk(ad_clk1), //input WrClk
		.RdClk(ad_clk1), //input RdClk
		.WrEn(WrEn), //input WrEn
		.RdEn(RdEn), //input RdEn
		.Q(Q), //output [9:0] Q
		.Empty(Empty), //output Empty
		.Full(Full) //output Full
	);*/

endmodule 