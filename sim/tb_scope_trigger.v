`timescale 1ns / 1ps
//=============================================================================
// tb_scope_trigger.v -- 触发对齐 / 滚动显示 路径验证（此前完全未验证）
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
// 判据 C（滚动模式, 斜坡输入）:
//   最右列的采样值必须大于最左列（最右列是最新采样）。
//=============================================================================
module tb_scope_trigger;

    localparam integer CLK_NS = 20;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [9:0] ch0_in = 10'd512;
    reg adc_valid = 1'b1, key_in = 1'b1;
    reg sq_mode = 1'b1, ramp_mode = 1'b0;
    reg [6:0] sq_cnt = 7'd0;

    reg cfg_tb_we=1'b0;    reg [15:0] cfg_tb=16'd0;
    reg cfg_ten_we=1'b0;   reg cfg_ten=1'b0;
    reg cfg_scr_we=1'b0;   reg cfg_scr=1'b0;
    reg cfg_tmode_we=1'b0; reg [1:0] cfg_tmode=2'd0;

    wire [11:0] vga_rgb;
    wire vga_hs, vga_vs, vga_de;

    vga_scope_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(1),
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224), .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10), .CLK_HZ(24_000_000),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) dut (
        .clk(clk), .rst(rst), .ch0_in(ch0_in), .ch1_in(10'd512),
        .adc_valid(adc_valid), .key_n(4'b1111), .sw_menu(1'b0), .sw_run(1'b1), .sw_page(1'b0), .sw_roll(1'b0),
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
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de)
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
            v = dut.u_ram0.mem[(base + k) & 1023];
            expect_v = ((k % 90) < 45) ? 800 : 200;
            if (v != expect_v) begin
                if (bad < 6) $display("     不匹配 k=%0d got=%0d expect=%0d", k, v, expect_v);
                bad = bad + 1;
            end
        end
        $display("[tb_scope_trigger] A 触发对齐 (normal, rd_base=%0d)", base);
        $display("  缓冲 [rd_base..+639] 与触发相位不符的点数 = %0d (expect 0)", bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL 触发没有对准 ==> rd_base 未锁到触发点"); end

        // 再等一次捕获，确认 rd_base 对齐后内容仍然一致
        wait (dut.u_cap0.state == 2'd2);      // 离开 DONE，重新采集
        wait (dut.u_cap0.state == 2'd3);
        @(posedge clk); @(posedge clk);
        base = dut.rd_base0;
        bad = 0;
        for (k = 0; k < 640; k = k + 1) begin
            v = dut.u_ram0.mem[(base + k) & 1023];
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

        // ================= 判据 C: 滚动显示 =================
        sq_mode = 1'b0; ramp_mode = 1'b1;
        @(posedge clk); cfg_scr_we <= 1'b1; cfg_scr <= 1'b1;
        @(posedge clk); cfg_scr_we <= 1'b0;
        repeat (4000) @(posedge clk);

        s_left = 10'd0; s_right = 10'd0;
        while (s_left == 10'd0 || s_right == 10'd0) begin
            @(posedge clk);
            if (vga_de && dut.pix_ce) begin
                if (dut.px_d == 12'd1)   s_left  = dut.s0;
                if (dut.px_d == 12'd639) s_right = dut.s0;
            end
        end
        $display("[tb_scope_trigger] C 滚动显示: 最左列采样=%0d, 最右列采样=%0d", s_left, s_right);
        if (s_right <= s_left) begin errors=errors+1;
            $display("  FAIL 最右列不是最新采样（滚动基准不对）"); end

        if (errors == 0) $display("[tb_scope_trigger] PASS");
        else             $display("[tb_scope_trigger] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
