//==============================================================================
// 层: 抽象(图形层)  文件: abs/menu_layer.v   [v2: 双页菜单]
// 功能: 屏幕设置菜单（OSD），共两页
//   第 0 页 示波器: CH0 CH1 VS0 VS1 VP0 VP1 HSC TB  ROL   (9 项)
//   第 1 页 信号源: WAV FRE ATT PHA                       (4 项)
//   每行格式 "[项号] XXX=值"，选中行亮底高亮，带边框。
//   面板位于左上角 (8,8)，行高 8 像素，宽 60 像素，高度随页内项数变化。
//==============================================================================
`timescale 1ns / 1ps

module menu_layer (
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    input  wire        on,
    input  wire [3:0]  sel,
    input  wire        page,       // 0=示波器 1=信号源
    input  wire        ena_sig,    // 0=外部 ADC 模式，信号源页不可用
    input  wire [3:0]  v0, v1, v2, v3, v4, v5, v6, v7, v8,   // 第 0 页 9 项
    input  wire [3:0]  w0, w1, w2, w3,                      // 第 1 页 4 项
    output wire        hit,
    output wire [11:0] color
);

    localparam [11:0] X0 = 12'd8;
    localparam [11:0] Y0 = 12'd8;
    localparam [11:0] W  = 12'd60;

    localparam [11:0] C_BG     = 12'h123;
    localparam [11:0] C_BORDER = 12'hCC3;
    localparam [11:0] C_SELBG  = 12'h553;
    localparam [11:0] C_TEXT   = 12'hFFF;

    wire       pg   = page && ena_sig;             // 信号源页仅在可用时显示
    wire [3:0] rows = pg ? 4'd4 : 4'd9;            // 本页项数
    wire [11:0] H   = {2'b00, rows, 3'b000} + 12'd8;  // rows*8 + 8

    wire [11:0] rx = px - X0;
    wire [11:0] ry = py - Y0;
    wire in_panel = on && de && (px >= X0) && (px < X0 + W) && (py >= Y0) && (py < Y0 + H);
    wire border = in_panel && ((rx < 12'd1) || (rx >= W - 12'd1) ||
                               (ry < 12'd1) || (ry >= H - 12'd1));

    wire [11:0] tx = rx - 12'd2;
    wire [11:0] ty = ry - 12'd4;
    wire in_text = in_panel && (rx >= 12'd2) && (rx < W - 12'd2) &&
                   (ry >= 12'd4) && (ry < H - 12'd4);

    wire [3:0] row       = ty[6:3];
    wire [2:0] glyph_row = ty[2:0];
    wire [3:0] col       = tx[5:3];
    wire [2:0] glyph_col = tx[2:0];
    wire row_ok = (row < rows) && (col < 4'd7);
    wire sel_row = (row == sel);

    //------------------------------------------------------------------
    // 标签（6bit 字符码 x3）
    //------------------------------------------------------------------
    reg [17:0] label;
    always @(*) begin
        if (!pg) begin
            case (row)
                4'd0: label = {6'd12, 6'd17, 6'd0 };   // CH0
                4'd1: label = {6'd12, 6'd17, 6'd1 };   // CH1
                4'd2: label = {6'd31, 6'd28, 6'd0 };   // VS0
                4'd3: label = {6'd31, 6'd28, 6'd1 };   // VS1
                4'd4: label = {6'd31, 6'd25, 6'd0 };   // VP0
                4'd5: label = {6'd31, 6'd25, 6'd1 };   // VP1
                4'd6: label = {6'd17, 6'd28, 6'd12};   // HSC 水平缩放
                4'd7: label = {6'd29, 6'd11, 6'd37};   // TB  时基
                default: label = {6'd27, 6'd24, 6'd19}; // ROL 滚动
            endcase
        end
        else begin
            case (row)
                4'd0: label = {6'd32, 6'd10, 6'd31};   // WAV 波形
                4'd1: label = {6'd15, 6'd27, 6'd14};   // FRE 频率
                4'd2: label = {6'd10, 6'd29, 6'd29};   // ATT 幅度
                default: label = {6'd25, 6'd17, 6'd10}; // PHA 相位
            endcase
        end
    end

    //------------------------------------------------------------------
    // 每项的值
    //------------------------------------------------------------------
    reg [3:0] val;
    always @(*) begin
        if (!pg) begin
            case (row)
                4'd0: val = v0;  4'd1: val = v1;
                4'd2: val = v2;  4'd3: val = v3;
                4'd4: val = v4;  4'd5: val = v5;
                4'd6: val = v6;  4'd7: val = v7;
                default: val = v8;
            endcase
        end
        else begin
            case (row)
                4'd0: val = w0;  4'd1: val = w1;
                4'd2: val = w2;  default: val = w3;
            endcase
        end
    end

    //------------------------------------------------------------------
    // 字符选择
    //------------------------------------------------------------------
    reg [5:0] ch;
    always @(*) begin
        case (col)
            4'd0: ch = {2'b00, row};
            4'd1: ch = 6'd37;
            4'd2: ch = label[17:12];
            4'd3: ch = label[11:6];
            4'd4: ch = label[5:0];
            4'd5: ch = 6'd36;
            default: ch = {2'b00, val};     // 4bit 值直接取字模：0-9 数字，10-15 显示 A-F
        endcase
    end

    wire [7:0] glyph_bits;
    font_rom u_font (.ch(ch), .row(glyph_row), .bits(glyph_bits));
    wire pix_on = glyph_bits[3'd7 - glyph_col];

    assign hit = (in_panel && border) ? 1'b1 :
                 (in_text && row_ok)  ? 1'b1 : 1'b0;

    assign color = border                        ? C_BORDER :
                   (in_text && row_ok && pix_on) ? C_TEXT   :
                   (in_text && row_ok && sel_row) ? C_SELBG :
                                                   C_BG      ;

endmodule