//==============================================================================
// 层: ADC ABS(归一化)  文件: abs/adc_norm.v
// 功能: 把型号相关的原始流归一化为应用层统一格式：
//   - 对齐: ALIGN=1(左对齐) -> 右移 (DW-RES)；ALIGN=0(右对齐) -> 掩码截取
//   - 位宽: 统一为 DW 位(默认 16)，右对齐、无符号
//   - 通道: 原样透传 r_ch（拆分由上层按需处理）
// 契约: s_data/s_ch/s_valid 与 r_data/r_ch/r_valid 同拍，r_ready=s_ready。
//==============================================================================
`timescale 1ns / 1ps

module adc_norm #(
    parameter integer DW    = 16,
    parameter integer RES   = 12,
    parameter integer ALIGN = 1
)(
    input  wire          clk,
    input  wire          rst,
    input  wire [DW-1:0] r_data,
    input  wire [1:0]    r_ch,
    input  wire          r_valid,
    output wire          r_ready,
    output wire [DW-1:0] s_data,
    output wire [1:0]    s_ch,
    output wire          s_valid,
    input  wire          s_ready
);
    localparam [DW-1:0] MASK = (1 << RES) - 1;
    wire [DW-1:0] norm = ALIGN ? (r_data >> (DW - RES)) : (r_data & MASK);

    assign s_data  = norm;
    assign s_ch    = r_ch;
    assign s_valid = r_valid;
    assign r_ready = s_ready;
endmodule
