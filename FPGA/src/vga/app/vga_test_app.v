//==============================================================================
// 层: 应用(屏幕自检)  文件: app/vga_test_app.v
// 功能: 屏幕自检图案发生器（只依赖 HAL 的 font_rom，不修改任何下层封装）
//
// 5 个自检画面(约 2s 自动切换, 也可短按按键手动切换):
//   0 彩条      : 8 色竖条(白/黄/青/绿/品红/红/蓝/黑) —— 查 RGB 接线与电平
//   1 灰阶      : 8 级灰度横条                —— 查 DAC 线性/位序
//   2 棋盘格    : 32x32 黑白方格              —— 查像素时钟/同步稳定性
//   3 边框+移动方块 : 四边白框 + 十字 + 移动绿块 —— 查几何/满屏/无撕裂
//   4 文字      : "VGA TEST" / "640X480 60HZ" —— 查字模与像素对齐
//
// 接口: 输入当前像素坐标 (px,py) 与 de；输出该像素颜色 RGB444
//       所有逻辑纯组合(除模式/移动计数器)，不占用 BSRAM/DSP
//==============================================================================
`timescale 1ns / 1ps

module vga_test_app #(
    parameter integer H_VIS      = 640,
    parameter integer V_VIS      = 480,
    parameter integer AUTO_FRAMES = 120,     // 自动切换间隔(帧)，60Hz 下约 2s
    parameter [11:0]  COL_BG     = 12'h012
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        ev_next,   // 单周期: 手动切换到下一画面
    input  wire        frame,     // 帧起始脉冲
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    output reg  [11:0] rgb,
    output wire [2:0]  mode_o
);

    localparam integer NMODE = 5;

    reg [2:0]  mode;
    reg [7:0]  auto_cnt;
    reg [9:0]  pos;          // 移动方块的水平位置
    reg [15:0] frame_cnt;

    assign mode_o = mode;

    //------------------------------------------------------------------
    // 画面切换与动画计数
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            mode      <= 3'd0;
            auto_cnt  <= 8'd0;
            pos       <= 10'd0;
            frame_cnt <= 16'd0;
        end
        else begin
            frame_cnt <= frame_cnt + 16'd1;

            if (frame) begin
                pos <= (pos >= 10'd592) ? 10'd0 : (pos + 10'd4);

                if (auto_cnt == (AUTO_FRAMES-1)) begin
                    auto_cnt <= 8'd0;
                    mode     <= (mode == (NMODE-1)) ? 3'd0 : (mode + 3'd1);
                end
                else begin
                    auto_cnt <= auto_cnt + 8'd1;
                end
            end

            if (ev_next) begin          // 按键优先
                mode     <= (mode == (NMODE-1)) ? 3'd0 : (mode + 3'd1);
                auto_cnt <= 8'd0;
            end
        end
    end

    //------------------------------------------------------------------
    // 画面 0: 8 色竖条（每段 64 像素）
    //------------------------------------------------------------------
    wire [2:0] bar_idx = px[8:6];

    reg [11:0] bar_col;
    always @(*) begin
        case (bar_idx)
            3'd0: bar_col = 12'hFFF;   // 白
            3'd1: bar_col = 12'hFF0;   // 黄
            3'd2: bar_col = 12'h0FF;   // 青
            3'd3: bar_col = 12'h0F0;   // 绿
            3'd4: bar_col = 12'hF0F;   // 品红
            3'd5: bar_col = 12'hF00;   // 红
            3'd6: bar_col = 12'h00F;   // 蓝
            default: bar_col = 12'h000; // 黑
        endcase
    end

    //------------------------------------------------------------------
    // 画面 1: 8 级灰阶横条（每级 58 像素）
    //------------------------------------------------------------------
    wire [3:0] gray_lvl = py[8:6];          // 0..7
    wire [11:0] gray_col = {gray_lvl, gray_lvl, gray_lvl};

    //------------------------------------------------------------------
    // 画面 2: 32x32 棋盘格
    //------------------------------------------------------------------
    wire chk = px[5] ^ py[5];

    //------------------------------------------------------------------
    // 画面 3: 边框 + 十字 + 移动方块
    //------------------------------------------------------------------
    wire border = (px < 12'd4) || (px >= (H_VIS-4)) ||
                  (py < 12'd4) || (py >= (V_VIS-4));
    wire cross  = ((py >= 12'd238) && (py <= 12'd241)) ||
                  ((px >= 12'd318) && (px <= 12'd321));
    wire [11:0] box_x = {2'b00, pos};
    wire moving = (px >= box_x) && (px < (box_x + 12'd48)) &&
                  (py >= 12'd200) && (py < 12'd248);

    //------------------------------------------------------------------
    // 画面 4: 两行文字（复用 HAL 的 8x8 字模）
    //------------------------------------------------------------------
    wire [11:0] tx0 = 12'd288;      // "VGA TEST" 居中: (640-64)/2
    wire [11:0] ty0 = 12'd200;
    wire [11:0] tx1 = 12'd272;      // "640X480 60HZ" 居中: (640-96)/2
    wire [11:0] ty1 = 12'd232;

    wire in_t0 = (px >= tx0) && (px < (tx0 + 12'd64)) &&
                 (py >= ty0) && (py < (ty0 + 12'd8));
    wire in_t1 = (px >= tx1) && (px < (tx1 + 12'd96)) &&
                 (py >= ty1) && (py < (ty1 + 12'd8));

    wire [4:0] c0 = (px - tx0) >> 3;    // 0..7
    wire [4:0] c1 = (px - tx1) >> 3;    // 0..11
    wire [2:0] r0 = (py - ty0);
    wire [2:0] r1 = (py - ty1);

    reg [5:0] code0, code1;
    always @(*) begin
        case (c0)
            5'd0: code0 = 6'd31;   // V
            5'd1: code0 = 6'd16;   // G
            5'd2: code0 = 6'd10;   // A
            5'd3: code0 = 6'd37;   // 空格
            5'd4: code0 = 6'd29;   // T
            5'd5: code0 = 6'd14;   // E
            5'd6: code0 = 6'd28;   // S
            default: code0 = 6'd29; // T
        endcase
    end

    always @(*) begin
        case (c1)
            5'd0:  code1 = 6'd6;    // 6
            5'd1:  code1 = 6'd4;    // 4
            5'd2:  code1 = 6'd0;    // 0
            5'd3:  code1 = 6'd33;   // X
            5'd4:  code1 = 6'd4;    // 4
            5'd5:  code1 = 6'd8;    // 8
            5'd6:  code1 = 6'd0;    // 0
            5'd7:  code1 = 6'd37;   // 空格
            5'd8:  code1 = 6'd6;    // 6
            5'd9:  code1 = 6'd0;    // 0
            5'd10: code1 = 6'd17;   // H
            default: code1 = 6'd35; // Z
        endcase
    end

    wire [5:0] ch_sel  = in_t1 ? code1 : code0;
    wire [2:0] row_sel = in_t1 ? r1 : r0;

    wire [7:0] font_bits;
    font_rom u_font (
        .ch  (ch_sel),
        .row (row_sel),
        .bits(font_bits)
    );

    wire [2:0] bit_idx = in_t1 ? (px - tx1) : (px - tx0);
    wire text_hit = (in_t0 || in_t1) && font_bits[3'd7 - bit_idx];

    //------------------------------------------------------------------
    // 画面选择
    //------------------------------------------------------------------
    always @(*) begin
        if (!de)
            rgb = COL_BG;
        else begin
            case (mode)
                3'd0: rgb = bar_col;
                3'd1: rgb = gray_col;
                3'd2: rgb = chk ? 12'hFFF : 12'h000;
                3'd3: rgb = border ? 12'hFFF :
                             cross  ? 12'hF00 :
                             moving ? 12'h0F0 : COL_BG;
                3'd4: rgb = text_hit ? 12'hFFF : COL_BG;
                default: rgb = COL_BG;
            endcase
        end
    end

endmodule
