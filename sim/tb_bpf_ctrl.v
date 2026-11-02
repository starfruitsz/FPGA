`timescale 1ns/1ps
//=============================================================================
// tb_bpf_ctrl.v -- 48Hz 算法带通(bpf_ctrl.v)自检
//
// 判据：输入 48Hz 正弦（幅度 ±47 码，pp=94），输出应为中心增益 1.0 的正弦，
//       pp 落在 94*(1±10%) 内。同时统计 dvalid 次数，确认流水线在走。
//
// [2026-11-02 重写] 旧版本两个问题：
//   1) en 分频 4096、只跑 300 万拍 -> 只有 732 个采样，判据要求 n>2000，
//      于是 hits 永远是 0、mx/mn 保持初值，必然 FAIL；
//   2) 没有"输入幅度/输出幅度"的显式判据。
//   现改为 en 每 8 拍一次（采样率随 clk 缩放，但信号频率仍按 48/6152.34 的
//   采样点比例给，语义不变），跑 40000 拍 ≈ 5000 个采样。
//=============================================================================
`timescale 1ns/1ps
module tb_bpf_ctrl;
    reg clk = 0, rst = 1;
    reg [9:0] din = 10'd512;
    wire [9:0] dout;
    wire dvalid;

    reg [2:0] div = 3'd0;
    wire en = (div == 3'd0);

    bpf_ctrl dut(.clk(clk), .rst(rst), .en(en), .din(din), .dout(dout), .dvalid(dvalid));

    always #5 clk = ~clk;
    always @(posedge clk) div <= div + 3'd1;

    integer n = 0;
    real ph;
    always @(posedge clk) if (!rst && en) begin
        ph = 6.2831853 * 48.0 * n / 6152.34;
        din <= 512 + $rtoi(47.0 * $sin(ph));
        n   <= n + 1;
    end

    integer hits = 0, mx = 0, mn = 1023;
    always @(posedge clk) begin
        #1;
        if (!rst && dvalid) begin
            if (n > 1000) begin
                hits = hits + 1;
                if (dout > mx) mx = dout;
                if (dout < mn) mn = dout;
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst = 0;
        repeat (40000) @(posedge clk);
        $display("  [tb_bpf_ctrl] n=%0d hits=%0d mx=%0d mn=%0d pp=%0d amp=%.1f gain=%.3f",
                 n, hits, mx, mn, mx-mn, (mx-mn)/2.0, ((mx-mn)/2.0)/47.0);
        if (hits > 100 && (mx-mn) > 94*0.9 && (mx-mn) < 94*1.1) $display("  [tb_bpf_ctrl] PASS");
        else                                                      $display("  [tb_bpf_ctrl] FAIL");
        $finish;
    end
endmodule
