`timescale 1ns / 1ps
//=============================================================================
// tb_ad_da_par.v -- 并口 AD/DA 模块驱动（ad_da_par）自检
//
// 被测: FPGA/src/ad_da_par.v
//   1) ADCLK / DACLK: 系统时钟 8 分频、占空比 50%、两路同相
//   2) AD 通路: ad_clk 反相沿锁存 ad_data -> 打两拍同步 -> s_data + s_valid(单拍)
//   3) DA 通路: da_clk 反相沿更新 da_data -> da_out，整个 DACLK 周期保持不变
//      （外部 DAC 在正相沿锁存，反相沿更新可给出半个周期的建立时间）
//   4) 复位: 所有输出为 0，s_valid 不出现毛刺
//
// 激励约定: 外部数据只在 clk 下降沿变化（真实器件相对采样沿有半个周期的建立
//   时间），这样"采样沿那一刻的值"是唯一确定的，参考模型不会和 DUT 抢边沿。
//   数据每拍都变化的模式专门用来验证采样点确实落在反相沿（而不是上升沿）。
//=============================================================================
module tb_ad_da_par;

    localparam integer CLK_HALF_PS = 20833;      // 24MHz 时钟半周期(ps)

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg  [9:0] ad_data = 10'h000;                // 外部 ADC 并行数据
    reg  [9:0] da_data = 10'h000;                // 送 DAC 的数据（顶层取 ch1_val）

    wire       ad_clk, da_clk;
    wire [9:0] s_data;
    wire       s_valid;
    wire [9:0] da_out;

    ad_da_par #(.DIV_LOG2(3)) dut (
        .clk     (clk),
        .rst     (rst),
        .ad_data (ad_data),
        .ad_clk  (ad_clk),
        .s_data  (s_data),
        .s_valid (s_valid),
        .da_data (da_data),
        .da_clk  (da_clk),
        .da_out  (da_out)
    );

    always #(CLK_HALF_PS/1000.0) clk = ~clk;

    integer errors = 0;

    // 自检使能: 复位期间 ad_clk/da_clk 还是 x, x->0 也算一次 negedge 事件,
    // 会让"采样点自检"和"占空比测量"各被带偏一次。等复位释放、时钟跑起来
    // 再打开自检, 这些上电伪边沿就不会被当成真实采样。
    reg chk_en = 1'b0;

    //------------------------------------------------------------------
    // 激励: 外部数据在 clk 下降沿更新
    //   stim_mode 0 = 固定码 0x155
    //             1 = 每个 ADCLK 周期换一个码（真实 ADC 行为）
    //             2 = 每拍都换（最坏情况，用来定位采样沿）
    //             3 = 0x2AA / 0x155 交替图样
    //------------------------------------------------------------------
    reg [1:0] stim_mode = 2'd0;
    reg [2:0] ad_div    = 3'd0;
    reg       ad_alt    = 1'b0;

    always @(negedge clk) begin
        ad_div <= ad_div + 3'd1;
        ad_alt <= (ad_div == 3'd0) ? ~ad_alt : ad_alt;
        case (stim_mode)
            2'd0: ad_data <= 10'h155;                              // 固定码
            2'd1: if (ad_div == 3'd0) ad_data <= ad_data + 10'd1;  // 每 8 拍换一次
            2'd2: ad_data <= ad_data + 10'd1;                      // 每拍换一次
            2'd3: ad_data <= ad_alt ? 10'h2AA : 10'h155;           // 交替图样
            default: ;                                             // 保持不变
        endcase
    end

    // DA 数据每拍都变：只有"反相沿更新 + 整个周期保持"才能在检查里全对
    reg [9:0] da_cnt = 10'd0;
    always @(negedge clk) begin
        da_cnt  <= da_cnt + 10'd3;
        da_data <= da_cnt;
    end

    //------------------------------------------------------------------
    // 时钟测量（$time 单位 ns）
    //------------------------------------------------------------------
    time    t_rise = 0, t_fall = 0;
    time    last_period = 0, last_high = 0;
    integer n_rise = 0;
    integer per_bad = 0, duty_bad = 0;

    always @(posedge ad_clk) begin
        if (n_rise > 0) begin
            last_period = $time - t_rise;
            // 8 分频: 周期 = 8 * 41.666ns = 333.3ns（含 $time 取整误差）
            if ((last_period < 332) || (last_period > 335)) per_bad = per_bad + 1;
            // 50% 占空比: 低电平宽度也必须和高电平一样
            if ((($time - t_fall) > (last_high + 2)) ||
                (($time - t_fall) + 2 < last_high)) duty_bad = duty_bad + 1;
        end
        t_rise  = $time;
        n_rise  = n_rise + 1;
    end

    always @(negedge ad_clk) begin
        // n_rise==0 说明还没出现过真实的上升沿(复位期间 x->0 的伪边沿)，跳过
        if (n_rise > 0) begin
            last_high = $time - t_rise;
            t_fall    = $time;
            // 高电平宽度 = 4 * 41.666ns = 166.6ns
            if ((last_high < 165) || (last_high > 168)) duty_bad = duty_bad + 1;
        end
    end

    //------------------------------------------------------------------
    // 时钟域检查: 两路时钟同相、s_valid 每 8 拍一次
    //------------------------------------------------------------------
    reg [31:0] cyc = 32'd0;
    integer    phase_bad = 0, vld_gap_bad = 0, n_vld = 0;
    reg [31:0] last_vld = 32'd0;

    always @(posedge clk) begin
        cyc <= cyc + 32'd1;
        if (ad_clk !== da_clk) phase_bad <= phase_bad + 1;
        if (s_valid === 1'b1) begin
            n_vld <= n_vld + 1;
            if ((n_vld > 0) && ((cyc - last_vld) !== 32'd8)) vld_gap_bad <= vld_gap_bad + 1;
            last_vld <= cyc;
        end
    end

    //------------------------------------------------------------------
    // AD 通路自检（每个 ADCLK 周期一次）
    //   参考值 = ad_clk 反相沿那一刻的 ad_data（就是 DUT 锁存的值），
    //   两拍之后 s_data 必须等于它、s_valid 必须为 1；
    //   再下一拍 s_valid 必须收回、s_data 保持到下一个采样点。
    //------------------------------------------------------------------
    integer n_ad_chk = 0;

    task ad_check;
        reg [9:0] ref;
        begin
            @(negedge ad_clk);              // 与 DUT 的捕获沿同一时刻
            ref = ad_data;
            @(posedge clk);                 // +1 拍: 第一级同步
            @(posedge clk);                 // +2 拍: 第二级同步 -> s_data 更新
            #1;
            if (s_data !== ref) begin
                errors = errors + 1;
                if (errors <= 10) $display("  FAIL AD 数据: 期望 %0d 实际 %0d (t=%0t)", ref, s_data, $time);
            end
            if (s_valid !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 10) $display("  FAIL AD s_valid: s_data 更新时没有拉高 (t=%0t)", $time);
            end
            @(posedge clk);                 // +3 拍: 脉冲必须收回
            #1;
            if (s_valid !== 1'b0) begin
                errors = errors + 1;
                if (errors <= 10) $display("  FAIL AD s_valid: 不是单拍脉冲 (t=%0t)", $time);
            end
            if (s_data !== ref) begin
                errors = errors + 1;
                if (errors <= 10) $display("  FAIL AD 数据: 没有保持到下一个采样点 (t=%0t)", $time);
            end
            n_ad_chk = n_ad_chk + 1;
        end
    endtask

    //------------------------------------------------------------------
    // DA 通路自检（每个 DACLK 周期一次）
    //   参考值 = da_clk 反相沿那一刻的 da_data（DUT 在同一拍更新 da_out），
    //   之后 7 个 clk 拍（覆盖随后的 DACLK 正相沿）da_out 都必须等于它：
    //   既验证"反相沿更新"，也验证"正相沿前后数据稳定"。
    //------------------------------------------------------------------
    integer n_da_chk = 0;

    task da_check;
        reg [9:0] ref;
        integer k;
        begin
            @(negedge da_clk);              // DUT 在这一拍更新 da_data -> da_out
            ref = da_data;
            for (k = 0; k < 7; k = k + 1) begin
                @(posedge clk);
                #1;
                if (da_out !== ref) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("  FAIL DA 数据: 期望 %0d 实际 %0d (周期内第 %0d 拍, t=%0t)",
                                 ref, da_out, k, $time);
                end
            end
            n_da_chk = n_da_chk + 1;
        end
    endtask

    initial begin
        wait (chk_en);          // 复位释放、时钟稳定后才开始自检
        forever ad_check;
    end
    initial begin
        wait (chk_en);
        forever da_check;
    end

    //------------------------------------------------------------------
    // 主流程
    //------------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_ad_da_par.vcd");
            $dumpvars(0, tb_ad_da_par);
        end

        //==================== 复位 ====================
        repeat (10) @(posedge clk);
        #1;
        $display("[tb_ad_da_par] 复位: ad_clk=%b da_clk=%b s_data=%0d s_valid=%b da_out=%0d",
                 ad_clk, da_clk, s_data, s_valid, da_out);
        if (ad_clk !== 1'b0)   begin errors=errors+1; $display("  FAIL 复位时 ADCLK 不是 0"); end
        if (da_clk !== 1'b0)   begin errors=errors+1; $display("  FAIL 复位时 DACLK 不是 0"); end
        if (s_data !== 10'd0)  begin errors=errors+1; $display("  FAIL 复位时 s_data 不是 0"); end
        if (s_valid !== 1'b0)  begin errors=errors+1; $display("  FAIL 复位时 s_valid 不是 0"); end
        if (da_out !== 10'd0)  begin errors=errors+1; $display("  FAIL 复位时 da_out 不是 0"); end
        if (n_vld != 0)        begin errors=errors+1; $display("  FAIL 复位期间 s_valid 有脉冲"); end

        rst = 1'b0;

        // 等时钟稳定两个完整 ADCLK 周期后再打开自检(避开上电伪边沿)
        repeat (2) @(posedge ad_clk);
        chk_en = 1'b1;

        //==================== 阶段 1: 固定码 ====================
        $display("[tb_ad_da_par] 阶段 1: ad_data 固定 0x155");
        stim_mode = 2'd0;
        repeat (40) @(posedge ad_clk);

        //==================== 阶段 2: 每个 ADCLK 换码 ====================
        $display("[tb_ad_da_par] 阶段 2: 每个 ADCLK 周期换一个码（真实 ADC）");
        stim_mode = 2'd1;
        repeat (80) @(posedge ad_clk);

        //==================== 阶段 3: 每拍换码（最坏情况）====================
        $display("[tb_ad_da_par] 阶段 3: ad_data 每拍都变（验证采样点在反相沿）");
        stim_mode = 2'd2;
        repeat (80) @(posedge ad_clk);

        //==================== 阶段 4: 交替图样 ====================
        $display("[tb_ad_da_par] 阶段 4: ad_data 在 0x2AA/0x155 间交替");
        stim_mode = 2'd3;
        repeat (80) @(posedge ad_clk);

        //==================== 阶段 5: 回到固定码 ====================
        stim_mode = 2'd0;
        repeat (40) @(posedge ad_clk);

        //==================== 结论 ====================
        $display("[tb_ad_da_par] ADCLK: 周期=%0d ns (8 分频应为 333ns) 高电平=%0d ns (应为 166ns) 上升沿=%0d 个",
                 last_period, last_high, n_rise);
        $display("[tb_ad_da_par] AD 采样自检=%0d 次, DA 锁存自检=%0d 次, s_valid 脉冲=%0d 个",
                 n_ad_chk, n_da_chk, n_vld);

        if (per_bad  != 0) begin errors=errors+1;
            $display("  FAIL ADCLK 周期不是 8 分频 (%0d 次)", per_bad); end
        if (duty_bad != 0) begin errors=errors+1;
            $display("  FAIL ADCLK 占空比不是 50%% (%0d 次)", duty_bad); end
        if (phase_bad != 0) begin errors=errors+1;
            $display("  FAIL ADCLK/DACLK 不同相 (%0d 次)", phase_bad); end
        if (vld_gap_bad != 0) begin errors=errors+1;
            $display("  FAIL s_valid 间隔不是 8 拍 (%0d 次)", vld_gap_bad); end
        if (n_ad_chk < 200) begin errors=errors+1;
            $display("  FAIL AD 自检次数太少 (%0d)", n_ad_chk); end
        if (n_da_chk < 200) begin errors=errors+1;
            $display("  FAIL DA 自检次数太少 (%0d)", n_da_chk); end

        if (errors == 0) $display("[tb_ad_da_par] PASS");
        else             $display("[tb_ad_da_par] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
