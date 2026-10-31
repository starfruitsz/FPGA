`timescale 1ns / 1ps
//=============================================================================
// tb_scope_trigger.v -- 触发对齐 / SW3 滚动显示 / 退出滚动回乒乓 路径验证
//
// 输入: 周期 90 采样点的方波 (前 45 点 800, 后 45 点 200)
//   选 90 是因为它既不整除 1024（否则循环缓冲快照相位恒定）
//   也不整除 420000（否则相邻帧之间不会漂移）
//
// 判据 A（触发打开, normal 模式）:
//   捕获完成后缓冲被冻结(we=0)，直接从 RAM 读 [rd_base .. rd_base+639]，
//   必须严格符合"以触发点为起点"的方波相位：k%90<45 -> 800，否则 200。
//   这验证了 rd_base 确实对准触发点（触发对齐的核心）。
// 判据 B（触发关闭）:
//   相隔一帧读取同一批地址，内容必须发生变化（相位在自由漂移），
//   与 A 形成对照。
// 判据 C（SW3 滚动模式, 斜坡输入）—— 缺陷 1:
//   - SW3 拨上后 scroll_en 生效，显示读地址改用"正在写的那半"(buf_wr)
//   - 采集自由循环写：we 每拍有效、写指针持续前进、不响应触发、状态停在 ARMED
//   - 最右列的采样值必须大于最左列（最右列是最新采样 => 波形向左滚动）
// 判据 D（SW3 拨下回到乒乓）:
//   - 显示读地址切回 buf_disp（已采完的那半）
//   - 必须重新采满一屏(1024 点)才更新 buf_disp / 翻 buf_wr
//   - 新显示的那半内容必须是连续斜坡（证明是整屏采完才切，不是半屏）
//=============================================================================
module tb_scope_trigger;

    localparam integer CLK_NS = 20;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [9:0] ch0_in = 10'd512;
    reg adc_valid = 1'b1, key_in = 1'b1;
    reg sq_mode = 1'b1, ramp_mode = 1'b0;
    reg [6:0] sq_cnt = 7'd0;
    reg sw_roll = 1'b0;                 // SW3：已弃用（T6 无反应）
    reg sw_roll2 = 1'b1;                // SW5：拨上=非滚动、拨下=滚动

    reg cfg_tb_we=1'b0;    reg [15:0] cfg_tb=16'd0;
    reg cfg_ten_we=1'b0;   reg cfg_ten=1'b0;
    reg cfg_scr_we=1'b0;   reg cfg_scr=1'b0;
    reg cfg_tmode_we=1'b0; reg [1:0] cfg_tmode=2'd0;

    wire [11:0] vga_rgb;
    wire vga_hs, vga_vs, vga_de;
    wire sel_ch_o;               // 选中通道（SW2 复用结果，本用例不关心，仅保持端口同步）

    vga_scope_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(1),
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224), .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10), .CLK_HZ(24_000_000),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) dut (
        .clk(clk), .rst(rst), .ch0_in(ch0_in), .ch1_in(10'd512),
        .adc_valid(adc_valid), .adc_mode(1'b0), .key_n(4'b1111), .sw_menu(1'b0), .sw_run(1'b0), .sw_page(1'b0), .sw_roll(sw_roll), .sw_roll2(sw_roll2), .sw_auto(1'b0), .sw_hzfree(1'b0), .sw_move(1'b0),
        .cfg_tb_we(cfg_tb_we), .cfg_tb(cfg_tb),
        .cfg_run_we(1'b0), .cfg_run(1'b1),
        .cfg_ten_we(cfg_ten_we), .cfg_ten(cfg_ten),
        .cfg_lvl_we(1'b0), .cfg_lvl(10'd512),
        .cfg_edg_we(1'b0), .cfg_edg(1'b0),
        .cfg_scr_we(cfg_scr_we), .cfg_scr(cfg_scr),
        .cfg_tmode_we(cfg_tmode_we), .cfg_tmode(cfg_tmode),
        .cfg_tsrc_we(1'b0), .cfg_tsrc(1'b0),
        .cfg_pre_we(1'b0), .cfg_pre(10'd0),
        .cfg_hold_we(1'b0), .cfg_hold(16'd0),
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de),
        .sel_ch_o(sel_ch_o)
    );

    always #(CLK_NS/2) clk = ~clk;

    always @(posedge clk) begin
        sq_cnt <= (sq_cnt == 7'd89) ? 7'd0 : (sq_cnt + 7'd1);
        if (sq_mode)        ch0_in <= (sq_cnt < 7'd45) ? 10'd800 : 10'd200;
        else if (ramp_mode) ch0_in <= ch0_in + 10'd1;
    end

    integer errors = 0;
    integer k, bad, base, v, expect_v;
    integer snap1 [0:89];
    integer snap2 [0:89];
    reg [9:0] s_left, s_right;
    integer diff;

    // 判据 C / D 的观测变量
    integer wa_c0, wa_c1, we_bad, elapsed, done_seen, disp_before, wr_before;
    reg [9:0] disp_after, wr_after;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_scope_trigger.vcd");
            $dumpvars(0, tb_scope_trigger);
        end
        repeat (8) @(posedge clk);
        rst = 1'b0;

        @(posedge clk); cfg_tb_we <= 1'b1;   cfg_tb <= 16'd0;
        @(posedge clk); cfg_tb_we <= 1'b0;

        // ================= 判据 A: 触发打开 =================
        @(posedge clk); cfg_ten_we <= 1'b1;  cfg_ten <= 1'b1;
        @(posedge clk); cfg_ten_we <= 1'b0;
        @(posedge clk); cfg_tmode_we <= 1'b1; cfg_tmode <= 2'd1;   // normal
        @(posedge clk); cfg_tmode_we <= 1'b0;

        wait (dut.u_cap0.state == 2'd3);      // 等到一次捕获完成(此时 we=0, 缓冲冻结)
        @(posedge clk);
        @(posedge clk);

        base = dut.rd_base0;
        bad = 0;
        for (k = 0; k < 640; k = k + 1) begin
            v = dut.u_ram0.mem[((base + k) & 1023) + (dut.buf_disp0 ? 1024 : 0)];  // 乒乓缓冲
            expect_v = ((k % 90) < 45) ? 800 : 200;
            if (v != expect_v) begin
                if (bad < 6) $display("     不匹配 k=%0d got=%0d expect=%0d", k, v, expect_v);
                bad = bad + 1;
            end
        end
        $display("[tb_scope_trigger] A 触发对齐 (normal, rd_base=%0d)", base);
        $display("  缓冲 [rd_base..+639] 与触发相位不符的点数 = %0d (expect 0)", bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL 触发没有对准 ==> rd_base 未锁到触发点"); end

        // ================= 判据 A2: 显示基准在 done 时锁存 =================
        //   arm 之后 rd_base 会被清 0，但屏幕这时还在显示刚采完的那半区。
        //   显示读地址必须继续用"那一屏"锁存下来的基准，否则每采完一屏
        //   画面就整体平移一次 —— 现象就是"画面一直慢慢滚/跳"。
        base = dut.rd_base_d0;
        wait (dut.u_cap0.state == 2'd1);      // 重新布防（rd_base 被清 0）
        @(posedge clk);
        @(posedge clk);
        $display("[tb_scope_trigger] A2 显示基准锁存: rd_base=%0d rd_base_d0=%0d (expect 0 / %0d)",
                 dut.rd_base0, dut.rd_base_d0, base);
        if (dut.rd_base0 !== 10'd0) begin
            errors=errors+1; $display("  FAIL 重新布防后 rd_base 没有清零"); end
        if (dut.rd_base_d0 !== base[9:0]) begin
            errors=errors+1; $display("  FAIL 显示基准没锁存（画面会平移）"); end

        // 再等一次捕获，确认 rd_base 对齐后内容仍然一致
        wait (dut.u_cap0.state == 2'd2);      // 离开 DONE，重新采集
        wait (dut.u_cap0.state == 2'd3);
        @(posedge clk); @(posedge clk);
        base = dut.rd_base0;
        bad = 0;
        for (k = 0; k < 640; k = k + 1) begin
            v = dut.u_ram0.mem[((base + k) & 1023) + (dut.buf_disp0 ? 1024 : 0)];  // 乒乓缓冲
            expect_v = ((k % 90) < 45) ? 800 : 200;
            if (v != expect_v) bad = bad + 1;
        end
        $display("  第二次捕获: rd_base=%0d，不符点数=%0d (expect 0)", base, bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL 第二次捕获相位不一致"); end

        // ================= 判据 B: 触发关闭 =================
        @(posedge clk); cfg_ten_we <= 1'b1;  cfg_ten <= 1'b0;
        @(posedge clk); cfg_ten_we <= 1'b0;
        @(posedge clk); cfg_tmode_we <= 1'b1; cfg_tmode <= 2'd0;   // auto
        @(posedge clk); cfg_tmode_we <= 1'b0;

        repeat (3000) @(posedge clk);
        for (k = 0; k < 90; k = k + 1) snap1[k] = dut.u_ram0.mem[k];
        repeat (420000) @(posedge clk);        // 正好一帧
        for (k = 0; k < 90; k = k + 1) snap2[k] = dut.u_ram0.mem[k];

        diff = 0;
        for (k = 0; k < 90; k = k + 1)
            if (snap1[k] != snap2[k]) diff = diff + 1;
        $display("[tb_scope_trigger] B 触发关闭: 相隔一帧同一批地址变化点数 = %0d (expect > 0)", diff);
        if (diff == 0) begin errors=errors+1;
            $display("  FAIL 无触发时缓冲相位居然不变，与 A 的对照不成立"); end

        // ================= 判据 C: 滚动显示（SW5 拨下 = 滚动）=================
        sq_mode = 1'b0; ramp_mode = 1'b1;
        repeat (20) @(posedge clk);
        sw_roll2 = 1'b0;                       // 拨下 = 滚动
        repeat (20) @(posedge clk);

        $display("[tb_scope_trigger] C SW5 滚动: scroll_en=%b roll=%b (expect 1/1)",
                 dut.scroll_en, dut.roll);
        if (dut.scroll_en !== 1'b1) begin errors=errors+1; $display("  FAIL SW5 没有把滚动状态置起来"); end
        if (dut.roll !== 1'b1)      begin errors=errors+1; $display("  FAIL roll 别名没有跟随 scroll_en"); end

        // 采集侧必须自由循环写：状态 ARMED、we 有效、写指针持续前进、不翻半区
        wa_c0 = dut.u_cap0.waddr;
        disp_before = dut.buf_disp0;
        wr_before   = dut.buf_wr0;
        we_bad = 0;
        for (k = 0; k < 300; k = k + 1) begin
            @(posedge clk);
            if (dut.we0 !== 1'b1) we_bad = we_bad + 1;
        end
        wa_c1 = dut.u_cap0.waddr;
        $display("  采集侧: state=%0d we(无效次数)=%0d 写指针 %0d -> %0d (expect +300)",
                 dut.u_cap0.state, we_bad, wa_c0, wa_c1);
        $display("  采集侧: buf_wr=%b buf_disp=%b (expect 不变 %0d/%0d，不翻乒乓半区)",
                 dut.buf_wr0, dut.buf_disp0, wr_before, disp_before);
        if (dut.buf_wr0 !== wr_before)      begin errors=errors+1; $display("  FAIL 滚动模式翻了写半区"); end
        if (dut.buf_disp0 !== disp_before)  begin errors=errors+1; $display("  FAIL 滚动模式翻了显示半区"); end
        if (dut.u_cap0.state !== 2'd1)      begin errors=errors+1; $display("  FAIL 滚动模式状态不是 ARMED"); end
        if (we_bad != 0)                    begin errors=errors+1; $display("  FAIL 滚动模式不是每拍写入"); end
        if (((wa_c0 + 300) & 1023) !== wa_c1) begin errors=errors+1; $display("  FAIL 写指针没有自由前进"); end
        if (dut.raddr0[10] !== dut.buf_wr0) begin errors=errors+1; $display("  FAIL 滚动的读地址没有指向正在写的那半"); end

        // 斜坡周期 1024 正好等于一屏，先让正在写的那半被斜坡完整覆盖一遍，
        // 这样左右两列之间才有确定的相位差（最右列比最左列晚 638 个采样）
        repeat (1200) @(posedge clk);

        s_left = 10'd0; s_right = 10'd0;
        while (s_left == 10'd0 || s_right == 10'd0) begin
            @(posedge clk);
            if (vga_de && dut.pix_ce) begin
                if (dut.px_d == 12'd1)   s_left  = dut.s0;
                if (dut.px_d == 12'd639) s_right = dut.s0;
            end
        end
        $display("[tb_scope_trigger] C 滚动显示: 最左列采样=%0d, 最右列采样=%0d (地址差 638)",
                 s_left, s_right);
        if (s_right <= s_left) begin errors=errors+1;
            $display("  FAIL 最右列不是最新采样（滚动方向不对）"); end
        if (((s_right - s_left) & 10'd1023) != 10'd638) begin errors=errors+1;
            $display("  FAIL 左右列相位差不是 638，滚动窗口没对齐"); end

        // ================= 判据 D: SW3 拨下回乒乓 =================
        // 先把触发参数恢复成 normal + 触发使能（滚动模式下不影响采集，退出后才生效）
        @(posedge clk); cfg_ten_we <= 1'b1;   cfg_ten <= 1'b1;
        @(posedge clk); cfg_ten_we <= 1'b0;
        @(posedge clk); cfg_tmode_we <= 1'b1; cfg_tmode <= 2'd1;
        @(posedge clk); cfg_tmode_we <= 1'b0;
        repeat (20) @(posedge clk);

        disp_before = dut.buf_disp0;
        wr_before   = dut.buf_wr0;

        sw_roll2 = 1'b1;                       // 拨上 = 非滚动
        repeat (8) @(posedge clk);
        $display("[tb_scope_trigger] D 退出滚动: scroll_en=%b 读半区=%b buf_disp=%b (expect 0/已采完的半)",
                 dut.scroll_en, dut.raddr0[10], dut.buf_disp0);
        if (dut.scroll_en !== 1'b0)             begin errors=errors+1; $display("  FAIL 拨上 SW5 没有退出滚动"); end
        if (dut.raddr0[10] !== dut.buf_disp0)   begin errors=errors+1; $display("  FAIL 退出滚动后读地址没切回 buf_disp"); end

        elapsed = 0; done_seen = 0;
        while ((elapsed < 5000) && (done_seen == 0)) begin
            @(posedge clk);
            elapsed = elapsed + 1;
            if (dut.done0 === 1'b1) done_seen = 1;
        end
        @(posedge clk);                    // 等 buf_disp / buf_wr 更新完
        disp_after = dut.buf_disp0;
        wr_after   = dut.buf_wr0;

        $display("  退出后第一次捕获: done=%0d 用时=%0d 拍（一屏=1024）", done_seen, elapsed);
        $display("  buf_disp %0d -> %0d, buf_wr %0d -> %0d",
                 disp_before, disp_after, wr_before, wr_after);
        if (done_seen == 0)            begin errors=errors+1; $display("  FAIL 退出滚动后没有完成捕获"); end
        if (elapsed < 1024)            begin errors=errors+1; $display("  FAIL 没有采满一屏就换页"); end
        if (disp_after !== wr_before)  begin errors=errors+1; $display("  FAIL 显示半区不是刚采满的那半"); end
        if (wr_after !== ((wr_before + 1) & 1))
                                       begin errors=errors+1; $display("  FAIL 写半区没有翻到另一半"); end
        if (disp_after == disp_before) begin errors=errors+1; $display("  FAIL 乒乓没有换页"); end
        if (dut.raddr0[10] !== dut.buf_disp0)
                                       begin errors=errors+1; $display("  FAIL 换页后读地址没用 buf_disp"); end

        // 新显示的那半必须是整屏连续斜坡（半屏数据的话这里会断）
        bad = 0;
        for (k = 1; k < 1024; k = k + 1) begin
            v = dut.u_ram0.mem[disp_after*1024 + k];
            expect_v = (dut.u_ram0.mem[disp_after*1024] + k) & 1023;
            if (v != expect_v) bad = bad + 1;
        end
        $display("  新半区连续斜坡不符点数 = %0d (expect 0)", bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL 显示半区不是整屏采满的数据"); end

        if (errors == 0) $display("[tb_scope_trigger] PASS");
        else             $display("[tb_scope_trigger] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
