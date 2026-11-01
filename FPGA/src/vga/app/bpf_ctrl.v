//==============================================================================
// 层: 应用(控制)  文件: sparkroad_scope_top 内的算法级带通（本文件为独立模块）
// 文件: app/bpf_ctrl.v
// 功能: 算法级 40~54Hz 带通滤波 —— 只用在 **ADRC 的输入 y** 上
//       显示通路仍显示原始 ADC 采样值，不受影响。
//
//   规格：中心 48Hz、带宽 20Hz（38~58Hz）、二阶状态变量（Chamberlin SVF）
//   采样率 = ADCLK = 25.2MHz/8 = 3.15MHz（ADRC 每来一个 ad_val_valid 推进一次）
//     f = 2*sin(pi*48/3.15MHz) = 9.574e-5  -> Q24 = 1606
//     q = 1/Q = 20/48 = 0.4167            -> Q16 = 27307  (Q=2.4)
//   定点：状态 Q16（32bit），系数 Q24/Q16；乘积 Q40，右移 24 回到 Q16。
//   节拍：en 每 8 个时钟来一次，用 4 拍状态机分时复用 2 个乘法器，
//         输出比 en 晚 4 拍，用 dvalid 标出有效。
//==============================================================================
`timescale 1ns / 1ps

module bpf_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 1=来一个新 ADC 采样（ad_val_valid）
    input  wire [9:0]  din,       // ADC 原始码 0..1023
    output reg  [9:0]  dout,      // 带通输出（同量纲，中心 512）
    output reg         dvalid
);

    localparam signed [23:0] F_Q24 = 24'sd1606;    // 2*sin(pi*f0/fs)  Q24
    localparam signed [15:0] Q_Q16 = 16'sd27307;   // 1/Q = 14/47      Q16

    reg signed [31:0] low;         // 低通状态 Q16
    reg signed [31:0] band;        // 带通状态 Q16
    reg        [2:0]  st;
    reg signed [31:0] x_q16;       // 本拍输入（Q16）
    reg signed [31:0] t1;          // f*band >>24
    reg signed [31:0] low_n;
    reg signed [31:0] qb;          // q*band
    reg signed [31:0] high;
    reg signed [31:0] t3;          // f*high >>24

    wire signed [31:0] x_in = ($signed({22'b0, din}) - 32'sd512) <<< 16;

    wire signed [31:0] band_n = band + t3;
    // 归一化：bc = band * (1/Q)，使 47Hz 处增益 = 1（否则峰值增益 = Q = 3.36）
    wire signed [63:0] bc     = band_n * $signed({48'b0, Q_Q16});   // Q16*Q16 -> Q32
    wire signed [31:0] yq     = bc[63:32];                          // Q32 -> Q0（有符号偏移）
    wire        [9:0]  ycode  = (yq > 32'sd511)  ? 10'd1023 :
                                (yq < -32'sd512) ? 10'd0    : (yq[9:0] + 10'd512);

    always @(posedge clk) begin
        if (rst) begin
            low <= 32'sd0; band <= 32'sd0; st <= 3'd0;
            x_q16 <= 32'sd0; t1 <= 32'sd0; low_n <= 32'sd0;
            qb <= 32'sd0; high <= 32'sd0; t3 <= 32'sd0;
            dout <= 10'd512; dvalid <= 1'b0;
        end
        else begin
            dvalid <= 1'b0;
            case (st)
                3'd0: if (en) begin x_q16 <= x_in; st <= 3'd1; end
                3'd1: begin                                  // t1 = f*band
                    t1 <= (band * $signed({{8{F_Q24[23]}}, F_Q24})) >>> 24;
                    st <= 3'd2;
                end
                3'd2: begin                                  // low += t1 ; qb = q*band
                    low_n <= low + t1;
                    qb    <= (band * $signed({16'b0, Q_Q16})) >>> 16;
                    st    <= 3'd3;
                end
                3'd3: begin                                  // high = x - low - qb
                    high <= x_q16 - low_n - qb;
                    st   <= 3'd4;
                end
                3'd4: begin                                  // t3 = f*high
                    t3 <= (high * $signed({{8{F_Q24[23]}}, F_Q24})) >>> 24;
                    st <= 3'd5;
                end
                3'd5: begin                                  // band += t3 ; 输出
                    low  <= low_n;
                    band <= band + t3;
                    dout   <= ycode;
                    dvalid <= 1'b1;
                    st     <= 3'd0;
                end
                default: st <= 3'd0;
            endcase

        end
    end

endmodule





