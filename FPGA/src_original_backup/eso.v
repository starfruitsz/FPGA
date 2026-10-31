`timescale 1ns / 1ps 
`define WIDTH 20 

module eso 
( 
    input ad_clk, 
    input sys_rst_n, 
    input signed [9:0] e_in, 
    input signed [9:0] u_out, 
    input wire c_flag, 
    input wire k_flag, 
    input wire [11:0] c_date, 
    input wire [11:0] k_date, 
    
    output signed [`WIDTH-1: 0] z1k0, 
    output signed [`WIDTH-1: 0] z2k0, 
    output signed [`WIDTH-1: 0] z3k0, 
    output signed [9:0] out_da 
); 
    
reg signed [`WIDTH-1: 0] z1k1; 
reg signed [`WIDTH-1: 0] z2k1; 
reg signed [`WIDTH-1: 0] z3k1; 
reg signed [9:0] y; 
reg signed [9:0] uk; 
reg signed [9:0] c; 
reg signed [10:0] k; 

parameter signed B01=21'd90; 
parameter signed B02=21'd2700; 
parameter signed B03=21'd27000; 
parameter signed b0=16'd5000; 
parameter signed n = 2'd1; 
 
//initial 
//begin 
// c=10'd150; 
// k=11'd25; 
//end 
// 

always@(posedge ad_clk or negedge sys_rst_n) 
    begin
        if(sys_rst_n==1'b0) 
            begin 
                z1k1 <= 'd0; 
                z2k1 <= 'd0; 
                z3k1 <= 'd0; 
                y <= 'd0; 
                uk <= 'd0; 
            end 
        else 
            begin 
                z1k1 <= z1k0; //z(k)=z(k+1) 
                z2k1 <= z2k0; 
                z3k1 <= z3k0; 
                y <= -e_in; 
                uk <= u_out; 
            end  
    end
    
always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            c<=10'd150; 
            k<=11'd20; 
        end //初始化参数 
    else if(c_flag==1'b1) 
        c<=c_date; 
    else if(k_flag==1'b1) 
        k<=k_date; 
    else 
        begin 
            c<=c; 
            k<=k; 
        end 
 
wire signed [`WIDTH + 16 - 1 : 0] uk_b0; 
wire signed [`WIDTH + 16 - 1 : 0] uk_b0_h; 
assign uk_b0 = uk * b0; 
assign uk_b0_h = uk_b0 >>> 13; 

wire signed [`WIDTH - 1: 0] z2k1_h; //z(k)*h 
wire signed [`WIDTH - 1: 0] z3k1_h; 
assign z2k1_h = z2k1 >>> 10; 
assign z3k1_h = z3k1 >>> 10; 

wire signed [`WIDTH - 1 + 1: 0] sub; 
assign sub = z1k1 - y; 

wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B01; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B02; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B03; 
assign sub_B01 = sub * B01; //B1e1,B2e1,B3e1 
assign sub_B02 = sub * B02; 
assign sub_B03 = sub * B03; 

wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B01_h; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B02_h; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B03_h; 
assign sub_B01_h = sub_B01 >>> 10; //Be1*h
assign sub_B02_h = sub_B02 >>> 10; 
assign sub_B03_h = sub_B03 >>> 10; 

wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z1k0_reg; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z2k0_reg; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z3k0_reg; 
assign z1k0_reg = z1k1 + z2k1_h - sub_B01_h; //前向差分 ESO 
assign z2k0_reg = z2k1 + z3k1_h - sub_B02_h + uk_b0_h; 
assign z3k0_reg = z3k1 - sub_B03_h; 

assign z1k0 = z1k0_reg[21: 0]; //z(k+1) 
assign z2k0 = z2k0_reg[21: 0]; 
assign z3k0 = z3k0_reg[21: 0]; 

wire signed [`WIDTH + 12 -1: 0] err1; 
wire signed [`WIDTH + 12 -1: 0] err2; 

assign err1 = z1k0 * c; 
assign err2 = z2k0 * c; 

wire signed [`WIDTH + 13 -1: 0] she ; 
assign she = err1 + z2k0; //s=ce1+e2 
wire signed [`WIDTH + 13 + 11 -1: 0] kshe; 
assign kshe = she * k; 

wire signed [4 : 0] sgn; 
assign sgn= (she>1'd0)?1'd1:4'b1111; 

wire signed [`WIDTH + 22 -1: 0] v_1; 
assign v_1 = kshe +sgn + err2; 

wire signed [`WIDTH + 21 -1: 0] viout; 
assign viout = v_1 - z3k0; //ks+sgn+cz2-f 

wire signed [40 -1: 0] b; 
assign b = viout >>> 15; 
assign out_da = b[9 : 0]; 
 
endmodule 