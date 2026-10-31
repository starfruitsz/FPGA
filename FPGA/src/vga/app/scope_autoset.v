//==============================================================================
// 层: 应用(自动量程)  文件: app/scope_autoset.v
// 功能: 自动量程（SW4）—— 双通道同时统计
//   1) 每 30 帧(约 0.5s) 或 1024 个采样点统计一次 ch0/ch1 两路的 vmax/vmin
//   2) 每路 A = max(vmax-512, 512-vmin)，取 peak_out = max(A0, A1)
//   3) 档位 vs(2..7) 由 peak_out 选，判据: peak_out * 7/2^vs <= 201 px
//      （201 = 90% x 224 半高）。两个通道共用同一档，按"幅度大的那一路
//      也装得下"来选，所以 CH0/CH1 能同时完整落在屏幕内。
//   4) 分别输出两路直流中点 mid_out0/mid_out1，
//      顶层用 mid0 给 CH0 精细居中、用 mid1 给 CH1 精细居中（各管各的）。
//   5) 自动量程只决定"档位 + 中点"，不参与任何通道使能(ch0_en/ch1_en)。
//   6) SW4 拨上 = 持续自适应；拨下 = 停止更新（保留最后一次结果）
//==============================================================================
`timescale 1ns / 1ps

module scope_autoset #(
    parameter integer WIN_TICKS  = 1024,   // 一次统计的采样点上限
    parameter integer WIN_FRAMES = 30      // 一次统计的帧数上限(60Hz -> 0.5s)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        en,          // SW4：1=持续自动
    input  wire [9:0]  din0,        // ch0 采样
    input  wire [9:0]  din1,        // ch1 采样
    input  wire        valid,       // adc_valid
    input  wire [15:0] tb_div,      // 采样分频（与采集一致）
    input  wire        frame,       // VGA 帧起始
    output reg  [2:0]  vs_out,      // 垂直档位 2..7（两通道共用一档）
    output reg  [9:0]  mid_out0,    // ch0 直流中点
    output reg  [9:0]  mid_out1,    // ch1 直流中点
    output reg  [9:0]  peak_out,    // 两路峰值的较大者(码)，供档位判决与基线夹紧
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
    reg [9:0]  vmax0, vmin0;        // ch0 包络
    reg [9:0]  vmax1, vmin1;        // ch1 包络
    reg [15:0] tick_cnt, wait_cnt;
    reg        en_d;

    // 档位判决：满足 A*7/2^vs <= 201 的最大增益(最小 vs)
    //   注意：入参已经是两路里较大的那个峰值 peak_max
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

    //------------------------------------------------------------------
    // 两路各自的峰值/中点（组合算出，判决那一拍一起锁存）
    //   位宽：vmax+vmin 最大 2046，必须用 11bit 再右移，
    //   否则 10bit 求和会在 1024 处回绕（914+112=1026 -> 2），中点就变成 0
    //------------------------------------------------------------------
    wire [10:0] vmax0_x = {1'b0, vmax0};
    wire [10:0] vmin0_x = {1'b0, vmin0};
    wire [10:0] vmax1_x = {1'b0, vmax1};
    wire [10:0] vmin1_x = {1'b0, vmin1};

    wire [10:0] up0 = (vmax0_x >= 11'd512) ? (vmax0_x - 11'd512) : 11'd0;
    wire [10:0] dn0 = (vmin0_x <= 11'd512) ? (11'd512 - vmin0_x) : 11'd0;
    wire [10:0] up1 = (vmax1_x >= 11'd512) ? (vmax1_x - 11'd512) : 11'd0;
    wire [10:0] dn1 = (vmin1_x <= 11'd512) ? (11'd512 - vmin1_x) : 11'd0;

    wire [10:0] peak0_x = (up0 >= dn0) ? up0 : dn0;
    wire [10:0] peak1_x = (up1 >= dn1) ? up1 : dn1;
    wire [9:0]  peak0   = (peak0_x > 11'd1023) ? 10'd1023 : peak0_x[9:0];
    wire [9:0]  peak1   = (peak1_x > 11'd1023) ? 10'd1023 : peak1_x[9:0];

    // 档位只看两路里较大的那个峰值：共用一档也能让两路同时装得下
    wire [9:0]  peak_max = (peak0 >= peak1) ? peak0 : peak1;

    wire [9:0]  mid0    = (vmax0_x + vmin0_x) >> 1;
    wire [9:0]  mid1    = (vmax1_x + vmin1_x) >> 1;

    always @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            vmax0   <= 10'd0;   vmin0 <= 10'h3FF;
            vmax1   <= 10'd0;   vmin1 <= 10'h3FF;
            tick_cnt<= 16'd0;
            wait_cnt<= 16'd0;
            vs_out   <= 3'd4;       // 上电默认：与旧版一致
            mid_out0 <= 10'd512;
            mid_out1 <= 10'd512;
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
                        vmax0 <= 10'd0;   vmin0 <= 10'h3FF;
                        vmax1 <= 10'd0;   vmin1 <= 10'h3FF;
                        tick_cnt <= 16'd0;
                        wait_cnt <= 16'd0;
                        busy <= 1'b1;
                        state <= ST_MEAS;
                    end
                end
                ST_MEAS: begin
                    // 两路同时统计包络（同一拍采样，互不影响）
                    if (tick) begin
                        if (din0 > vmax0) vmax0 <= din0;
                        if (din0 < vmin0) vmin0 <= din0;
                        if (din1 > vmax1) vmax1 <= din1;
                        if (din1 < vmin1) vmin1 <= din1;
                        tick_cnt <= tick_cnt + 16'd1;
                    end
                    if (frame) wait_cnt <= wait_cnt + 16'd1;
                    // 采满一个窗口（点数或帧数先到）就判决
                    if ((tick_cnt >= WIN_TICKS-1) || (wait_cnt >= WIN_FRAMES-1)) begin
                        vs_out   <= pick_vs(peak_max);   // 档位：两路共用，取大峰值
                        mid_out0 <= mid0;                // 中点：两路分开
                        mid_out1 <= mid1;
                        peak_out <= peak_max;
                        wait_cnt <= 16'd0;
                        state   <= ST_WAIT;
                        busy    <= 1'b0;
                    end
                end
                ST_WAIT: begin
                    if (!en) state <= ST_IDLE;
                    else if (frame) begin
                        if (wait_cnt >= WIN_FRAMES-1) begin
                            vmax0 <= 10'd0;   vmin0 <= 10'h3FF;
                            vmax1 <= 10'd0;   vmin1 <= 10'h3FF;
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
