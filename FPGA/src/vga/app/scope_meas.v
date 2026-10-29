//==============================================================================
// 层: 应用(测量)  文件: app/scope_meas.v
// 功能: 【特性2 自动测量】在每个显示帧(帧起始脉冲)内统计:
//   - 峰峰值 vpp = max - min
//   - 过零(阈值 512)上升次数 cnt -> 频率约 cnt * 帧频(60Hz)
// 说明: 统计窗口 = 一帧，结果在帧起始打一拍输出，供文本层显示。
//==============================================================================
`timescale 1ns / 1ps

module scope_meas #(
    parameter integer THRESH = 512
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  din,
    input  wire        tick,        // 采样节拍
    input  wire        frame,       // 帧起始(单周期)
    output reg  [9:0]  vpp,
    output reg  [15:0] freq
);

    reg [9:0]  vmin;
    reg [9:0]  vmax;
    reg [15:0] cnt;
    reg [9:0]  din_d;

    localparam [9:0] TH = THRESH;

    wire rise = (din_d < TH) && (din >= TH);

    always @(posedge clk) begin
        if (rst) begin
            vmin <= 10'h3FF;
            vmax <= 10'd0;
            cnt  <= 16'd0;
            din_d <= 10'd0;
            vpp  <= 10'd0;
            freq <= 16'd0;
        end
        else if (frame) begin
            vpp  <= vmax - vmin;          // 上一帧统计结果
            freq <= cnt * 16'd60;         // 帧频约 60Hz
            vmin <= 10'h3FF;
            vmax <= 10'd0;
            cnt  <= 16'd0;
        end
        else if (tick) begin
            din_d <= din;
            if (din < vmin) vmin <= din;
            if (din > vmax) vmax <= din;
            if (rise)       cnt  <= cnt + 16'd1;
        end
    end

endmodule
