//==============================================================================
// 层: 应用(信号源)  文件: app/func_gen.v
// 功能: 内置函数发生器 —— ADC 未接入时给示波器提供可调测试信号
//   波形: 0=正弦 1=方波 2=三角波 3=锯齿波
//   频率: 8 档（1/5/10/50/100/500/1k/2k Hz），采样率固定 FS_HZ
//   幅度: 4 档（100/50/25/12.5%），中心 512，满幅约 ±400（与 adc_norm 输出范围一致）
// 输出: data[9:0] + 单周期 valid，语义与 adc_valid 完全一致
//==============================================================================
`timescale 1ns / 1ps

module func_gen #(
    parameter integer CLK_HZ = 24_000_000,
    parameter integer FS_HZ  = 12_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] wave,       // 波形选择
    input  wire [2:0] freq_sel,   // 频率档位
    input  wire [1:0] amp_sel,    // 幅度档位
    input  wire [3:0] phase_idx,  // 相位档 0..9，每档 36 度
    output reg  [9:0] data,
    output reg        valid
);

    localparam integer DIV = CLK_HZ / FS_HZ;

    //------------------------------------------------------------------
    // 频率表: INC = f / FS * 2^24
    //------------------------------------------------------------------
    reg [23:0] inc;
    always @(*) begin
        case (freq_sel)
            3'd0: inc = 24'd1398;      // 1 Hz
            3'd1: inc = 24'd6991;      // 5 Hz
            3'd2: inc = 24'd13981;     // 10 Hz
            3'd3: inc = 24'd69905;     // 50 Hz
            3'd4: inc = 24'd139810;    // 100 Hz
            3'd5: inc = 24'd699051;    // 500 Hz
            3'd6: inc = 24'd1398101;   // 1 kHz
            default: inc = 24'd2796203; // 2 kHz
        endcase
    end

    reg [15:0] cnt;
    reg [23:0] phase;
    // 相位偏移：idx * (2^24 / 10)，0..9 档对应 0..324 度
    wire [23:0] phase_off = {20'd0, phase_idx} * 24'd1677722;
    wire [23:0] ph = phase + phase_off;
    wire [7:0] idx = ph[23:16];

    //------------------------------------------------------------------
    // 256 点正弦表（中心 512，幅度 400）
    //------------------------------------------------------------------
    reg [9:0] sine;
    always @(*) begin
        case (idx)
        8'd0   : sine = 10'd512;
        8'd1   : sine = 10'd522;
        8'd2   : sine = 10'd532;
        8'd3   : sine = 10'd541;
        8'd4   : sine = 10'd551;
        8'd5   : sine = 10'd561;
        8'd6   : sine = 10'd571;
        8'd7   : sine = 10'd580;
        8'd8   : sine = 10'd590;
        8'd9   : sine = 10'd600;
        8'd10  : sine = 10'd609;
        8'd11  : sine = 10'd619;
        8'd12  : sine = 10'd628;
        8'd13  : sine = 10'd637;
        8'd14  : sine = 10'd647;
        8'd15  : sine = 10'd656;
        8'd16  : sine = 10'd665;
        8'd17  : sine = 10'd674;
        8'd18  : sine = 10'd683;
        8'd19  : sine = 10'd692;
        8'd20  : sine = 10'd701;
        8'd21  : sine = 10'd709;
        8'd22  : sine = 10'd718;
        8'd23  : sine = 10'd726;
        8'd24  : sine = 10'd734;
        8'd25  : sine = 10'd742;
        8'd26  : sine = 10'd750;
        8'd27  : sine = 10'd758;
        8'd28  : sine = 10'd766;
        8'd29  : sine = 10'd773;
        8'd30  : sine = 10'd781;
        8'd31  : sine = 10'd788;
        8'd32  : sine = 10'd795;
        8'd33  : sine = 10'd802;
        8'd34  : sine = 10'd808;
        8'd35  : sine = 10'd815;
        8'd36  : sine = 10'd821;
        8'd37  : sine = 10'd827;
        8'd38  : sine = 10'd833;
        8'd39  : sine = 10'd839;
        8'd40  : sine = 10'd845;
        8'd41  : sine = 10'd850;
        8'd42  : sine = 10'd855;
        8'd43  : sine = 10'd860;
        8'd44  : sine = 10'd865;
        8'd45  : sine = 10'd869;
        8'd46  : sine = 10'd874;
        8'd47  : sine = 10'd878;
        8'd48  : sine = 10'd882;
        8'd49  : sine = 10'd885;
        8'd50  : sine = 10'd889;
        8'd51  : sine = 10'd892;
        8'd52  : sine = 10'd895;
        8'd53  : sine = 10'd898;
        8'd54  : sine = 10'd900;
        8'd55  : sine = 10'd902;
        8'd56  : sine = 10'd904;
        8'd57  : sine = 10'd906;
        8'd58  : sine = 10'd908;
        8'd59  : sine = 10'd909;
        8'd60  : sine = 10'd910;
        8'd61  : sine = 10'd911;
        8'd62  : sine = 10'd912;
        8'd63  : sine = 10'd912;
        8'd64  : sine = 10'd912;
        8'd65  : sine = 10'd912;
        8'd66  : sine = 10'd912;
        8'd67  : sine = 10'd911;
        8'd68  : sine = 10'd910;
        8'd69  : sine = 10'd909;
        8'd70  : sine = 10'd908;
        8'd71  : sine = 10'd906;
        8'd72  : sine = 10'd904;
        8'd73  : sine = 10'd902;
        8'd74  : sine = 10'd900;
        8'd75  : sine = 10'd898;
        8'd76  : sine = 10'd895;
        8'd77  : sine = 10'd892;
        8'd78  : sine = 10'd889;
        8'd79  : sine = 10'd885;
        8'd80  : sine = 10'd882;
        8'd81  : sine = 10'd878;
        8'd82  : sine = 10'd874;
        8'd83  : sine = 10'd869;
        8'd84  : sine = 10'd865;
        8'd85  : sine = 10'd860;
        8'd86  : sine = 10'd855;
        8'd87  : sine = 10'd850;
        8'd88  : sine = 10'd845;
        8'd89  : sine = 10'd839;
        8'd90  : sine = 10'd833;
        8'd91  : sine = 10'd827;
        8'd92  : sine = 10'd821;
        8'd93  : sine = 10'd815;
        8'd94  : sine = 10'd808;
        8'd95  : sine = 10'd802;
        8'd96  : sine = 10'd795;
        8'd97  : sine = 10'd788;
        8'd98  : sine = 10'd781;
        8'd99  : sine = 10'd773;
        8'd100 : sine = 10'd766;
        8'd101 : sine = 10'd758;
        8'd102 : sine = 10'd750;
        8'd103 : sine = 10'd742;
        8'd104 : sine = 10'd734;
        8'd105 : sine = 10'd726;
        8'd106 : sine = 10'd718;
        8'd107 : sine = 10'd709;
        8'd108 : sine = 10'd701;
        8'd109 : sine = 10'd692;
        8'd110 : sine = 10'd683;
        8'd111 : sine = 10'd674;
        8'd112 : sine = 10'd665;
        8'd113 : sine = 10'd656;
        8'd114 : sine = 10'd647;
        8'd115 : sine = 10'd637;
        8'd116 : sine = 10'd628;
        8'd117 : sine = 10'd619;
        8'd118 : sine = 10'd609;
        8'd119 : sine = 10'd600;
        8'd120 : sine = 10'd590;
        8'd121 : sine = 10'd580;
        8'd122 : sine = 10'd571;
        8'd123 : sine = 10'd561;
        8'd124 : sine = 10'd551;
        8'd125 : sine = 10'd541;
        8'd126 : sine = 10'd532;
        8'd127 : sine = 10'd522;
        8'd128 : sine = 10'd512;
        8'd129 : sine = 10'd502;
        8'd130 : sine = 10'd492;
        8'd131 : sine = 10'd483;
        8'd132 : sine = 10'd473;
        8'd133 : sine = 10'd463;
        8'd134 : sine = 10'd453;
        8'd135 : sine = 10'd444;
        8'd136 : sine = 10'd434;
        8'd137 : sine = 10'd424;
        8'd138 : sine = 10'd415;
        8'd139 : sine = 10'd405;
        8'd140 : sine = 10'd396;
        8'd141 : sine = 10'd387;
        8'd142 : sine = 10'd377;
        8'd143 : sine = 10'd368;
        8'd144 : sine = 10'd359;
        8'd145 : sine = 10'd350;
        8'd146 : sine = 10'd341;
        8'd147 : sine = 10'd332;
        8'd148 : sine = 10'd323;
        8'd149 : sine = 10'd315;
        8'd150 : sine = 10'd306;
        8'd151 : sine = 10'd298;
        8'd152 : sine = 10'd290;
        8'd153 : sine = 10'd282;
        8'd154 : sine = 10'd274;
        8'd155 : sine = 10'd266;
        8'd156 : sine = 10'd258;
        8'd157 : sine = 10'd251;
        8'd158 : sine = 10'd243;
        8'd159 : sine = 10'd236;
        8'd160 : sine = 10'd229;
        8'd161 : sine = 10'd222;
        8'd162 : sine = 10'd216;
        8'd163 : sine = 10'd209;
        8'd164 : sine = 10'd203;
        8'd165 : sine = 10'd197;
        8'd166 : sine = 10'd191;
        8'd167 : sine = 10'd185;
        8'd168 : sine = 10'd179;
        8'd169 : sine = 10'd174;
        8'd170 : sine = 10'd169;
        8'd171 : sine = 10'd164;
        8'd172 : sine = 10'd159;
        8'd173 : sine = 10'd155;
        8'd174 : sine = 10'd150;
        8'd175 : sine = 10'd146;
        8'd176 : sine = 10'd142;
        8'd177 : sine = 10'd139;
        8'd178 : sine = 10'd135;
        8'd179 : sine = 10'd132;
        8'd180 : sine = 10'd129;
        8'd181 : sine = 10'd126;
        8'd182 : sine = 10'd124;
        8'd183 : sine = 10'd122;
        8'd184 : sine = 10'd120;
        8'd185 : sine = 10'd118;
        8'd186 : sine = 10'd116;
        8'd187 : sine = 10'd115;
        8'd188 : sine = 10'd114;
        8'd189 : sine = 10'd113;
        8'd190 : sine = 10'd112;
        8'd191 : sine = 10'd112;
        8'd192 : sine = 10'd112;
        8'd193 : sine = 10'd112;
        8'd194 : sine = 10'd112;
        8'd195 : sine = 10'd113;
        8'd196 : sine = 10'd114;
        8'd197 : sine = 10'd115;
        8'd198 : sine = 10'd116;
        8'd199 : sine = 10'd118;
        8'd200 : sine = 10'd120;
        8'd201 : sine = 10'd122;
        8'd202 : sine = 10'd124;
        8'd203 : sine = 10'd126;
        8'd204 : sine = 10'd129;
        8'd205 : sine = 10'd132;
        8'd206 : sine = 10'd135;
        8'd207 : sine = 10'd139;
        8'd208 : sine = 10'd142;
        8'd209 : sine = 10'd146;
        8'd210 : sine = 10'd150;
        8'd211 : sine = 10'd155;
        8'd212 : sine = 10'd159;
        8'd213 : sine = 10'd164;
        8'd214 : sine = 10'd169;
        8'd215 : sine = 10'd174;
        8'd216 : sine = 10'd179;
        8'd217 : sine = 10'd185;
        8'd218 : sine = 10'd191;
        8'd219 : sine = 10'd197;
        8'd220 : sine = 10'd203;
        8'd221 : sine = 10'd209;
        8'd222 : sine = 10'd216;
        8'd223 : sine = 10'd222;
        8'd224 : sine = 10'd229;
        8'd225 : sine = 10'd236;
        8'd226 : sine = 10'd243;
        8'd227 : sine = 10'd251;
        8'd228 : sine = 10'd258;
        8'd229 : sine = 10'd266;
        8'd230 : sine = 10'd274;
        8'd231 : sine = 10'd282;
        8'd232 : sine = 10'd290;
        8'd233 : sine = 10'd298;
        8'd234 : sine = 10'd306;
        8'd235 : sine = 10'd315;
        8'd236 : sine = 10'd323;
        8'd237 : sine = 10'd332;
        8'd238 : sine = 10'd341;
        8'd239 : sine = 10'd350;
        8'd240 : sine = 10'd359;
        8'd241 : sine = 10'd368;
        8'd242 : sine = 10'd377;
        8'd243 : sine = 10'd387;
        8'd244 : sine = 10'd396;
        8'd245 : sine = 10'd405;
        8'd246 : sine = 10'd415;
        8'd247 : sine = 10'd424;
        8'd248 : sine = 10'd434;
        8'd249 : sine = 10'd444;
        8'd250 : sine = 10'd453;
        8'd251 : sine = 10'd463;
        8'd252 : sine = 10'd473;
        8'd253 : sine = 10'd483;
        8'd254 : sine = 10'd492;
        8'd255 : sine = 10'd502;
        default: sine = 10'd512;
        endcase
    end

    //------------------------------------------------------------------
    // 各波形统一映射到 "中心 512 / 幅度约 ±400"
    //------------------------------------------------------------------
    // 三角：前半周期 0->1023，后半周期 1023->0（一个完整周期 = 一个三角）
    wire [10:0] tri_u = ph[23] ? (11'd1023 - {1'b0, ph[22:13]})
                                  :  {1'b0, ph[22:13]};
    wire signed [11:0] tri_raw = $signed({1'b0, tri_u}) - 12'sd512;
    // 锯齿：取相位最高 10 位，一个完整周期内 0->1023 单调上升
    wire signed [11:0] saw_raw = $signed({1'b0, ph[23:14]}) - 12'sd512;

    // 统一缩放到 ±400（与正弦/adc_norm 量程一致）
    // 注意：Verilog 乘法结果宽度 = 两个操作数宽度的最大值，12bit x 25 会溢出。
    //       这里把常量写成 18 位，乘积就有 18 位，再右移 5 位得到 ±400。
    wire signed [17:0] tri_m = tri_raw * 18'sd25;
    wire signed [17:0] saw_m = saw_raw * 18'sd25;
    wire signed [12:0] tri_s = 13'sd512 + (tri_m >>> 5);
    wire signed [12:0] saw_s = 13'sd512 + (saw_m >>> 5);

    reg [9:0] wave_val;
    always @(*) begin
        case (wave)
            2'd0: wave_val = sine;
            2'd1: wave_val = ph[23] ? 10'd112 : 10'd912;          // 方波 ±400
            2'd2: wave_val = tri_s[9:0];                              // 三角 ±~400
            default: wave_val = saw_s[9:0];                           // 锯齿 ±~400
        endcase
    end

    // 幅度缩放: 0=1x 1=1/2 2=1/4 3=1/8
    wire signed [11:0] delta    = $signed({2'b00, wave_val}) - 12'sd512;
    wire signed [11:0] delta_s  = delta >>> amp_sel;   // 算术右移，amp_sel=0..3
    wire [9:0] scaled = 10'd512 + delta_s[9:0];

    always @(posedge clk) begin
        if (rst) begin
            cnt   <= 16'd0;
            phase <= 24'd0;
            data  <= 10'd512;
            valid <= 1'b0;
        end
        else begin
            valid <= 1'b0;
            if (cnt == DIV - 1) begin
                cnt   <= 16'd0;
                phase <= phase + inc;
                data  <= scaled;
                valid <= 1'b1;
            end
            else begin
                cnt <= cnt + 16'd1;
            end
        end
    end

endmodule