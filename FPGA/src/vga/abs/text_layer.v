//==============================================================================
// 层: 抽象(图形层)  文件: abs/text_layer.v   [由工具自动生成, 勿手改]
// 功能: 文本图层，2 行 x 32 列，含 5 个 4 位十六进制数字域。
//   行0: "AD=####  U=####  TB=####"   <- val0(AD) / val1(U) / val2(TB)
//   行1: "VP=####  FR=####"           <- val3(峰峰值) / val4(频率, 关闭测量时显示 0)
// 说明: 无字符缓存，模板用 case 常量实现；数字域通过 nibble 选择覆盖。
//==============================================================================
`timescale 1ns / 1ps

module text_layer #(
    parameter integer TEXT_Y0   = 448,
    parameter integer TEXT_X0   = 8,
    parameter integer COLS      = 32,
    parameter integer VAL0_COL0 = 3,
    parameter integer VAL1_COL0 = 11,
    parameter integer VAL2_COL0 = 20,
    parameter integer VAL3_COL0 = 3,
    parameter integer VAL4_COL0 = 12,
    parameter [11:0]  COL       = 12'hFFF
)(
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    input  wire [15:0] val0,
    input  wire [15:0] val1,
    input  wire [15:0] val2,
    input  wire [15:0] val3,
    input  wire [15:0] val4,
    output wire        hit,
    output wire [11:0] color
);

    localparam [11:0] TX0 = TEXT_X0;
    localparam [11:0] TY0 = TEXT_Y0;
    localparam [4:0]  C0  = VAL0_COL0;
    localparam [4:0]  C1  = VAL1_COL0;
    localparam [4:0]  C2  = VAL2_COL0;
    localparam [4:0]  C3  = VAL3_COL0;
    localparam [4:0]  C4  = VAL4_COL0;

    wire [11:0] dx = px - TX0;
    wire [11:0] dy = py - TY0;

    wire in_y = (py >= TY0) && (py < (TY0 + 12'd16));
    wire in_x = (px >= TX0) && (px < (TX0 + COLS*8));

    wire [4:0] col  = dx[8:3];
    wire       row  = dy[3];
    wire [2:0] frow = dy[2:0];

    // 模板字符码
    reg [5:0] tpl_code;
    always @(*) begin
        case ({row, col})
            7'd0  : tpl_code = 6'd10;   // 'A'
            7'd1  : tpl_code = 6'd13;   // 'D'
            7'd2  : tpl_code = 6'd36;   // '='
            7'd3  : tpl_code = 6'd37;   // '#'
            7'd4  : tpl_code = 6'd37;   // '#'
            7'd5  : tpl_code = 6'd37;   // '#'
            7'd6  : tpl_code = 6'd37;   // '#'
            7'd7  : tpl_code = 6'd37;   // ' '
            7'd8  : tpl_code = 6'd37;   // ' '
            7'd9  : tpl_code = 6'd30;   // 'U'
            7'd10 : tpl_code = 6'd36;   // '='
            7'd11 : tpl_code = 6'd37;   // '#'
            7'd12 : tpl_code = 6'd37;   // '#'
            7'd13 : tpl_code = 6'd37;   // '#'
            7'd14 : tpl_code = 6'd37;   // '#'
            7'd15 : tpl_code = 6'd37;   // ' '
            7'd16 : tpl_code = 6'd37;   // ' '
            7'd17 : tpl_code = 6'd29;   // 'T'
            7'd18 : tpl_code = 6'd11;   // 'B'
            7'd19 : tpl_code = 6'd36;   // '='
            7'd20 : tpl_code = 6'd37;   // '#'
            7'd21 : tpl_code = 6'd37;   // '#'
            7'd22 : tpl_code = 6'd37;   // '#'
            7'd23 : tpl_code = 6'd37;   // '#'
            7'd24 : tpl_code = 6'd37;   // ' '
            7'd25 : tpl_code = 6'd37;   // ' '
            7'd26 : tpl_code = 6'd37;   // ' '
            7'd27 : tpl_code = 6'd37;   // ' '
            7'd28 : tpl_code = 6'd37;   // ' '
            7'd29 : tpl_code = 6'd37;   // ' '
            7'd30 : tpl_code = 6'd37;   // ' '
            7'd31 : tpl_code = 6'd37;   // ' '
            7'd32 : tpl_code = 6'd31;   // 'V'
            7'd33 : tpl_code = 6'd25;   // 'P'
            7'd34 : tpl_code = 6'd36;   // '='
            7'd35 : tpl_code = 6'd37;   // '#'
            7'd36 : tpl_code = 6'd37;   // '#'
            7'd37 : tpl_code = 6'd37;   // '#'
            7'd38 : tpl_code = 6'd37;   // '#'
            7'd39 : tpl_code = 6'd37;   // ' '
            7'd40 : tpl_code = 6'd37;   // ' '
            7'd41 : tpl_code = 6'd15;   // 'F'
            7'd42 : tpl_code = 6'd27;   // 'R'
            7'd43 : tpl_code = 6'd36;   // '='
            7'd44 : tpl_code = 6'd37;   // '#'
            7'd45 : tpl_code = 6'd37;   // '#'
            7'd46 : tpl_code = 6'd37;   // '#'
            7'd47 : tpl_code = 6'd37;   // '#'
            7'd48 : tpl_code = 6'd37;   // ' '
            7'd49 : tpl_code = 6'd37;   // ' '
            7'd50 : tpl_code = 6'd37;   // ' '
            7'd51 : tpl_code = 6'd37;   // ' '
            7'd52 : tpl_code = 6'd37;   // ' '
            7'd53 : tpl_code = 6'd37;   // ' '
            7'd54 : tpl_code = 6'd37;   // ' '
            7'd55 : tpl_code = 6'd37;   // ' '
            7'd56 : tpl_code = 6'd37;   // ' '
            7'd57 : tpl_code = 6'd37;   // ' '
            7'd58 : tpl_code = 6'd37;   // ' '
            7'd59 : tpl_code = 6'd37;   // ' '
            7'd60 : tpl_code = 6'd37;   // ' '
            7'd61 : tpl_code = 6'd37;   // ' '
            7'd62 : tpl_code = 6'd37;   // ' '
            7'd63 : tpl_code = 6'd37;   // ' '
            default: tpl_code = 6'd37;   // 空格
        endcase
    end

    // 5 个十六进制数字域(每域 4 列，高位在左)
    wire [4:0] sh0 = (C0 + 5'd3 - col) * 5'd4;
    wire [4:0] sh1 = (C1 + 5'd3 - col) * 5'd4;
    wire [4:0] sh2 = (C2 + 5'd3 - col) * 5'd4;
    wire [4:0] sh3 = (C3 + 5'd3 - col) * 5'd4;
    wire [4:0] sh4 = (C4 + 5'd3 - col) * 5'd4;

    wire is_v0 = (row == 1'b0) && (col >= C0) && (col <= C0 + 5'd3);
    wire is_v1 = (row == 1'b0) && (col >= C1) && (col <= C1 + 5'd3);
    wire is_v2 = (row == 1'b0) && (col >= C2) && (col <= C2 + 5'd3);
    wire is_v3 = (row == 1'b1) && (col >= C3) && (col <= C3 + 5'd3);
    wire is_v4 = (row == 1'b1) && (col >= C4) && (col <= C4 + 5'd3);

    wire [3:0] d0 = val0 >> sh0;
    wire [3:0] d1 = val1 >> sh1;
    wire [3:0] d2 = val2 >> sh2;
    wire [3:0] d3 = val3 >> sh3;
    wire [3:0] d4 = val4 >> sh4;

    wire [5:0] code = is_v0 ? {2'b00, d0} :
                      is_v1 ? {2'b00, d1} :
                      is_v2 ? {2'b00, d2} :
                      is_v3 ? {2'b00, d3} :
                      is_v4 ? {2'b00, d4} : tpl_code;

    wire [7:0] bits;
    font_rom u_font (
        .ch  (code),
        .row (frow),
        .bits(bits)
    );

    assign hit   = de && in_x && in_y && bits[3'd7 - dx[2:0]];
    assign color = COL;

endmodule
