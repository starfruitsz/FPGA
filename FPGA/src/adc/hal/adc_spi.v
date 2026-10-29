//==============================================================================
// 层: ADC HAL(型号驱动)  文件: hal/adc_spi.v
// 功能: SPI ADC 驱动模板（占位实现）。协议细节必须封装在本文件内，
//       对外只输出 r_data/r_ch/r_valid，应用层不感知 SPI。
// 待填参数:
//   SPI_HZ    SPI 时钟频率
//   CPOL/CPHA SPI 模式(0~3)
//   CMD_RD    读命令字
//   BITS      每次转换位数(8/12/16)
//   CS_ACT    CS 有效电平
// 状态机(建议): IDLE -> CS_LOW -> SEND_CMD -> READ_BITS -> CS_HIGH -> VALID
//   采样率由 rate 分频决定；读回数据按 MSB-first 组装到 r_data。
//==============================================================================
`timescale 1ns / 1ps

module adc_spi #(
    parameter integer RW      = 16,
    parameter integer BITS    = 12,
    parameter integer SPI_DIV = 8,      // sclk = clk / (2*SPI_DIV)
    parameter integer CPOL    = 0,
    parameter integer CPHA    = 0,
    parameter integer CS_ACT  = 0
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          enable,
    input  wire [15:0]   rate,
    // SPI 物理引脚
    output wire          sclk,
    output wire          cs_n,
    output wire          mosi,
    input  wire          miso,
    // 原始流
    output wire [RW-1:0] r_data,
    output wire [1:0]    r_ch,
    output wire          r_valid,
    input  wire          r_ready,
    output wire          locked,
    output wire          error
);
    // 占位：未实现协议，先保证编译与接口契约；所有输出为安全值。
    assign sclk    = 1'b0;
    assign cs_n    = (CS_ACT == 0) ? 1'b1 : 1'b0;
    assign mosi    = 1'b0;
    assign r_data  = {RW{1'b0}};
    assign r_ch    = 2'd0;
    assign r_valid = 1'b0;
    assign locked  = 1'b0;
    assign error   = 1'b0;
    // TODO: 按上面状态机实现，r_valid 每完成一次转换拉高 1 拍。
endmodule
