//==============================================================================
// 层: ADC HAL(型号驱动)  文件: hal/adc_stub.v
// 功能: 内部测试信号源（锯齿波），无硬件时用于跑通显示/触发/测量链路。
//   契约见 adc_backend_if.vh：输出 r_data/r_ch/r_valid，不做对齐转换。
//==============================================================================
`timescale 1ns / 1ps

module adc_stub #(
    parameter integer RW = 16
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          enable,
    input  wire [15:0]   rate,
    output reg  [RW-1:0] r_data,
    output reg  [1:0]    r_ch,
    output reg           r_valid,
    input  wire          r_ready,
    output wire          locked,
    output wire          error
);
    reg [15:0] cnt;
    always @(posedge clk) begin
        if (rst) begin
            cnt     <= 16'd0;
            r_data  <= {RW{1'b0}};
            r_ch    <= 2'd0;
            r_valid <= 1'b0;
        end
        else if (!enable) begin
            r_valid <= 1'b0;
        end
        else begin
            cnt     <= cnt + 16'd1;
            r_data  <= cnt;                     // 16bit 锯齿(赋值自动零扩展)
            r_ch    <= 2'd0;
            r_valid <= 1'b1;                     // 每个时钟一个样本
        end
    end
    assign locked = 1'b1;
    assign error  = 1'b0;
endmodule
