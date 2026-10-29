//==============================================================================
// 层: 抽象(图形层)  文件: abs/text_layer.v   [v2: 两页模板]  (由工具生成, 勿手改)
// 功能: 文本图层，2 行 x 32 列，5 个数字域；page 选择显示页:
//   page=0  行0 "AD=####  U=####  TB=####"   行1 "VP=####  FR=####"
//   page=1  行0 "HI=#### LO=####  AV=####"   行1 "PE=#### DU=####"
// 数字域列位置两页一致(3/11/20/3/11)，上层只需按页切换 val0..val4 的数值。
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
    parameter integer VAL4_COL0 = 11,
    parameter [11:0]  COL       = 12'hFFF
)(
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    input  wire        page,
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

    // 模板字符码：{page,row} 共 4 行 x 32 列
    reg [5:0] tpl_code;
    always @(*) begin
        case ({page, row, col})
            8'd0  : tpl_code = 6'd10;   // 'A'
            8'd1  : tpl_code = 6'd13;   // 'D'
            8'd2  : tpl_code = 6'd36;   // '='
            8'd3  : tpl_code = 6'd37;   // '#'
            8'd4  : tpl_code = 6'd37;   // '#'
            8'd5  : tpl_code = 6'd37;   // '#'
            8'd6  : tpl_code = 6'd37;   // '#'
            8'd7  : tpl_code = 6'd37;   // ' '
            8'd8  : tpl_code = 6'd37;   // ' '
            8'd9  : tpl_code = 6'd30;   // 'U'
            8'd10 : tpl_code = 6'd36;   // '='
            8'd11 : tpl_code = 6'd37;   // '#'
            8'd12 : tpl_code = 6'd37;   // '#'
            8'd13 : tpl_code = 6'd37;   // '#'
            8'd14 : tpl_code = 6'd37;   // '#'
            8'd15 : tpl_code = 6'd37;   // ' '
            8'd16 : tpl_code = 6'd37;   // ' '
            8'd17 : tpl_code = 6'd29;   // 'T'
            8'd18 : tpl_code = 6'd11;   // 'B'
            8'd19 : tpl_code = 6'd36;   // '='
            8'd20 : tpl_code = 6'd37;   // '#'
            8'd21 : tpl_code = 6'd37;   // '#'
            8'd22 : tpl_code = 6'd37;   // '#'
            8'd23 : tpl_code = 6'd37;   // '#'
            8'd24 : tpl_code = 6'd37;   // ' '
            8'd25 : tpl_code = 6'd37;   // ' '
            8'd26 : tpl_code = 6'd37;   // ' '
            8'd27 : tpl_code = 6'd37;   // ' '
            8'd28 : tpl_code = 6'd37;   // ' '
            8'd29 : tpl_code = 6'd37;   // ' '
            8'd30 : tpl_code = 6'd37;   // ' '
            8'd31 : tpl_code = 6'd37;   // ' '
            8'd32 : tpl_code = 6'd31;   // 'V'
            8'd33 : tpl_code = 6'd25;   // 'P'
            8'd34 : tpl_code = 6'd36;   // '='
            8'd35 : tpl_code = 6'd37;   // '#'
            8'd36 : tpl_code = 6'd37;   // '#'
            8'd37 : tpl_code = 6'd37;   // '#'
            8'd38 : tpl_code = 6'd37;   // '#'
            8'd39 : tpl_code = 6'd37;   // ' '
            8'd40 : tpl_code = 6'd37;   // ' '
            8'd41 : tpl_code = 6'd15;   // 'F'
            8'd42 : tpl_code = 6'd27;   // 'R'
            8'd43 : tpl_code = 6'd36;   // '='
            8'd44 : tpl_code = 6'd37;   // '#'
            8'd45 : tpl_code = 6'd37;   // '#'
            8'd46 : tpl_code = 6'd37;   // '#'
            8'd47 : tpl_code = 6'd37;   // '#'
            8'd48 : tpl_code = 6'd37;   // ' '
            8'd49 : tpl_code = 6'd37;   // ' '
            8'd50 : tpl_code = 6'd37;   // ' '
            8'd51 : tpl_code = 6'd37;   // ' '
            8'd52 : tpl_code = 6'd37;   // ' '
            8'd53 : tpl_code = 6'd37;   // ' '
            8'd54 : tpl_code = 6'd37;   // ' '
            8'd55 : tpl_code = 6'd37;   // ' '
            8'd56 : tpl_code = 6'd37;   // ' '
            8'd57 : tpl_code = 6'd37;   // ' '
            8'd58 : tpl_code = 6'd37;   // ' '
            8'd59 : tpl_code = 6'd37;   // ' '
            8'd60 : tpl_code = 6'd37;   // ' '
            8'd61 : tpl_code = 6'd37;   // ' '
            8'd62 : tpl_code = 6'd37;   // ' '
            8'd63 : tpl_code = 6'd37;   // ' '
            8'd64 : tpl_code = 6'd17;   // 'H'
            8'd65 : tpl_code = 6'd18;   // 'I'
            8'd66 : tpl_code = 6'd36;   // '='
            8'd67 : tpl_code = 6'd37;   // '#'
            8'd68 : tpl_code = 6'd37;   // '#'
            8'd69 : tpl_code = 6'd37;   // '#'
            8'd70 : tpl_code = 6'd37;   // '#'
            8'd71 : tpl_code = 6'd37;   // ' '
            8'd72 : tpl_code = 6'd19;   // 'L'
            8'd73 : tpl_code = 6'd24;   // 'O'
            8'd74 : tpl_code = 6'd36;   // '='
            8'd75 : tpl_code = 6'd37;   // '#'
            8'd76 : tpl_code = 6'd37;   // '#'
            8'd77 : tpl_code = 6'd37;   // '#'
            8'd78 : tpl_code = 6'd37;   // '#'
            8'd79 : tpl_code = 6'd37;   // ' '
            8'd80 : tpl_code = 6'd37;   // ' '
            8'd81 : tpl_code = 6'd10;   // 'A'
            8'd82 : tpl_code = 6'd31;   // 'V'
            8'd83 : tpl_code = 6'd36;   // '='
            8'd84 : tpl_code = 6'd37;   // '#'
            8'd85 : tpl_code = 6'd37;   // '#'
            8'd86 : tpl_code = 6'd37;   // '#'
            8'd87 : tpl_code = 6'd37;   // '#'
            8'd88 : tpl_code = 6'd37;   // ' '
            8'd89 : tpl_code = 6'd37;   // ' '
            8'd90 : tpl_code = 6'd37;   // ' '
            8'd91 : tpl_code = 6'd37;   // ' '
            8'd92 : tpl_code = 6'd37;   // ' '
            8'd93 : tpl_code = 6'd37;   // ' '
            8'd94 : tpl_code = 6'd37;   // ' '
            8'd95 : tpl_code = 6'd37;   // ' '
            8'd96 : tpl_code = 6'd25;   // 'P'
            8'd97 : tpl_code = 6'd14;   // 'E'
            8'd98 : tpl_code = 6'd36;   // '='
            8'd99 : tpl_code = 6'd37;   // '#'
            8'd100: tpl_code = 6'd37;   // '#'
            8'd101: tpl_code = 6'd37;   // '#'
            8'd102: tpl_code = 6'd37;   // '#'
            8'd103: tpl_code = 6'd37;   // ' '
            8'd104: tpl_code = 6'd13;   // 'D'
            8'd105: tpl_code = 6'd30;   // 'U'
            8'd106: tpl_code = 6'd36;   // '='
            8'd107: tpl_code = 6'd37;   // '#'
            8'd108: tpl_code = 6'd37;   // '#'
            8'd109: tpl_code = 6'd37;   // '#'
            8'd110: tpl_code = 6'd37;   // '#'
            8'd111: tpl_code = 6'd37;   // ' '
            8'd112: tpl_code = 6'd37;   // ' '
            8'd113: tpl_code = 6'd37;   // ' '
            8'd114: tpl_code = 6'd37;   // ' '
            8'd115: tpl_code = 6'd37;   // ' '
            8'd116: tpl_code = 6'd37;   // ' '
            8'd117: tpl_code = 6'd37;   // ' '
            8'd118: tpl_code = 6'd37;   // ' '
            8'd119: tpl_code = 6'd37;   // ' '
            8'd120: tpl_code = 6'd37;   // ' '
            8'd121: tpl_code = 6'd37;   // ' '
            8'd122: tpl_code = 6'd37;   // ' '
            8'd123: tpl_code = 6'd37;   // ' '
            8'd124: tpl_code = 6'd37;   // ' '
            8'd125: tpl_code = 6'd37;   // ' '
            8'd126: tpl_code = 6'd37;   // ' '
            8'd127: tpl_code = 6'd37;   // ' '
            default: tpl_code = 6'd37;
        endcase
    end

    // 5 个十六进制数字域
    wire [4:0] sh0 = (C0 + 5'd3 - col) * 5'd4;
    wire [4:0] sh1 = (C1 + 5'd3 - col) * 5'd4;
    wire [4:0] sh2 = (C2 + 5'd3 - col) * 5'd4;
    wire [4:0] sh3 = (C3 + 5'd3 - col) * 5'd4;
    wire [4:0] sh4 = (C4 + 5'd3 - col) * 5'd4;

    wire is_v0 = (col >= C0) && (col <= C0 + 5'd3);
    wire is_v1 = (col >= C1) && (col <= C1 + 5'd3);
    wire is_v2 = (col >= C2) && (col <= C2 + 5'd3);
    wire is_v3 = (row == 1'b1) && (col >= C3) && (col <= C3 + 5'd3);
    wire is_v4 = (row == 1'b1) && (col >= C4) && (col <= C4 + 5'd3);
    wire is_v01 = (row == 1'b0) && (col >= C0) && (col <= C0 + 5'd3);
    wire is_v11 = (row == 1'b0) && (col >= C1) && (col <= C1 + 5'd3);
    wire is_v21 = (row == 1'b0) && (col >= C2) && (col <= C2 + 5'd3);

    wire [3:0] d0 = val0 >> sh0;
    wire [3:0] d1 = val1 >> sh1;
    wire [3:0] d2 = val2 >> sh2;
    wire [3:0] d3 = val3 >> sh3;
    wire [3:0] d4 = val4 >> sh4;

    wire [5:0] code = is_v01 ? {2'b00, d0} :
                      is_v11 ? {2'b00, d1} :
                      is_v21 ? {2'b00, d2} :
                      is_v3  ? {2'b00, d3} :
                      is_v4  ? {2'b00, d4} : tpl_code;

    wire [7:0] bits;
    font_rom u_font (
        .ch  (code),
        .row (frow),
        .bits(bits)
    );

    assign hit   = de && in_x && in_y && bits[3'd7 - dx[2:0]];
    assign color = COL;

endmodule
