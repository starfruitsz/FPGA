`timescale 1ns/1ps
//=============================================================================
// tb_decim512.v -- 512 点累加抽取自检
//   判据：常数输入 512 个点后 dout 必须等于该常数；
//         交替 400/600 各 256 个点后 dout = 500（(256*400+256*600)>>9）；
//         dvalid 每 512 个采样正好 1 次。
//=============================================================================
module tb_decim512;
    reg clk = 0, rst = 1, en = 0;
    reg [9:0] din = 10'd0;
    wire [9:0] dout;
    wire dvalid;

    decim512 dut(.clk(clk), .rst(rst), .en(en), .din(din), .dout(dout), .dvalid(dvalid));
    always #5 clk = ~clk;

    integer errors = 0, i, n_dv = 0, got = -1, dv_cnt_phase = 0;
    // dvalid 与 dout 是同一拍的非阻塞赋值，观测必须晚一拍才能读到新 dout
    reg dv_d = 1'b0;
    always @(posedge clk) begin
        dv_d <= (!rst) && dvalid;
        if (dv_d) begin n_dv = n_dv + 1; got = dout; end
    end

    integer en_cnt = 0, clk_edges = 0;
    always @(posedge clk) begin
        clk_edges = clk_edges + 1;
        if (en) en_cnt = en_cnt + 1;
    end

    task push;
        input [9:0] v;
        begin
            // 注意：#1 必须在时钟沿之后再撤 en。否则 "沿后立刻拉低" 与
            // "always@(posedge) 采样 en" 处于同一时间步，谁先执行不确定，
            // 实测 Icarus 每次都让任务先跑 -> en 永远采不到（经典 TB 竞态）。
            din = v; en = 1'b1; @(posedge clk); #1 en = 1'b0; @(posedge clk);
        end
    endtask

    initial begin
        $display("[tb_decim512] 512 点累加抽取");
        repeat (4) @(posedge clk); rst = 0;

        // 阶段 1：常数 600
        n_dv = 0;
        for (i = 0; i < 512; i = i + 1) push(10'd600);
        repeat (2) @(posedge clk);
        $display("  dbg: t=%0t edges=%0d cnt=%0d acc=%0d rst=%b en=%b en_cnt=%0d",
                 $time, clk_edges, dut.cnt, dut.acc, rst, en, en_cnt);
        $display("  常数 600: dvalid 次数=%0d (expect 1) dout=%0d (expect 600)", n_dv, got);
        if (n_dv !== 1) begin errors = errors + 1; $display("  FAIL dvalid 次数不对"); end
        if (got !== 10'd600) begin errors = errors + 1; $display("  FAIL 常数值没有被平均回原值"); end

        // 阶段 2：交替 400/600（各 256 个）
        n_dv = 0; got = -1;
        for (i = 0; i < 256; i = i + 1) begin push(10'd400); push(10'd600); end
        repeat (2) @(posedge clk);
        $display("  交替 400/600: dvalid 次数=%0d (expect 1) dout=%0d (expect 500)", n_dv, got);
        if (n_dv !== 1) begin errors = errors + 1; $display("  FAIL dvalid 次数不对"); end
        if (got !== 10'd500) begin errors = errors + 1; $display("  FAIL 平均值不对"); end

        // 阶段 3：满量程 1023，检查 19bit 累加不溢出
        n_dv = 0; got = -1;
        for (i = 0; i < 512; i = i + 1) push(10'd1023);
        repeat (2) @(posedge clk);
        $display("  满量程 1023: dout=%0d (expect 1023，检查 19bit 累加不溢出)", got);
        if (got !== 10'd1023) begin errors = errors + 1; $display("  FAIL 满量程溢出"); end

        if (errors == 0) $display("[tb_decim512] PASS");
        else             $display("[tb_decim512] FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
