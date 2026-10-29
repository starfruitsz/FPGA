//==============================================================================
// 层: 抽象(图形层)  文件: abs/trace_layer.v
// 功能: 单通道波形图层(流式渲染，无帧缓存)
//   对当前像素列 px 取两个相邻采样 s_now/s_prev，分别映射成绘图区 y 坐标，
//   若当前扫描线 py 落在两者之间，则该像素点亮 => 自动连成波形。
// 映射: y = (PLOT_H-1) - (s * SCALE_NUM >> SCALE_SHIFT)
//       默认 10bit(0..1023) -> 0..447，取 7/16 缩放
//==============================================================================
`timescale 1ns / 1ps

module trace_layer #(
    parameter integer H_VIS       = 640,
    parameter integer PLOT_H      = 448,
    parameter integer SCALE_NUM   = 7,
    parameter integer SCALE_SHIFT = 4,
    parameter [11:0]  COL         = 12'h1F1
)(
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    input  wire        en,        // 通道使能
    input  wire [9:0]  s_now,     // 当前列采样
    input  wire [9:0]  s_prev,    // 前一列采样
    output wire        hit,
    output wire [11:0] color
);

    wire [15:0] n_now  = s_now  * SCALE_NUM;
    wire [15:0] n_prev = s_prev * SCALE_NUM;

    localparam [11:0] PLOT_TOP = PLOT_H - 1;

    wire [11:0] y_now  = PLOT_TOP - (n_now  >> SCALE_SHIFT);
    wire [11:0] y_prev = PLOT_TOP - (n_prev >> SCALE_SHIFT);

    wire [11:0] y_hi = (y_now > y_prev) ? y_now : y_prev;
    wire [11:0] y_lo = (y_now > y_prev) ? y_prev : y_now;

    // px != 0: 避免行首与上一行末列"连"出一条竖线
    assign hit = en && de && (px != 12'd0) && (px < H_VIS) && (py < PLOT_H)
                 && (py >= y_lo) && (py <= y_hi);
    assign color = COL;

endmodule
