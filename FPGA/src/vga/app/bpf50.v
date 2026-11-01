//==============================================================================
// 层: 应用(显示)  文件: app/bpf50.v
// 功能: 50Hz 带通显示滤波器（状态变量 SVF / Chamberlin 结构）
//
//   用途：SW15(R15) 拨上时启用，把送进显示 RAM 的采样先过一道「中心 50Hz、
//         Q=5」的带通，去掉直流与高频噪声，让 50Hz 正弦看起来平滑。
//
//   为什么放这里：滤波器必须按「显示采样率」(= 捕获速率) 跑，所以 step 直接
//   接采集写使能 we —— 每采一个点推进一次，中心频率恒为 50Hz，与一屏时间无关。
//
//   差分方程（Chamberlin 状态变量，稳定、系数好算）：
//     low  += f * band
//     high  = x - low - q*band
//     band += f * high
//     y     = band                      （带通输出）
//   定点：状态 Q8；f 为 Q12（f = 2*sin(pi*f0/fs)）；q = 1/Q = 1/5 ~ 13/64
//
//   注意：f 由顶层 bpf_f_rom 按 {adc_mode, tb_idx} 给出；最快几档 f 很小(甚至 0)，
//        此时滤波基本不起作用 —— 50Hz 带通本来也只对慢时基有意义。
//==============================================================================
`timescale 1ns / 1ps

module bpf50 (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 步进使能 (= 采集写使能 we)
    input  wire        filt_on,   // SW15: 1=滤波 0=直通
    input  wire [11:0] fcoef,     // Q12: f = 2*sin(pi*50/fs)
    input  wire [9:0]  din,
    output wire [9:0]  dout
);

    reg signed [19:0] low;    // 低通状态  Q8
    reg signed [19:0] band;   // 带通状态  Q8

    // x 转 Q8: (din-512)*256
    wire signed [19:0] xq = ($signed({10'b0, din}) - 20'sd512) <<< 8;

    // low += f*band  (Q8 * Q12 -> Q20 -> 右移 12 回 Q8)
    wire signed [31:0] p1  = band * $signed({8'b0, fcoef});
    wire signed [19:0] p1s = p1 >>> 12;
    wire signed [19:0] low_n = low + p1s;

    // q*band = band * 13 / 64
    wire signed [19:0] qb = (band * 20'sd13) >>> 6;

    // high = x - low - q*band
    wire signed [19:0] high = xq - low - qb;

    // band += f*high
    wire signed [31:0] p3  = high * $signed({8'b0, fcoef});
    wire signed [19:0] p3s = p3 >>> 12;
    wire signed [19:0] band_n = band + p3s;

    // 输出: Q8 -> Q0，限幅到 -512..+511，再加中点 512
    wire signed [19:0] yq = band_n >>> 8;
    wire signed [19:0] yc = (yq > 20'sd511)  ? 20'sd511  :
                             (yq < -20'sd512) ? -20'sd512 : yq;

    assign dout = filt_on ? (yc[9:0] + 10'd512) : din;

    always @(posedge clk) begin
        if (rst) begin
            low  <= 20'sd0;
            band <= 20'sd0;
        end
        else if (en && filt_on) begin
            low  <= low_n;
            band <= band_n;
        end
    end

endmodule
