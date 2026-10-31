//==============================================================================
// 层: 应用(自动量程)  文件: app/scope_autoset.v
// 功能: 自动量程（SW4）
//   1) 每 30 帧(约 0.5s) 或 1024 个采样点统计一次 ch0 的 vmax/vmin
//   2) A = max(vmax-512, 512-vmin)，按"刚好装得下"选垂直档位 vs(2..7)
//      判据: A * 7/2^vs <= 201 px（201 = 90% x 224 半高）
//   3) 输出直流中点 mid，供顶层做精细居中（波形永远居中显示）
//   4) SW4 拨上 = 持续自适应；拨下 = 停止更新（保留最后一次结果）
//==============================================================================
`timescale 1ns / 1ps

module scope_autoset #(
    parameter integer WIN_TICKS  = 1024,   // 一次统计的采样点上限
    parameter integer WIN_FRAMES = 30      // 一次统计的帧数上限(60Hz -> 0.5s)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        en,          // SW4：1=持续自动
    input  wire [9:0]  din,         // ch0 采样
    input  wire        valid,       // adc_valid
    input  wire [15:0] tb_div,      // 采样分频（与采集一致）
    input  wire        frame,       // VGA 帧起始
    output reg  [2:0]  vs_out,      // 垂直档位 2..7
    output reg  [9:0]  mid_out,     // 直流中点
    output reg  [9:0]  peak_out,    // 峰值偏离(码)，供基线夹紧用
    output reg         busy
);

    // 采样节拍复算（与 scope_capture 的 tick 同义）
    reg [15:0] rate_cnt;
    wire tick = valid && (rate_cnt == tb_div);
    always @(posedge clk) begin
        if (rst)                     rate_cnt <= 16'd0;
        else if (tick)               rate_cnt <= 16'd0;
        else if (rate_cnt < tb_div)  rate_cnt <= rate_cnt + 16'd1;
        else                         rate_cnt <= tb_div;
    end

    localparam [1:0] ST_IDLE = 2'd0, ST_MEAS = 2'd1, ST_WAIT = 2'd2;

    reg [1:0]  state;
    reg [9:0]  vmax_i, vmin_i;
    reg [15:0] tick_cnt, wait_cnt;
    reg        en_d;

    // 档位判决：满足 A*7/2^vs <= 201 的最大增益(最小 vs)
    function [2:0] pick_vs;
        input [9:0] a;
        begin
            if      (a <= 10'd114) pick_vs = 3'd2;
            else if (a <= 10'd229) pick_vs = 3'd3;
            else if (a <= 10'd459) pick_vs = 3'd4;
            else if (a <= 10'd919) pick_vs = 3'd5;
            else                    pick_vs = 3'd6;   // A 最大 1023，vs=6 即最小增益
        end
    endfunction

    // 位宽：vmax+vmin 最大 2046，必须用 11bit 再右移，
    // 否则 10bit 求和会在 1024 处回绕（914+112=1026 -> 2），中点就变成 0
    wire [10:0] vmax_x = {1'b0, vmax_i};
    wire [10:0] vmin_x = {1'b0, vmin_i};
    wire [10:0] up_peak = (vmax_x >= 11'd512) ? (vmax_x - 11'd512) : 11'd0;
    wire [10:0] dn_peak = (vmin_x <= 11'd512) ? (11'd512 - vmin_x) : 11'd0;
    wire [10:0] peak_x  = (up_peak >= dn_peak) ? up_peak : dn_peak;
    wire [9:0]  peak    = (peak_x > 11'd1023) ? 10'd1023 : peak_x[9:0];
    wire [10:0] mid_sum = vmax_x + vmin_x;
    wire [9:0]  midv    = mid_sum[10:1];

    always @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            vmax_i  <= 10'd0;
            vmin_i  <= 10'h3FF;
            tick_cnt<= 16'd0;
            wait_cnt<= 16'd0;
            vs_out   <= 3'd4;       // 上电默认：与旧版一致
            mid_out  <= 10'd512;
            peak_out <= 10'd0;
            busy    <= 1'b0;
            en_d    <= 1'b0;
        end
        else begin
            en_d <= en;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (en) begin              // 拨上就立刻测一次
                        vmax_i <= 10'd0;
                        vmin_i <= 10'h3FF;
                        tick_cnt <= 16'd0;
                        wait_cnt <= 16'd0;
                        busy <= 1'b1;
                        state <= ST_MEAS;
                    end
                end
                ST_MEAS: begin
                    if (tick) begin
                        if (din > vmax_i) vmax_i <= din;
                        if (din < vmin_i) vmin_i <= din;
                        tick_cnt <= tick_cnt + 16'd1;
                    end
                    if (frame) wait_cnt <= wait_cnt + 16'd1;
                    // 采满一个窗口（点数或帧数先到）就判决
                    if ((tick_cnt >= WIN_TICKS-1) || (wait_cnt >= WIN_FRAMES-1)) begin
                        vs_out   <= pick_vs(peak);
                        mid_out  <= midv;
                        peak_out <= peak;
                        wait_cnt <= 16'd0;
                        state   <= ST_WAIT;
                        busy    <= 1'b0;
                    end
                end
                ST_WAIT: begin
                    if (!en) state <= ST_IDLE;
                    else if (frame) begin
                        if (wait_cnt >= WIN_FRAMES-1) begin
                            vmax_i <= 10'd0;
                            vmin_i <= 10'h3FF;
                            tick_cnt <= 16'd0;
                            wait_cnt <= 16'd0;
                            busy <= 1'b1;
                            state <= ST_MEAS;
                        end
                        else wait_cnt <= wait_cnt + 16'd1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
