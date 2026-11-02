//==============================================================================
// 层: 应用(显示)  文件: app/bpf50.v   （文件名沿用，内容已换成卡尔曼滤波）
// 功能: 显示平滑滤波 —— 稳态（常增益）卡尔曼滤波，按采样率自适应增益
//
//   为什么换：原来的 50Hz 状态变量带通在谐振时状态会大幅摆动（Q=5 时幅值是
//   输入的 5 倍），定点下容易溢出/发散的观感，用户实测“滤波一开波形就变形”。
//   现改成**一阶稳态卡尔曼**：模型认为信号近似常量 + 白噪声，
//       预测:  x' = x
//       增益:  K  = P/(P+R)   （稳态时常数，预先算好）
//       更新:  x  = x + K*(z - x)
//   这就是卡尔曼滤波在“常量模型”下的稳态解，等价于一阶 IIR 低通，
//   **永远稳定、无谐振、无过冲**。
//
//   增益 K 按 {adc_mode, tb_idx} 查表：等效截止频率恒为 150Hz。
//     50Hz 处 |H| = 1/sqrt(1+(50/150)^2) = 0.95，基本不衰减；
//     高频噪声被压制（采样率越高压制越强），所以低频正弦看起来平滑。
//
//   定点：状态 Q8（24bit），K 为 Q16；x += (K*(z-x)) >> 16。
//   K 接近 1（采样率很低）时自动旁路，等于不滤波。
//==============================================================================
`timescale 1ns / 1ps

module bpf50 (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 步进使能（= 采集写使能 we）
    input  wire        filt_on,   // SW15: 1=滤波 0=直通
    input  wire        adc_mode,  // 1=AD/DA(样本 8clk 起) 0=自发生(2100clk 起)
    input  wire [3:0]  tb_idx,    // 时基档位（决定采样率 -> 决定增益）
    input  wire [9:0]  din,
    output wire [9:0]  dout
);

    //------------------------------------------------------------------
    // 卡尔曼增益表 K（Q16），等效截止 150Hz
    //------------------------------------------------------------------
    reg [15:0] kal_k;
    always @(*) begin
        if (adc_mode) begin
            case (tb_idx)
                4'd0: kal_k = 16'd55435;
                4'd1: kal_k = 16'd39807;
                4'd2: kal_k = 16'd24473;
                4'd3: kal_k = 16'd13660;
                4'd4: kal_k = 16'd7229;
                4'd5: kal_k = 16'd3719;
                4'd6: kal_k = 16'd1887;
                4'd7: kal_k = 16'd949;
                4'd8: kal_k = 16'd476;
                4'd9: kal_k = 16'd237;
                4'd10: kal_k = 16'd118;
                4'd11: kal_k = 16'd59;
                4'd12: kal_k = 16'd29;
                4'd13: kal_k = 16'd20;
                4'd14: kal_k = 16'd20;
                default: kal_k = 16'd20;
            endcase
        end
        else begin
            case (tb_idx)
                4'd0: kal_k = 16'd55435;
                4'd1: kal_k = 16'd39807;
                4'd2: kal_k = 16'd24473;
                4'd3: kal_k = 16'd13660;
                4'd4: kal_k = 16'd7229;
                default: kal_k = 16'd4950;
            endcase
        end
    end

    // K 太小 -> 采样率太高、平滑过强（响应迟钝），K 太大 -> 等于不滤波
    wire filt_ok = filt_on && (kal_k < 16'd60000);

    reg signed [23:0] xq;          // 状态（Q8）
    wire signed [23:0] zq = ($signed({14'b0, din}) - 24'sd512) <<< 8;   // 输入 Q8
    wire signed [23:0] err = zq - xq;
    wire signed [39:0] mul = err * $signed({24'b0, kal_k});
    wire signed [23:0] inc = mul[39:16];   // = (mul>>>16) 取低 24 位，位等价
    wire signed [23:0] xn  = xq + inc;

    // 输出: Q8 -> Q0，限幅后加中点
    wire signed [23:0] yq = xn >>> 8;
    wire signed [23:0] yc = (yq > 24'sd511)  ? 24'sd511  :
                             (yq < -24'sd512) ? -24'sd512 : yq;

    assign dout = filt_ok ? (yc[9:0] + 10'd512) : din;

    always @(posedge clk) begin
        if (rst) xq <= 24'sd0;
        else if (en) begin
            if (filt_ok) xq <= xn;
            else         xq <= zq;     // 旁路时状态跟随输入，切回来不跳
        end
    end

endmodule

