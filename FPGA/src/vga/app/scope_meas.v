//==============================================================================
// 层: 应用(测量)  文件: app/scope_meas.v   [v2: 扩展测量]
// 功能: 每个显示帧内统计波形特征，帧起始输出上一帧结果：
//   vpp  峰峰值 = max - min；vmax/vmin 本帧最大/最小
//   vmean  前 256 个采样点的平均值（右移 8 位，无需除法器）
//   period 相邻两次上升穿越之间的采样点数
//   freq   帧内上升穿越次数 x 帧频(约 60Hz)
//   duty   前 256 点中高于阈值的比例(0~100)
// 说明: RMS 需要开方，本版本不实现（可用 CORDIC 或查表，后续再加）。
//==============================================================================
`timescale 1ns / 1ps

module scope_meas #(
    parameter integer THRESH = 512
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  din,
    input  wire        tick,
    input  wire        frame,
    output reg  [9:0]  vpp,
    output reg  [9:0]  vmax,
    output reg  [9:0]  vmin,
    output reg  [9:0]  vmean,
    output reg  [15:0] freq,
    output reg  [15:0] period,
    output reg  [7:0]  duty
);

    localparam [9:0] TH = THRESH;

    reg [9:0]  vmax_i, vmin_i;
    reg [15:0] cnt;
    reg [15:0] period_cnt;
    reg [15:0] period_lat;
    reg [17:0] sum;
    reg [8:0]  win_cnt;
    reg [8:0]  high_cnt;
    reg [9:0]  din_d;

    wire rise = (din_d < TH) && (din >= TH);

    always @(posedge clk) begin
        if (rst) begin
            vmax_i <= 10'd0;      vmin_i <= 10'h3FF;
            cnt <= 16'd0;         period_cnt <= 16'd0;  period_lat <= 16'd0;
            sum <= 18'd0;         win_cnt <= 9'd0;      high_cnt <= 9'd0;
            din_d <= 10'd0;
            vpp <= 10'd0; vmax <= 10'd0; vmin <= 10'd0; vmean <= 10'd0;
            freq <= 16'd0; period <= 16'd0; duty <= 8'd0;
        end
        else if (frame) begin
            vpp    <= vmax_i - vmin_i;
            vmax   <= vmax_i;
            vmin   <= vmin_i;
            vmean  <= sum[17:8];
            period <= period_lat;
            freq   <= cnt * 16'd60;
            duty   <= (win_cnt == 9'd0) ? 8'd0 : ((high_cnt * 8'd100) >> 8);

            vmax_i <= 10'd0;      vmin_i <= 10'h3FF;
            cnt <= 16'd0;         period_cnt <= 16'd0;
            sum <= 18'd0;         win_cnt <= 9'd0;   high_cnt <= 9'd0;
        end
        else if (tick) begin
            din_d <= din;

            if (din > vmax_i) vmax_i <= din;
            if (din < vmin_i) vmin_i <= din;

            if (rise) begin
                cnt        <= cnt + 16'd1;
                period_lat <= period_cnt;
                period_cnt <= 16'd0;
            end
            else if (period_cnt != 16'hFFFF) begin
                period_cnt <= period_cnt + 16'd1;
            end

            if (win_cnt != 9'd256) begin
                sum      <= sum + {8'd0, din};
                win_cnt  <= win_cnt + 9'd1;
                if (din > TH) high_cnt <= high_cnt + 9'd1;
            end
        end
    end

endmodule
