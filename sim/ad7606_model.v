`timescale 1ns / 1ps
//=============================================================================
// ad7606_model.v -- AD7606 串行模式的**行为模型**（仅用于仿真，不参与综合）
//
// 时序约定（与 AD7606 数据手册串行读一致，也是 adc_ad7606_spi.v 的假设）：
//   CONVST 上升沿  : 锁存 4 个通道的转换结果，BUSY 拉高
//   BUSY           : 维持 CONV_CLK 个 clk 后拉低（模拟转换时间）
//   CS 下降沿      : 开始一帧，位指针清 0
//   SCLK 下降沿    : 输出下一位（第 1 个下降沿输出 ch1 的 D15）
//   SCLK 上升沿    : 主机采样，本模型不改数据（数据在下降沿已稳定）
//   64 位后        : 依次是 ch1..ch4 各 16bit，MSB first
//
// 关键点：DOUTA 用“SCLK 下降沿事件”驱动，而不是用 clk 打拍，
//         否则在 sdiv=1（半周期只有 1 个 clk）时会晚一拍，导致整体错位。
//=============================================================================
module ad7606_model #(
    parameter integer CONV_CLK = 60        // BUSY 持续 clk 数
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        convst,
    input  wire        cs_n,
    input  wire        sclk,
    input  wire        adc_reset,
    output reg         busy,
    output reg         douta,
    input  wire [15:0] ch1,
    input  wire [15:0] ch2,
    input  wire [15:0] ch3,
    input  wire [15:0] ch4
);

    reg [63:0] frame;       // {ch1,ch2,ch3,ch4}，frame[63] = ch1 的 D15
    reg [6:0]  bit_idx;
    reg [7:0]  busy_cnt;
    reg        convst_d;

    // ---------- CONVST 上升沿：锁存采样值 + BUSY 拉高 ----------
    always @(posedge clk) begin
        convst_d <= convst;
        if (!busy && convst && !convst_d) begin
            frame    <= {ch1, ch2, ch3, ch4};
            busy     <= 1'b1;
            busy_cnt <= CONV_CLK[7:0];
        end
        else if (busy) begin
            if (busy_cnt == 8'd0) busy <= 1'b0;
            else                  busy_cnt <= busy_cnt - 8'd1;
        end
    end

    // ---------- CS 下降沿：位指针归零 ----------
    always @(negedge cs_n) begin
        bit_idx <= 7'd0;
    end

    // ---------- SCLK 下降沿：输出下一位 ----------
    always @(negedge sclk) begin
        if (!cs_n) begin
            douta   <= frame[7'd63 - bit_idx];
            bit_idx <= bit_idx + 7'd1;
        end
    end

    initial begin
        busy  = 1'b0;
        douta = 1'b0;
        bit_idx = 7'd0;
        frame = 64'd0;
    end

endmodule
