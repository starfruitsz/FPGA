//==============================================================================
// 层: ADC HAL(型号驱动)  文件: hal/adc_par.v
// 功能: 并行 ADC 基线驱动：把外部并行数据当成每个时钟一个样本。
//   用于替代原 adda.v 中"直接采 ad_date"的行为，保证 S2 不回归。
//   对齐/位宽转换不在本模块做（交给 abs/adc_norm）。
//==============================================================================
`timescale 1ns / 1ps

module adc_par #(
    parameter integer RW  = 16,
    parameter integer RES = 12
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          enable,
    input  wire [15:0]   rate,
    input  wire [15:0]   adc_din,     // 外部并行数据(右对齐)
    output wire [RW-1:0] r_data,
    output wire [1:0]    r_ch,
    output wire          r_valid,
    input  wire          r_ready,
    output wire          locked,
    output wire          error
);
    assign r_data  = adc_din;   // RW=16 时直接对应；RW>16 自动零扩展
    assign r_ch    = 2'd0;
    assign r_valid = enable;          // 每个 clk 一个样本
    assign locked  = 1'b1;
    assign error   = 1'b0;
endmodule
