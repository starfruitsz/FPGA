//==============================================================================
// 层: 应用(测试信号)  文件: app/sine_50hz.v
// 功能: 内部 50Hz 正弦信号源（DDS），用于**不接 ADC 时演示示波器**
//   - 采样率 FS_HZ（默认 12kHz），相位累加器 24bit，256 点正弦表
//   - 每 DIV 个时钟产生一个采样点并给出单周期 valid，与 adc_valid 语义一致
//   - 输出 10bit 无符号、中心 512、幅度约 400（与 adc_norm 的输出范围一致）
// 说明: 仅用于演示/自检，不参与实际采集；由顶层参数 DEMO_SINE 选择。
//==============================================================================
`timescale 1ns / 1ps

module sine_50hz #(
    parameter integer CLK_HZ  = 24_000_000,
    parameter integer FS_HZ   = 12_000,
    parameter integer FREQ_HZ = 50
)(
    input  wire       clk,
    input  wire       rst,
    output reg  [9:0] data,
    output reg        valid
);

    localparam integer DIV = CLK_HZ / FS_HZ;                  // 2000
    localparam integer INC = ((FREQ_HZ << 24) / FS_HZ);        // 69905

    reg [15:0] cnt;
    reg [23:0] phase;

    wire [7:0] idx = phase[23:16];

    reg [9:0] dout;
    always @(*) begin
        case (idx)
        8'd0   : dout = 10'd512;
        8'd1   : dout = 10'd522;
        8'd2   : dout = 10'd532;
        8'd3   : dout = 10'd541;
        8'd4   : dout = 10'd551;
        8'd5   : dout = 10'd561;
        8'd6   : dout = 10'd571;
        8'd7   : dout = 10'd580;
        8'd8   : dout = 10'd590;
        8'd9   : dout = 10'd600;
        8'd10  : dout = 10'd609;
        8'd11  : dout = 10'd619;
        8'd12  : dout = 10'd628;
        8'd13  : dout = 10'd637;
        8'd14  : dout = 10'd647;
        8'd15  : dout = 10'd656;
        8'd16  : dout = 10'd665;
        8'd17  : dout = 10'd674;
        8'd18  : dout = 10'd683;
        8'd19  : dout = 10'd692;
        8'd20  : dout = 10'd701;
        8'd21  : dout = 10'd709;
        8'd22  : dout = 10'd718;
        8'd23  : dout = 10'd726;
        8'd24  : dout = 10'd734;
        8'd25  : dout = 10'd742;
        8'd26  : dout = 10'd750;
        8'd27  : dout = 10'd758;
        8'd28  : dout = 10'd766;
        8'd29  : dout = 10'd773;
        8'd30  : dout = 10'd781;
        8'd31  : dout = 10'd788;
        8'd32  : dout = 10'd795;
        8'd33  : dout = 10'd802;
        8'd34  : dout = 10'd808;
        8'd35  : dout = 10'd815;
        8'd36  : dout = 10'd821;
        8'd37  : dout = 10'd827;
        8'd38  : dout = 10'd833;
        8'd39  : dout = 10'd839;
        8'd40  : dout = 10'd845;
        8'd41  : dout = 10'd850;
        8'd42  : dout = 10'd855;
        8'd43  : dout = 10'd860;
        8'd44  : dout = 10'd865;
        8'd45  : dout = 10'd869;
        8'd46  : dout = 10'd874;
        8'd47  : dout = 10'd878;
        8'd48  : dout = 10'd882;
        8'd49  : dout = 10'd885;
        8'd50  : dout = 10'd889;
        8'd51  : dout = 10'd892;
        8'd52  : dout = 10'd895;
        8'd53  : dout = 10'd898;
        8'd54  : dout = 10'd900;
        8'd55  : dout = 10'd902;
        8'd56  : dout = 10'd904;
        8'd57  : dout = 10'd906;
        8'd58  : dout = 10'd908;
        8'd59  : dout = 10'd909;
        8'd60  : dout = 10'd910;
        8'd61  : dout = 10'd911;
        8'd62  : dout = 10'd912;
        8'd63  : dout = 10'd912;
        8'd64  : dout = 10'd912;
        8'd65  : dout = 10'd912;
        8'd66  : dout = 10'd912;
        8'd67  : dout = 10'd911;
        8'd68  : dout = 10'd910;
        8'd69  : dout = 10'd909;
        8'd70  : dout = 10'd908;
        8'd71  : dout = 10'd906;
        8'd72  : dout = 10'd904;
        8'd73  : dout = 10'd902;
        8'd74  : dout = 10'd900;
        8'd75  : dout = 10'd898;
        8'd76  : dout = 10'd895;
        8'd77  : dout = 10'd892;
        8'd78  : dout = 10'd889;
        8'd79  : dout = 10'd885;
        8'd80  : dout = 10'd882;
        8'd81  : dout = 10'd878;
        8'd82  : dout = 10'd874;
        8'd83  : dout = 10'd869;
        8'd84  : dout = 10'd865;
        8'd85  : dout = 10'd860;
        8'd86  : dout = 10'd855;
        8'd87  : dout = 10'd850;
        8'd88  : dout = 10'd845;
        8'd89  : dout = 10'd839;
        8'd90  : dout = 10'd833;
        8'd91  : dout = 10'd827;
        8'd92  : dout = 10'd821;
        8'd93  : dout = 10'd815;
        8'd94  : dout = 10'd808;
        8'd95  : dout = 10'd802;
        8'd96  : dout = 10'd795;
        8'd97  : dout = 10'd788;
        8'd98  : dout = 10'd781;
        8'd99  : dout = 10'd773;
        8'd100 : dout = 10'd766;
        8'd101 : dout = 10'd758;
        8'd102 : dout = 10'd750;
        8'd103 : dout = 10'd742;
        8'd104 : dout = 10'd734;
        8'd105 : dout = 10'd726;
        8'd106 : dout = 10'd718;
        8'd107 : dout = 10'd709;
        8'd108 : dout = 10'd701;
        8'd109 : dout = 10'd692;
        8'd110 : dout = 10'd683;
        8'd111 : dout = 10'd674;
        8'd112 : dout = 10'd665;
        8'd113 : dout = 10'd656;
        8'd114 : dout = 10'd647;
        8'd115 : dout = 10'd637;
        8'd116 : dout = 10'd628;
        8'd117 : dout = 10'd619;
        8'd118 : dout = 10'd609;
        8'd119 : dout = 10'd600;
        8'd120 : dout = 10'd590;
        8'd121 : dout = 10'd580;
        8'd122 : dout = 10'd571;
        8'd123 : dout = 10'd561;
        8'd124 : dout = 10'd551;
        8'd125 : dout = 10'd541;
        8'd126 : dout = 10'd532;
        8'd127 : dout = 10'd522;
        8'd128 : dout = 10'd512;
        8'd129 : dout = 10'd502;
        8'd130 : dout = 10'd492;
        8'd131 : dout = 10'd483;
        8'd132 : dout = 10'd473;
        8'd133 : dout = 10'd463;
        8'd134 : dout = 10'd453;
        8'd135 : dout = 10'd444;
        8'd136 : dout = 10'd434;
        8'd137 : dout = 10'd424;
        8'd138 : dout = 10'd415;
        8'd139 : dout = 10'd405;
        8'd140 : dout = 10'd396;
        8'd141 : dout = 10'd387;
        8'd142 : dout = 10'd377;
        8'd143 : dout = 10'd368;
        8'd144 : dout = 10'd359;
        8'd145 : dout = 10'd350;
        8'd146 : dout = 10'd341;
        8'd147 : dout = 10'd332;
        8'd148 : dout = 10'd323;
        8'd149 : dout = 10'd315;
        8'd150 : dout = 10'd306;
        8'd151 : dout = 10'd298;
        8'd152 : dout = 10'd290;
        8'd153 : dout = 10'd282;
        8'd154 : dout = 10'd274;
        8'd155 : dout = 10'd266;
        8'd156 : dout = 10'd258;
        8'd157 : dout = 10'd251;
        8'd158 : dout = 10'd243;
        8'd159 : dout = 10'd236;
        8'd160 : dout = 10'd229;
        8'd161 : dout = 10'd222;
        8'd162 : dout = 10'd216;
        8'd163 : dout = 10'd209;
        8'd164 : dout = 10'd203;
        8'd165 : dout = 10'd197;
        8'd166 : dout = 10'd191;
        8'd167 : dout = 10'd185;
        8'd168 : dout = 10'd179;
        8'd169 : dout = 10'd174;
        8'd170 : dout = 10'd169;
        8'd171 : dout = 10'd164;
        8'd172 : dout = 10'd159;
        8'd173 : dout = 10'd155;
        8'd174 : dout = 10'd150;
        8'd175 : dout = 10'd146;
        8'd176 : dout = 10'd142;
        8'd177 : dout = 10'd139;
        8'd178 : dout = 10'd135;
        8'd179 : dout = 10'd132;
        8'd180 : dout = 10'd129;
        8'd181 : dout = 10'd126;
        8'd182 : dout = 10'd124;
        8'd183 : dout = 10'd122;
        8'd184 : dout = 10'd120;
        8'd185 : dout = 10'd118;
        8'd186 : dout = 10'd116;
        8'd187 : dout = 10'd115;
        8'd188 : dout = 10'd114;
        8'd189 : dout = 10'd113;
        8'd190 : dout = 10'd112;
        8'd191 : dout = 10'd112;
        8'd192 : dout = 10'd112;
        8'd193 : dout = 10'd112;
        8'd194 : dout = 10'd112;
        8'd195 : dout = 10'd113;
        8'd196 : dout = 10'd114;
        8'd197 : dout = 10'd115;
        8'd198 : dout = 10'd116;
        8'd199 : dout = 10'd118;
        8'd200 : dout = 10'd120;
        8'd201 : dout = 10'd122;
        8'd202 : dout = 10'd124;
        8'd203 : dout = 10'd126;
        8'd204 : dout = 10'd129;
        8'd205 : dout = 10'd132;
        8'd206 : dout = 10'd135;
        8'd207 : dout = 10'd139;
        8'd208 : dout = 10'd142;
        8'd209 : dout = 10'd146;
        8'd210 : dout = 10'd150;
        8'd211 : dout = 10'd155;
        8'd212 : dout = 10'd159;
        8'd213 : dout = 10'd164;
        8'd214 : dout = 10'd169;
        8'd215 : dout = 10'd174;
        8'd216 : dout = 10'd179;
        8'd217 : dout = 10'd185;
        8'd218 : dout = 10'd191;
        8'd219 : dout = 10'd197;
        8'd220 : dout = 10'd203;
        8'd221 : dout = 10'd209;
        8'd222 : dout = 10'd216;
        8'd223 : dout = 10'd222;
        8'd224 : dout = 10'd229;
        8'd225 : dout = 10'd236;
        8'd226 : dout = 10'd243;
        8'd227 : dout = 10'd251;
        8'd228 : dout = 10'd258;
        8'd229 : dout = 10'd266;
        8'd230 : dout = 10'd274;
        8'd231 : dout = 10'd282;
        8'd232 : dout = 10'd290;
        8'd233 : dout = 10'd298;
        8'd234 : dout = 10'd306;
        8'd235 : dout = 10'd315;
        8'd236 : dout = 10'd323;
        8'd237 : dout = 10'd332;
        8'd238 : dout = 10'd341;
        8'd239 : dout = 10'd350;
        8'd240 : dout = 10'd359;
        8'd241 : dout = 10'd368;
        8'd242 : dout = 10'd377;
        8'd243 : dout = 10'd387;
        8'd244 : dout = 10'd396;
        8'd245 : dout = 10'd405;
        8'd246 : dout = 10'd415;
        8'd247 : dout = 10'd424;
        8'd248 : dout = 10'd434;
        8'd249 : dout = 10'd444;
        8'd250 : dout = 10'd453;
        8'd251 : dout = 10'd463;
        8'd252 : dout = 10'd473;
        8'd253 : dout = 10'd483;
        8'd254 : dout = 10'd492;
        8'd255 : dout = 10'd502;
        default : dout = 10'd512;
        endcase
    end

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
                phase <= phase + INC[23:0];
                data  <= dout;          // 与 valid 同拍更新，采样侧下一拍取到
                valid <= 1'b1;
            end
            else begin
                cnt <= cnt + 16'd1;
            end
        end
    end

endmodule
