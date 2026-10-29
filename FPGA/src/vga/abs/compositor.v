//==============================================================================
// 层: 抽象(合成器)  文件: abs/compositor.v
// 功能: 按优先级把多个图层合成为一个像素(RGB444)
//   优先级: 文字 > CH1 波形 > CH0 波形 > 网格 > 背景
//==============================================================================
`timescale 1ns / 1ps

module compositor (
    input  wire        txt_hit,
    input  wire [11:0] txt_col,
    input  wire        ch1_hit,
    input  wire [11:0] ch1_col,
    input  wire        ch0_hit,
    input  wire [11:0] ch0_col,
    input  wire        grid_hit,
    input  wire [11:0] grid_col,
    input  wire [11:0] bg_col,
    output reg  [11:0] rgb
);

    always @(*) begin
        if (txt_hit)
            rgb = txt_col;
        else if (ch1_hit)
            rgb = ch1_col;
        else if (ch0_hit)
            rgb = ch0_col;
        else if (grid_hit)
            rgb = grid_col;
        else
            rgb = bg_col;
    end

endmodule
