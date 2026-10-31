`timescale 1ns / 1ps
//=============================================================================
// tb_eso.v -- ADRC 扩展状态观测器(eso.v)自检
//
// 被测: FPGA/src/eso.v（P26 起为 6 级流水线实现，见 RTL 头部说明）
//
// 时序契约（本用例的判据就按这张表来，RTL 头部写的是同一份）:
//     en 所在的那个时钟周期记作第 0 拍，之后每个 posedge 加 1 拍
//       第 4 拍（Z_LAT）: z1k0/z2k0/z3k0 更新
//       第 6 拍（U_LAT）: out_da 更新
//     流水线空闲时上述输出一位都不许动；流水线忙（pv[2:0] 非零）时到来的
//     en 被 RTL 忽略，本用例的 en 间隔固定 8 拍，不会触发该情形。
//
// 检查项:
//   1) 复位: 内部状态 z1/z2/z3 全 0
//      out_da 由零状态算出：she=0 -> sgn=-1 -> v_1=-1 -> >>>15=-1，
//      低 10 位就是 10'h3FF（按 10bit 补码解释是 -1，是原算法 sgn 项的
//      固有行为，不是 bug），流水线版本的 out_da 复位值与之相同
//   2) 流水线延迟: 单脉冲 en 后数拍，状态必须正好第 Z_LAT 拍更新、
//      out_da 必须正好第 U_LAT 拍更新（防止以后改流水线深度不告知）
//   3) 使能门控: en=0 期间系统时钟一直打拍，z1/z2/z3、out_da 一个 bit 都不许变
//   4) 单拍推进: 状态/输出只允许在 en 之后的有限窗口内变化（逐拍监控）
//   5) 阶跃响应: y=+100 / -100 / 0 各跑 900 个采样
//      - 前 300 拍收敛，后 600 拍统计：平均 z1 ≈ y、峰峰值有界（不发散）
//      - 注意观测器里 sgn 项是 ±1 的符号补偿，稳态本来就有几个码的抖动，
//        所以判据用"平均值 + 峰峰值"，不要求逐点相等
//   6) 输出范围: out_da 是 10bit 补码，检查落在 -512..511 且不是 x
//=============================================================================
module tb_eso;

    localparam integer CLK_HALF_PS = 20833;      // 24MHz

    // 流水线延迟契约（单位: en 之后的拍数）
    localparam integer Z_LAT = 4;                // 状态更新
    localparam integer U_LAT = 6;                // out_da 更新

    reg clk  = 1'b0;
    reg rstn = 1'b0;
    reg en   = 1'b0;

    reg signed [9:0] e_in = 10'sd0;              // 误差输入(= -(y))

    wire signed [19:0] z1k0, z2k0, z3k0;
    wire signed [9:0]  out_da;

    // u_out 是"上一拍控制量"的反馈输入，顶层就是把它接回 out_da
    eso dut (
        .ad_clk    (clk),
        .sys_rst_n (rstn),
        .en        (en),
        .e_in      (e_in),
        .u_out     (out_da),
        .out_da    (out_da),
        .c_flag    (1'b0),
        .k_flag    (1'b0),
        .c_date    (12'd150),
        .k_date    (12'd20),
        .z1k0      (z1k0),
        .z2k0      (z2k0),
        .z3k0      (z3k0)
    );

    always #(CLK_HALF_PS/1000.0) clk = ~clk;

    integer errors = 0;
    reg     chk    = 1'b0;

    // 稳态窗口统计
    reg     win = 1'b0;
    integer win_min, win_max, win_sum, win_cnt, v_now;

    //------------------------------------------------------------------
    // en 历史: en_hist[i] = (i+1) 拍之前的 en
    //   第 K 个 posedge 检测到"状态变了"时，这次变化是第 K-1 拍那个沿
    //   写进去的，而它由 Z_LAT 拍之前的 en 触发（out_da 同理用 U_LAT）。
    //   只有窗口里出现过 en，才允许输出变化。
    //------------------------------------------------------------------
    reg [7:0] en_hist;

    always @(posedge clk) begin
        if (!rstn) en_hist <= 8'd0;
        else       en_hist <= {en_hist[6:0], en};
    end

    //------------------------------------------------------------------
    // 逐拍监控 + 窗口统计
    //------------------------------------------------------------------
    reg [19:0] z1_h, z2_h, z3_h;
    reg [9:0]  o_h;
    integer    hold_bad = 0;

    always @(posedge clk) begin
        if (!rstn) begin
            z1_h <= 20'sd0; z2_h <= 20'sd0; z3_h <= 20'sd0;
            o_h  <= 10'h3FF;
        end
        else begin
            // 状态: 只允许在 en 之后的 Z_LAT 窗口内变化
            if (chk && !(|en_hist[Z_LAT:0]) &&
                ((z1k0 !== z1_h) || (z2k0 !== z2_h) || (z3k0 !== z3_h)))
                hold_bad = hold_bad + 1;

            // 控制量: 只允许在 en 之后的 U_LAT 窗口内变化
            if (chk && !(|en_hist[U_LAT:0]) && (out_da !== o_h))
                hold_bad = hold_bad + 1;

            // en 之后第 Z_LAT 拍: 此刻 z1k0 已经是本采样的新值，计入窗口
            // （en_hist[Z_LAT] = Z_LAT+1 拍之前出现过 en，即本拍刚好吃到新状态）
            if (win && en_hist[Z_LAT]) begin
                v_now = z1k0;
                if (v_now < win_min) win_min = v_now;
                if (v_now > win_max) win_max = v_now;
                win_sum = win_sum + v_now;
                win_cnt = win_cnt + 1;
            end

            z1_h <= z1k0; z2_h <= z2k0; z3_h <= z3k0; o_h <= out_da;
        end
    end

    //------------------------------------------------------------------
    // 采样节拍: 拉高 en 一拍, 然后停 7 拍（模拟 3.15MHz 采样 / 25.2MHz 时钟）
    //   流水线需要 6 拍算完，8 拍一采正好留 2 拍余量
    //------------------------------------------------------------------
    task tick;
        begin
            @(negedge clk); en = 1'b1;
            @(negedge clk); en = 1'b0;
            repeat (6) @(negedge clk);
        end
    endtask

    // 连续跑 n 个采样, 并把 y 保持为 y_in
    task run_samples;
        input signed [9:0] y_in;
        input integer     n;
        integer i;
        begin
            e_in = -y_in;               // eso 内部 y <= -e_in
            for (i = 0; i < n; i = i + 1) tick;
        end
    endtask

    //------------------------------------------------------------------
    // 流水线延迟测量: 单个 en 脉冲，数到状态 / out_da 变化为止
    //   计数约定: en 所在拍 = 0，之后每个 posedge 加 1
    //------------------------------------------------------------------
    task measure_latency;
        integer n, z_lat, u_lat;
        reg signed [19:0] z_ref;
        reg        [9:0]  o_ref;
        begin
            rstn = 1'b0; en = 1'b0; e_in = -10'sd100;   // y = +100
            repeat (8) @(negedge clk);
            rstn = 1'b1;
            repeat (4) @(negedge clk);
            chk = 1'b1;

            // 单脉冲 en（高一个整拍）
            @(negedge clk); en = 1'b1;
            @(posedge clk); #1;                          // 第 0 拍: en 被采到
            z_ref = z1k0; o_ref = out_da;
            @(negedge clk); en = 1'b0;

            n = 1;                                       // 现在在第 1 拍
            while ((z1k0 === z_ref) && (n < 16)) begin
                @(posedge clk); #1; n = n + 1;
            end
            z_lat = n;

            while ((out_da === o_ref) && (n < 20)) begin
                @(posedge clk); #1; n = n + 1;
            end
            u_lat = n;

            $display("[tb_eso] 流水线延迟: 状态 %0d 拍 (期望 %0d), out_da %0d 拍 (期望 %0d)",
                     z_lat, Z_LAT, u_lat, U_LAT);
            if (z_lat != Z_LAT) begin
                errors = errors + 1;
                $display("  FAIL 状态更新延迟不是 %0d 拍 (实际 %0d)", Z_LAT, z_lat);
            end
            if (u_lat != U_LAT) begin
                errors = errors + 1;
                $display("  FAIL out_da 更新延迟不是 %0d 拍 (实际 %0d)", U_LAT, u_lat);
            end
        end
    endtask

    // 复位 + 跑一个阶跃, 检查收敛
    task check_step;
        input signed [9:0] y_in;
        input [8*8-1:0]    tag;
        integer avg, pp, de;
        begin
            rstn = 1'b0; en = 1'b0; e_in = -y_in;
            repeat (8) @(negedge clk);
            rstn = 1'b1;
            repeat (4) @(negedge clk);

            // 前两拍的响应方向必须跟输入一致（符号约定检查）
            run_samples(y_in, 2);
            @(posedge clk); #1;
            if (((y_in > 0) && (z1k0 <= 0)) || ((y_in < 0) && (z1k0 >= 0))) begin
                errors = errors + 1;
                $display("  FAIL %0s 阶跃方向反了 (y=%0d z1=%0d)", tag, y_in, z1k0);
            end

            // 收敛段
            run_samples(y_in, 298);

            // 稳态窗口
            win_min = 32'sd1000000000; win_max = -32'sd1000000000;
            win_sum = 0; win_cnt = 0; win = 1'b1;
            run_samples(y_in, 600);
            win = 1'b0;
            @(posedge clk); #1;

            avg = win_sum / win_cnt;
            pp  = win_max - win_min;
            de  = (z1k0 > y_in) ? (z1k0 - y_in) : (y_in - z1k0);

            $display("  %0s: y=%0d -> 稳态 z1 均值=%0d 峰峰=%0d 末值=%0d z2=%0d z3=%0d out_da=%0d",
                     tag, y_in, avg, pp, z1k0, z2k0, z3k0, out_da);

            if ((avg > (y_in + 6)) || (avg < (y_in - 6))) begin
                errors = errors + 1;
                $display("  FAIL %0s z1 没有跟踪到 y (平均 %0d, 期望 %0d)", tag, avg, y_in);
            end
            if (pp > 40) begin
                errors = errors + 1;
                $display("  FAIL %0s 稳态峰峰值过大 %0d（观测器在抖/发散）", tag, pp);
            end
            if (de > 20) begin
                errors = errors + 1;
                $display("  FAIL %0s 末值偏离 y 太多 (%0d)", tag, de);
            end
            if ((z3k0 > 20'sd200000) || (z3k0 < -20'sd200000)) begin
                errors = errors + 1;
                $display("  FAIL %0s z3 发散 (=%0d)", tag, z3k0);
            end
            if ((out_da === 10'hxxx) || (out_da > 10'sd511) || (out_da < -10'sd512)) begin
                errors = errors + 1;
                $display("  FAIL %0s out_da 越界 (=%0d)", tag, out_da);
            end
        end
    endtask

    //------------------------------------------------------------------
    // 主流程
    //------------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_eso.vcd");
            $dumpvars(0, tb_eso);
        end

        //==================== 1) 复位 ====================
        repeat (8) @(negedge clk);
        #1;
        $display("[tb_eso] 复位: z1=%0d z2=%0d z3=%0d out_da=%0h (%0d)",
                 z1k0, z2k0, z3k0, out_da, out_da);
        if (z1k0 !== 20'sd0 || z2k0 !== 20'sd0 || z3k0 !== 20'sd0) begin
            errors = errors + 1; $display("  FAIL 复位时观测状态不是 0");
        end
        // 零状态: she=0 -> sgn=-1 -> v=-1 -> >>>15 = -1 -> out_da=10'h3FF
        if (out_da !== 10'h3FF) begin
            errors = errors + 1;
            $display("  FAIL 复位时 out_da 应为 10'h3FF(=-1)，实际 %0h", out_da);
        end

        rstn = 1'b1;
        repeat (4) @(negedge clk);
        chk = 1'b1;

        //==================== 2) en=0 必须冻结 ====================
        $display("[tb_eso] 阶段 2: en=0，输入变化 + 时钟不停，状态必须保持不变");
        e_in = -10'sd100;
        repeat (200) @(negedge clk);
        #1;
        if (z1k0 !== 20'sd0 || z2k0 !== 20'sd0 || z3k0 !== 20'sd0) begin
            errors = errors + 1;
            $display("  FAIL en=0 时状态被推进了 (z1=%0d z2=%0d z3=%0d)", z1k0, z2k0, z3k0);
        end
        if (out_da !== 10'h3FF) begin
            errors = errors + 1;
            $display("  FAIL en=0 时 out_da 变了 (%0h)", out_da);
        end

        //==================== 3) 流水线延迟 ====================
        $display("[tb_eso] 阶段 3: 单脉冲 en 的流水线延迟（状态 %0d 拍 / out_da %0d 拍）",
                 Z_LAT, U_LAT);
        measure_latency;

        //==================== 4) 阶跃响应 ====================
        $display("[tb_eso] 阶段 4: 阶跃响应（前 300 拍收敛，后 600 拍统计）");
        check_step( 10'sd100, "step+100");
        check_step(-10'sd100, "step-100");
        check_step( 10'sd0,   "step0");

        //==================== 5) 逐拍推进 ====================
        $display("[tb_eso] 阶段 5: 状态/输出只允许在 en 之后的窗口内变化");
        if (hold_bad != 0) begin
            errors = errors + 1;
            $display("  FAIL 有 %0d 次在无 en 窗口内输出发生变化", hold_bad);
        end
        else $display("  逐拍检查: en 窗口外输出变化 0 次");

        if (errors == 0) $display("[tb_eso] PASS");
        else             $display("[tb_eso] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
