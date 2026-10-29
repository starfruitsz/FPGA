//==============================================================================
// 层: 应用(采集)  文件: app/scope_capture.v
// 功能: 单通道采样引擎
//   - 采样率 = CLK / (rate_div+1)，rate_div 运行时可配(0 => 每个时钟采一点)
//   - 循环写入 BSRAM，写指针 arm 时归零
//   - 【特性1 触发】trig_en=1 时，检测到电平穿越就把写指针归零，
//     显示总是从触发点开始(±1 采样)，周期信号不再左右漂移
//   - run=0 冻结(停止写入，保留当前波形)
// 说明: 采样数据由顶层直连 RAM 的 wdata，与写地址同拍，第 0 个样本落在地址 0。
//==============================================================================
`timescale 1ns / 1ps

module scope_capture #(
    parameter integer DEPTH_LOG2 = 10
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [9:0]              din,        // 采样数据(仅用于触发检测)
    input  wire [15:0]             rate_div,
    input  wire                    run,
    input  wire                    arm,
    input  wire                    trig_en,
    input  wire [9:0]              trig_level,
    input  wire                    trig_edge,    // 0=上升沿 1=下降沿
    output wire                    we,
    output reg  [DEPTH_LOG2-1:0]   waddr,
    output reg                     trig_det     // 触发命中(单周期)
);

    reg [15:0] rate_cnt;
    reg [9:0]  din_d;

    wire tick = (rate_cnt == rate_div);

    assign we = run && (!arm) && tick;

    // 上升沿: 上一拍 < 阈值 且 本拍 >= 阈值；下降沿: 上一拍 > 阈值 且 本拍 <= 阈值
    wire cross = trig_edge
               ? ((din_d > trig_level) && (din <= trig_level))
               : ((din_d < trig_level) && (din >= trig_level));

    always @(posedge clk) begin
        if (rst) begin
            rate_cnt <= 16'd0;
            waddr    <= {DEPTH_LOG2{1'b0}};
            din_d    <= 10'd0;
            trig_det <= 1'b0;
        end
        else begin
            trig_det <= 1'b0;

            if (arm) begin
                rate_cnt <= 16'd0;
                waddr    <= {DEPTH_LOG2{1'b0}};
                din_d    <= din;
            end
            else if (!run) begin
                rate_cnt <= 16'd0;
            end
            else if (tick) begin
                rate_cnt <= 16'd0;
                din_d    <= din;
                if (trig_en && cross) begin
                    trig_det <= 1'b1;
                    waddr    <= {DEPTH_LOG2{1'b0}};   // 触发对齐
                end
                else begin
                    waddr    <= waddr + 1'b1;
                end
            end
            else begin
                rate_cnt <= rate_cnt + 16'd1;
            end
        end
    end

endmodule
