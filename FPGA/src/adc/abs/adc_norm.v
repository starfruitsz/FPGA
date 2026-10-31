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
    parameter integer DW     = 16,
    parameter integer RES    = 12,
    parameter integer ALIGN  = 1,
    parameter integer SIGNED = 0     // 1=输入为补码，先转偏移二进制
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
    // 补码 -> 偏移二进制：翻转最高位
    wire [DW-1:0] src  = SIGNED ? (r_data ^ {1'b1, {(DW-1){1'b0}}}) : r_data;
    wire [DW-1:0] norm = ALIGN ? (src >> (DW - RES)) : (src & MASK);

    assign s_data  = norm;
    assign s_ch    = r_ch;
    assign s_valid = r_valid;
    assign r_ready = s_ready;
endmodule
