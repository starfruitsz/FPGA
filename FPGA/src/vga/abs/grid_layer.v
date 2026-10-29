//==============================================================================
// 层: 抽象(图形层)  文件: abs/grid_layer.v
// 功能: 网格/坐标轴图层。只对当前像素(px,py)给出"是否命中"和颜色，
//       本身不存任何像素，因此不占显存。
// 说明: STEP 建议取 2 的幂(64/32/16)，内部的取模被优化成位与。
//==============================================================================
`timescale 1ns / 1ps

module grid_layer #(
    parameter integer H_VIS    = 640,
    parameter integer PLOT_H   = 448,
    parameter integer STEP     = 64,
    parameter integer AXIS_Y   = 224,
    parameter [11:0]  COL_GRID = 12'h151,
    parameter [11:0]  COL_AXIS = 12'h2A2
)(
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    output wire        hit,
    output wire [11:0] color
);

    localparam integer MASK = STEP - 1;

    wire in_plot = de && (px < H_VIS) && (py < PLOT_H);
    wire v_line  = ((px & MASK) == 0);      // 竖网格
    wire h_line  = ((py & MASK) == 0);      // 横网格
    wire axis    = (py == AXIS_Y);          // 零电平轴

    assign hit   = in_plot && (v_line || h_line || axis);
    assign color = axis ? COL_AXIS : COL_GRID;

endmodule
