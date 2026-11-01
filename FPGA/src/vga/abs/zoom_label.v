//==============================================================================
// 层: 抽象(图形层)  文件: abs/zoom_label.v
// 功能: 屏幕底部状态行：横轴/纵轴缩放档 + 整屏时间 + 整屏电压跨度
//
//   显示格式：  X:+2 Y:-1 T=180U V=3.30V
//     X: 横轴缩放档，每按一次放大 +0.5、缩小 -0.5（scope_app.hzoom10 计数）
//     Y: 纵轴缩放档 =(vstep x 0.5)，取 SW2 选中通道
//     T: 整屏时间（640 像素覆盖的真实时间），U=us，S=s
//     V: 整屏电压跨度（纵向 448 像素覆盖的电压范围）
//        ADC 0..1023 对应 0..3.3V -> 满屏跨度 = 448*4096/(gain*1024)*3.3V
//        默认增益 1792(=7/16) 时正好 3.30V（满量程）
//
//   位置：px 8..263 / py 464..471（第 58 字符行，波形区 py<448 之外）
//   字符码：'X'=33 'Y'=34 'T'=29 'V'=31 '='=36 ':'=38 '+'=41 '-'=40
//           ' '=37 '.'=39 'S'=28 'U'=34，数字 0..9 = 0..9
//==============================================================================
`timescale 1ns / 1ps

module zoom_label #(
    parameter integer X0 = 8,
    parameter integer Y0 = 464,
    parameter [11:0]  COL = 12'hFFF
)(
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        de,
    input  wire [6:0]  hscale,
    input  wire [3:0]  tb_idx,
    input  wire        adc_mode,
    input  wire signed [9:0] x10,
    input  wire signed [9:0] y10,
    input  wire [5:0]  gsel,        // 当前通道增益表索引 0..60（V 字段用）
    output wire        hit,
    output wire [11:0] color
);

    reg [3:0] sb;
    always @(*) begin
        if      (hscale <= 7'd1)  sb = 4'd0;
        else if (hscale <= 7'd3)  sb = 4'd1;
        else if (hscale <= 7'd7)  sb = 4'd2;
        else if (hscale <= 7'd15) sb = 4'd3;
        else if (hscale <= 7'd31) sb = 4'd4;
        else if (hscale <= 7'd47) sb = 4'd5;
        else if (hscale <= 7'd64) sb = 4'd6;
        else if (hscale <= 7'd84) sb = 4'd7;
        else                      sb = 4'd8;
    end

    // 整屏时间：两种采样节拍各一张表
    reg [35:0] sp_adc, sp_gen;
    always @(*) begin
        case ({tb_idx, sb})
            8'd0: sp_adc = 36'h881108241;
            8'd1: sp_adc = 36'h883006244;
            8'd2: sp_adc = 36'h95c0419c0;
            8'd3: sp_adc = 36'h95c0829c0;
            8'd4: sp_adc = 36'h95c1049c0;
            8'd5: sp_adc = 36'h95c1c79c0;
            8'd6: sp_adc = 36'h95c0419c1;
            8'd7: sp_adc = 36'h95c1c49c1;
            8'd8: sp_adc = 36'h95c0809c2;
            8'd16: sp_adc = 36'h962042249;
            8'd17: sp_adc = 36'h882008102;
            8'd18: sp_adc = 36'h883185105;
            8'd19: sp_adc = 36'h95c0419c0;
            8'd20: sp_adc = 36'h95c0829c0;
            8'd21: sp_adc = 36'h95c2439c0;
            8'd22: sp_adc = 36'h95c1859c0;
            8'd23: sp_adc = 36'h95c0c79c0;
            8'd24: sp_adc = 36'h95c0409c1;
            8'd32: sp_adc = 36'h962006244;
            8'd33: sp_adc = 36'h881004081;
            8'd34: sp_adc = 36'h8822021c2;
            8'd35: sp_adc = 36'h883185105;
            8'd36: sp_adc = 36'h95c0419c0;
            8'd37: sp_adc = 36'h95c2419c0;
            8'd38: sp_adc = 36'h95c2029c0;
            8'd39: sp_adc = 36'h95c1c39c0;
            8'd40: sp_adc = 36'h95c0459c0;
            8'd48: sp_adc = 36'h962008102;
            8'd49: sp_adc = 36'h962000086;
            8'd50: sp_adc = 36'h8811060c1;
            8'd51: sp_adc = 36'h8822021c2;
            8'd52: sp_adc = 36'h883185105;
            8'd53: sp_adc = 36'h886087189;
            8'd54: sp_adc = 36'h95c1019c0;
            8'd55: sp_adc = 36'h95c2019c0;
            8'd56: sp_adc = 36'h95c1429c0;
            8'd64: sp_adc = 36'h962004081;
            8'd65: sp_adc = 36'h962000043;
            8'd66: sp_adc = 36'h962002206;
            8'd67: sp_adc = 36'h8811060c1;
            8'd68: sp_adc = 36'h8822021c2;
            8'd69: sp_adc = 36'h883183204;
            8'd70: sp_adc = 36'h884104246;
            8'd71: sp_adc = 36'h882106049;
            8'd72: sp_adc = 36'h95c0c19c0;
            8'd80: sp_adc = 36'h965880086;
            8'd81: sp_adc = 36'h962005141;
            8'd82: sp_adc = 36'h962240103;
            8'd83: sp_adc = 36'h962201206;
            8'd84: sp_adc = 36'h8870c60c1;
            8'd85: sp_adc = 36'h8841c1102;
            8'd86: sp_adc = 36'h881047103;
            8'd87: sp_adc = 36'h886008144;
            8'd88: sp_adc = 36'h8821810c6;
            8'd96: sp_adc = 36'h965880043;
            8'd97: sp_adc = 36'h9658851c7;
            8'd98: sp_adc = 36'h9621401c1;
            8'd99: sp_adc = 36'h962240103;
            8'd100: sp_adc = 36'h962201206;
            8'd101: sp_adc = 36'h887200081;
            8'd102: sp_adc = 36'h8861431c1;
            8'd103: sp_adc = 36'h883009082;
            8'd104: sp_adc = 36'h881205043;
            8'd112: sp_adc = 36'h965885141;
            8'd113: sp_adc = 36'h965887203;
            8'd114: sp_adc = 36'h965881148;
            8'd115: sp_adc = 36'h9620801c1;
            8'd116: sp_adc = 36'h962140103;
            8'd117: sp_adc = 36'h962183006;
            8'd118: sp_adc = 36'h9621c6188;
            8'd119: sp_adc = 36'h8870c4041;
            8'd120: sp_adc = 36'h8801c7141;
            8'd128: sp_adc = 36'h9659621c7;
            8'd129: sp_adc = 36'h965883241;
            8'd130: sp_adc = 36'h965886084;
            8'd131: sp_adc = 36'h965881148;
            8'd132: sp_adc = 36'h9620801c1;
            8'd133: sp_adc = 36'h962201003;
            8'd134: sp_adc = 36'h9620c30c4;
            8'd135: sp_adc = 36'h9622011c5;
            8'd136: sp_adc = 36'h962148207;
            8'd144: sp_adc = 36'h965962203;
            8'd145: sp_adc = 36'h965962189;
            8'd146: sp_adc = 36'h965882042;
            8'd147: sp_adc = 36'h965883084;
            8'd148: sp_adc = 36'h965887108;
            8'd149: sp_adc = 36'h962040141;
            8'd150: sp_adc = 36'h962185042;
            8'd151: sp_adc = 36'h962144202;
            8'd152: sp_adc = 36'h962082243;
            8'd160: sp_adc = 36'h965962241;
            8'd161: sp_adc = 36'h965962204;
            8'd162: sp_adc = 36'h965885001;
            8'd163: sp_adc = 36'h965880042;
            8'd164: sp_adc = 36'h965889044;
            8'd165: sp_adc = 36'h965883107;
            8'd166: sp_adc = 36'h9621c6001;
            8'd167: sp_adc = 36'h962200101;
            8'd168: sp_adc = 36'h962044241;
            8'd176: sp_adc = 36'h9658859c9;
            8'd177: sp_adc = 36'h965962102;
            8'd178: sp_adc = 36'h965962085;
            8'd179: sp_adc = 36'h965885001;
            8'd180: sp_adc = 36'h965880042;
            8'd181: sp_adc = 36'h9658811c3;
            8'd182: sp_adc = 36'h9658830c5;
            8'd183: sp_adc = 36'h965884007;
            8'd184: sp_adc = 36'h9658801c9;
            8'd192: sp_adc = 36'h9658889c4;
            8'd193: sp_adc = 36'h965962081;
            8'd194: sp_adc = 36'h965962182;
            8'd195: sp_adc = 36'h965962085;
            8'd196: sp_adc = 36'h965885001;
            8'd197: sp_adc = 36'h965886201;
            8'd198: sp_adc = 36'h965887182;
            8'd199: sp_adc = 36'h965882143;
            8'd200: sp_adc = 36'h965885204;
            8'd208: sp_adc = 36'h9658829c3;
            8'd209: sp_adc = 36'h9658899c7;
            8'd210: sp_adc = 36'h9659621c1;
            8'd211: sp_adc = 36'h965962143;
            8'd212: sp_adc = 36'h965962007;
            8'd213: sp_adc = 36'h965884081;
            8'd214: sp_adc = 36'h9658881c1;
            8'd215: sp_adc = 36'h9658850c2;
            8'd216: sp_adc = 36'h965883083;
            8'd224: sp_adc = 36'h9658829c3;
            8'd225: sp_adc = 36'h9658899c7;
            8'd226: sp_adc = 36'h9659621c1;
            8'd227: sp_adc = 36'h965962143;
            8'd228: sp_adc = 36'h965962007;
            8'd229: sp_adc = 36'h965884081;
            8'd230: sp_adc = 36'h9658881c1;
            8'd231: sp_adc = 36'h9658850c2;
            8'd232: sp_adc = 36'h965883083;
            8'd240: sp_adc = 36'h9658829c3;
            8'd241: sp_adc = 36'h9658899c7;
            8'd242: sp_adc = 36'h9659621c1;
            8'd243: sp_adc = 36'h965962143;
            8'd244: sp_adc = 36'h965962007;
            8'd245: sp_adc = 36'h965884081;
            8'd246: sp_adc = 36'h9658881c1;
            8'd247: sp_adc = 36'h9658850c2;
            8'd248: sp_adc = 36'h965883083;
            default: sp_adc = 36'd0;
        endcase
    end
    always @(*) begin
        case ({tb_idx, sb})
            8'd0: sp_gen = 36'h881108241;
            8'd1: sp_gen = 36'h883006244;
            8'd2: sp_gen = 36'h95c0419c0;
            8'd3: sp_gen = 36'h95c0829c0;
            8'd4: sp_gen = 36'h95c1049c0;
            8'd5: sp_gen = 36'h95c1c79c0;
            8'd6: sp_gen = 36'h95c0419c1;
            8'd7: sp_gen = 36'h95c1c49c1;
            8'd8: sp_gen = 36'h95c0809c2;
            8'd16: sp_gen = 36'h962042249;
            8'd17: sp_gen = 36'h882008102;
            8'd18: sp_gen = 36'h883185105;
            8'd19: sp_gen = 36'h95c0419c0;
            8'd20: sp_gen = 36'h95c0829c0;
            8'd21: sp_gen = 36'h95c2439c0;
            8'd22: sp_gen = 36'h95c1859c0;
            8'd23: sp_gen = 36'h95c0c79c0;
            8'd24: sp_gen = 36'h95c0409c1;
            8'd32: sp_gen = 36'h962006244;
            8'd33: sp_gen = 36'h881004081;
            8'd34: sp_gen = 36'h8822021c2;
            8'd35: sp_gen = 36'h883185105;
            8'd36: sp_gen = 36'h95c0419c0;
            8'd37: sp_gen = 36'h95c2419c0;
            8'd38: sp_gen = 36'h95c2029c0;
            8'd39: sp_gen = 36'h95c1c39c0;
            8'd40: sp_gen = 36'h95c0459c0;
            8'd48: sp_gen = 36'h962008102;
            8'd49: sp_gen = 36'h962000086;
            8'd50: sp_gen = 36'h8811060c1;
            8'd51: sp_gen = 36'h8822021c2;
            8'd52: sp_gen = 36'h883185105;
            8'd53: sp_gen = 36'h886087189;
            8'd54: sp_gen = 36'h95c1019c0;
            8'd55: sp_gen = 36'h95c2019c0;
            8'd56: sp_gen = 36'h95c1429c0;
            8'd64: sp_gen = 36'h962004081;
            8'd65: sp_gen = 36'h962000043;
            8'd66: sp_gen = 36'h962002206;
            8'd67: sp_gen = 36'h8811060c1;
            8'd68: sp_gen = 36'h8822021c2;
            8'd69: sp_gen = 36'h883183204;
            8'd70: sp_gen = 36'h884104246;
            8'd71: sp_gen = 36'h882106049;
            8'd72: sp_gen = 36'h95c0c19c0;
            8'd80: sp_gen = 36'h9658830c8;
            8'd81: sp_gen = 36'h9620c8002;
            8'd82: sp_gen = 36'h9620c8144;
            8'd83: sp_gen = 36'h9621c6049;
            8'd84: sp_gen = 36'h8830c3201;
            8'd85: sp_gen = 36'h880005083;
            8'd86: sp_gen = 36'h887186184;
            8'd87: sp_gen = 36'h883205046;
            8'd88: sp_gen = 36'h887049108;
            8'd96: sp_gen = 36'h9658830c8;
            8'd97: sp_gen = 36'h9620c8002;
            8'd98: sp_gen = 36'h9620c8144;
            8'd99: sp_gen = 36'h9621c6049;
            8'd100: sp_gen = 36'h8830c3201;
            8'd101: sp_gen = 36'h880005083;
            8'd102: sp_gen = 36'h887186184;
            8'd103: sp_gen = 36'h883205046;
            8'd104: sp_gen = 36'h887049108;
            8'd112: sp_gen = 36'h9658830c8;
            8'd113: sp_gen = 36'h9620c8002;
            8'd114: sp_gen = 36'h9620c8144;
            8'd115: sp_gen = 36'h9621c6049;
            8'd116: sp_gen = 36'h8830c3201;
            8'd117: sp_gen = 36'h880005083;
            8'd118: sp_gen = 36'h887186184;
            8'd119: sp_gen = 36'h883205046;
            8'd120: sp_gen = 36'h887049108;
            8'd128: sp_gen = 36'h9658830c8;
            8'd129: sp_gen = 36'h9620c8002;
            8'd130: sp_gen = 36'h9620c8144;
            8'd131: sp_gen = 36'h9621c6049;
            8'd132: sp_gen = 36'h8830c3201;
            8'd133: sp_gen = 36'h880005083;
            8'd134: sp_gen = 36'h887186184;
            8'd135: sp_gen = 36'h883205046;
            8'd136: sp_gen = 36'h887049108;
            8'd144: sp_gen = 36'h9658830c8;
            8'd145: sp_gen = 36'h9620c8002;
            8'd146: sp_gen = 36'h9620c8144;
            8'd147: sp_gen = 36'h9621c6049;
            8'd148: sp_gen = 36'h8830c3201;
            8'd149: sp_gen = 36'h880005083;
            8'd150: sp_gen = 36'h887186184;
            8'd151: sp_gen = 36'h883205046;
            8'd152: sp_gen = 36'h887049108;
            8'd160: sp_gen = 36'h9658830c8;
            8'd161: sp_gen = 36'h9620c8002;
            8'd162: sp_gen = 36'h9620c8144;
            8'd163: sp_gen = 36'h9621c6049;
            8'd164: sp_gen = 36'h8830c3201;
            8'd165: sp_gen = 36'h880005083;
            8'd166: sp_gen = 36'h887186184;
            8'd167: sp_gen = 36'h883205046;
            8'd168: sp_gen = 36'h887049108;
            8'd176: sp_gen = 36'h9658830c8;
            8'd177: sp_gen = 36'h9620c8002;
            8'd178: sp_gen = 36'h9620c8144;
            8'd179: sp_gen = 36'h9621c6049;
            8'd180: sp_gen = 36'h8830c3201;
            8'd181: sp_gen = 36'h880005083;
            8'd182: sp_gen = 36'h887186184;
            8'd183: sp_gen = 36'h883205046;
            8'd184: sp_gen = 36'h887049108;
            8'd192: sp_gen = 36'h9658830c8;
            8'd193: sp_gen = 36'h9620c8002;
            8'd194: sp_gen = 36'h9620c8144;
            8'd195: sp_gen = 36'h9621c6049;
            8'd196: sp_gen = 36'h8830c3201;
            8'd197: sp_gen = 36'h880005083;
            8'd198: sp_gen = 36'h887186184;
            8'd199: sp_gen = 36'h883205046;
            8'd200: sp_gen = 36'h887049108;
            8'd208: sp_gen = 36'h9658830c8;
            8'd209: sp_gen = 36'h9620c8002;
            8'd210: sp_gen = 36'h9620c8144;
            8'd211: sp_gen = 36'h9621c6049;
            8'd212: sp_gen = 36'h8830c3201;
            8'd213: sp_gen = 36'h880005083;
            8'd214: sp_gen = 36'h887186184;
            8'd215: sp_gen = 36'h883205046;
            8'd216: sp_gen = 36'h887049108;
            8'd224: sp_gen = 36'h9658830c8;
            8'd225: sp_gen = 36'h9620c8002;
            8'd226: sp_gen = 36'h9620c8144;
            8'd227: sp_gen = 36'h9621c6049;
            8'd228: sp_gen = 36'h8830c3201;
            8'd229: sp_gen = 36'h880005083;
            8'd230: sp_gen = 36'h887186184;
            8'd231: sp_gen = 36'h883205046;
            8'd232: sp_gen = 36'h887049108;
            8'd240: sp_gen = 36'h9658830c8;
            8'd241: sp_gen = 36'h9620c8002;
            8'd242: sp_gen = 36'h9620c8144;
            8'd243: sp_gen = 36'h9621c6049;
            8'd244: sp_gen = 36'h8830c3201;
            8'd245: sp_gen = 36'h880005083;
            8'd246: sp_gen = 36'h887186184;
            8'd247: sp_gen = 36'h883205046;
            8'd248: sp_gen = 36'h887049108;
            default: sp_gen = 36'd0;
        endcase
    end
    wire [35:0] sp_r = adc_mode ? sp_adc : sp_gen;

    // 整屏电压跨度（按增益索引查表）
    reg [29:0] vsp_r;
    always @(*) begin
        case (gsel)
            6'd0: vsp_r = 30'h257c4041;
            6'd1: vsp_r = 30'h257c0001;
            6'd2: vsp_r = 30'h2595f009;
            6'd3: vsp_r = 30'h2595f247;
            6'd4: vsp_r = 30'h2595f007;
            6'd5: vsp_r = 30'h2595f0c6;
            6'd6: vsp_r = 30'h2595f185;
            6'd7: vsp_r = 30'h2595f005;
            6'd8: vsp_r = 30'h2595f104;
            6'd9: vsp_r = 30'h2595f243;
            6'd10: vsp_r = 30'h2595f143;
            6'd11: vsp_r = 30'h2595f043;
            6'd12: vsp_r = 30'h2595f202;
            6'd13: vsp_r = 30'h2595f102;
            6'd14: vsp_r = 30'h2595f082;
            6'd15: vsp_r = 30'h2595f241;
            6'd16: vsp_r = 30'h2595f1c1;
            6'd17: vsp_r = 30'h2595f141;
            6'd18: vsp_r = 30'h2595f101;
            6'd19: vsp_r = 30'h2595f081;
            6'd20: vsp_r = 30'h2595f041;
            6'd21: vsp_r = 30'h1f0859c9;
            6'd22: vsp_r = 30'h1f1c49c8;
            6'd23: vsp_r = 30'h1f0859c7;
            6'd24: vsp_r = 30'h1f2469c6;
            6'd25: vsp_r = 30'h1f1499c5;
            6'd26: vsp_r = 30'h1f2029c5;
            6'd27: vsp_r = 30'h1f0079c4;
            6'd28: vsp_r = 30'h1f2019c4;
            6'd29: vsp_r = 30'h1f0479c3;
            6'd30: vsp_r = 30'h1f0039c3;
            6'd31: vsp_r = 30'h1f0c99c2;
            6'd32: vsp_r = 30'h1f0469c2;
            6'd33: vsp_r = 30'h1f0839c2;
            6'd34: vsp_r = 30'h1f1809c2;
            6'd35: vsp_r = 30'h1f0c89c1;
            6'd36: vsp_r = 30'h1f0c69c1;
            6'd37: vsp_r = 30'h1f1449c1;
            6'd38: vsp_r = 30'h1f2429c1;
            6'd39: vsp_r = 30'h1f1019c1;
            6'd40: vsp_r = 30'h1f0809c1;
            6'd41: vsp_r = 30'h1f0099c0;
            6'd42: vsp_r = 30'h1f0089c0;
            6'd43: vsp_r = 30'h1f0479c0;
            6'd44: vsp_r = 30'h1f0c69c0;
            6'd45: vsp_r = 30'h1f1859c0;
            6'd46: vsp_r = 30'h1f0059c0;
            6'd47: vsp_r = 30'h1f1449c0;
            6'd48: vsp_r = 30'h1f0049c0;
            6'd49: vsp_r = 30'h1f1439c0;
            6'd50: vsp_r = 30'h1f0439c0;
            6'd51: vsp_r = 30'h1f2029c0;
            6'd52: vsp_r = 30'h1f1429c0;
            6'd53: vsp_r = 30'h1f0829c0;
            6'd54: vsp_r = 30'h1f0029c0;
            6'd55: vsp_r = 30'h1f1c19c0;
            6'd56: vsp_r = 30'h1f1419c0;
            6'd57: vsp_r = 30'h1f1019c0;
            6'd58: vsp_r = 30'h1f0819c0;
            6'd59: vsp_r = 30'h1f0419c0;
            6'd60: vsp_r = 30'h1f0019c0;
            default: vsp_r = 30'h0;
        endcase
    end

    // 数值拆分
    wire [9:0]  ax  = x10[9] ? (10'd0 - x10) : x10;
    wire [9:0]  ay  = y10[9] ? (10'd0 - y10) : y10;
    wire [15:0] axm = ax * 16'd205;
    wire [15:0] aym = ay * 16'd205;
    wire [5:0]  xip = axm[15:11];
    wire [5:0]  yip = aym[15:11];
    wire [9:0]  xfr = ax - ({4'b0000, xip} * 10'd10);
    wire [9:0]  yfr = ay - ({4'b0000, yip} * 10'd10);
    wire        xt  = (xip >= 6'd10);
    wire [1:0]  xtn = (xip >= 6'd30) ? 2'd3 : ((xip >= 6'd20) ? 2'd2 : 2'd1);
    wire [5:0]  xo  = xt ? (xip - ({4'b0000, xtn} * 6'd10)) : xip;

    wire [2:0] xlen = (ax == 10'd0) ? 3'd3 : (xt ? 3'd5 : 3'd4);
    wire [2:0] ylen = (ay == 10'd0) ? 3'd3 : 3'd4;
    wire [5:0] yp   = 6'd2 + {3'b000, xlen} + 6'd1;
    wire [5:0] yb0  = yp + 6'd2;
    wire [5:0] tp   = yb0 + {3'b000, ylen} + 6'd1;
    wire [5:0] vp   = tp + 6'd9;

    localparam integer NCOL = 32;
    wire [11:0] dx = px - X0;
    wire [11:0] dy = py - Y0;
    wire in_x = (px >= X0) && (px < (X0 + 8 * NCOL));
    wire in_y = (py >= Y0) && (py < (Y0 + 8));
    wire [5:0] cidx = dx[8:3];
    wire [2:0] bx   = dx[2:0];
    wire [2:0] grow = dy[2:0];

    reg [5:0] spc;
    always @(*) begin
        case (cidx - tp - 6'd2)
            6'd0: spc = sp_r[5:0];
            6'd1: spc = sp_r[11:6];
            6'd2: spc = sp_r[17:12];
            6'd3: spc = sp_r[23:18];
            6'd4: spc = sp_r[29:24];
            6'd5: spc = sp_r[35:30];
            default: spc = 6'd37;
        endcase
    end

    reg [5:0] vch;
    always @(*) begin
        case (cidx - vp - 6'd2)
            6'd0: vch = vsp_r[5:0];
            6'd1: vch = vsp_r[11:6];
            6'd2: vch = vsp_r[17:12];
            6'd3: vch = vsp_r[23:18];
            6'd4: vch = vsp_r[29:24];
            default: vch = 6'd37;
        endcase
    end

    wire [4:0] xr = cidx[4:0] - 5'd2;
    reg  [5:0] xch;
    always @(*) begin
        if (ax == 10'd0) begin
            case (xr)
                5'd0: xch = 6'd0;
                5'd1: xch = 6'd39;
                5'd2: xch = {2'b00, xfr[3:0]};
                default: xch = 6'd37;
            endcase
        end
        else if (!xt) begin
            case (xr)
                5'd0: xch = x10[9] ? 6'd40 : 6'd41;
                5'd1: xch = {2'b00, xo[3:0]};
                5'd2: xch = 6'd39;
                5'd3: xch = {2'b00, xfr[3:0]};
                default: xch = 6'd37;
            endcase
        end
        else begin
            case (xr)
                5'd0: xch = x10[9] ? 6'd40 : 6'd41;
                5'd1: xch = {4'b0000, xtn};
                5'd2: xch = {2'b00, xo[3:0]};
                5'd3: xch = 6'd39;
                5'd4: xch = {2'b00, xfr[3:0]};
                default: xch = 6'd37;
            endcase
        end
    end

    wire [4:0] yr = cidx[4:0] - yb0[4:0];
    reg  [5:0] ych;
    always @(*) begin
        if (ay == 10'd0) begin
            case (yr)
                5'd0: ych = 6'd0;
                5'd1: ych = 6'd39;
                5'd2: ych = {2'b00, yfr[3:0]};
                default: ych = 6'd37;
            endcase
        end
        else begin
            case (yr)
                5'd0: ych = y10[9] ? 6'd40 : 6'd41;
                5'd1: ych = {2'b00, yip[3:0]};
                5'd2: ych = 6'd39;
                5'd3: ych = {2'b00, yfr[3:0]};
                default: ych = 6'd37;
            endcase
        end
    end

    reg [5:0] ch;
    always @(*) begin
        ch = 6'd37;
        if (cidx == 6'd0)                      ch = 6'd33;
        else if (cidx == 6'd1)                 ch = 6'd38;
        else if (cidx < 6'd2 + {3'b000, xlen}) ch = xch;
        else if (cidx == yp)                   ch = 6'd34;
        else if (cidx == yp + 6'd1)            ch = 6'd38;
        else if (cidx < yb0 + {3'b000, ylen})  ch = ych;
        else if (cidx == tp)                   ch = 6'd29;
        else if (cidx == tp + 6'd1)            ch = 6'd36;
        else if (cidx < tp + 6'd8)             ch = spc;
        else if (cidx == vp)                   ch = 6'd31;
        else if (cidx == vp + 6'd1)            ch = 6'd36;
        else if (cidx < vp + 6'd7)             ch = vch;
    end

    wire [7:0] bits;
    font_rom u_font (.ch(ch), .row(grow), .bits(bits));

    assign hit   = de && in_x && in_y && bits[3'd7 - bx];
    assign color = COL;

endmodule
