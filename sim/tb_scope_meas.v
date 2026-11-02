`timescale 1ns/1ps
//=============================================================================
// tb_scope_meas.v -- 波形测量（Vpp/Vmax/Vmin/Vmean/频率/占空比）自检
//   判据（一帧 = 256 个 tick，frame 脉冲后结果锁存）：
//     A) 交替 400/600 各 128 点 -> vmax=600 vmin=400 vpp=200 vmean=500
//        duty=50%(din>512 共 128 点) freq=128*60=7680（128 次上升穿越）
//     B) 恒定 512 -> vpp=0 vmean=512 freq=0
//=============================================================================
module tb_scope_meas;
    reg clk = 0, rst = 1;
    reg [9:0] din = 10'd512;
    reg tick = 1'b0, frame = 1'b0;
    wire [9:0]  vpp, vmax, vmin, vmean;
    wire [15:0] freq, period;
    wire [7:0]  duty;

    scope_meas dut(.clk(clk), .rst(rst), .din(din), .tick(tick), .frame(frame),
                   .vpp(vpp), .vmax(vmax), .vmin(vmin), .vmean(vmean),
                   .freq(freq), .period(period), .duty(duty));
    always #5 clk = ~clk;

    integer errors = 0, i;

    task push;
        input [9:0] v;
        begin
            din = v; tick = 1'b1; @(posedge clk); #1 tick = 1'b0; @(posedge clk);
        end
    endtask

    task do_frame;
        begin
            frame = 1'b1; @(posedge clk); #1 frame = 1'b0; @(posedge clk);
        end
    endtask

    initial begin
        $display("[tb_scope_meas] 波形测量");
        repeat (4) @(posedge clk); rst = 0;

        // ---- A) 交替 400/600 ----
        for (i = 0; i < 128; i = i + 1) begin push(10'd400); push(10'd600); end
        do_frame;
        $display("  A) vmax=%0d vmin=%0d vpp=%0d vmean=%0d duty=%0d freq=%0d",
                 vmax, vmin, vpp, vmean, duty, freq);
        $display("     (expect 600/400/200/500/50/7680)");
        if (vmax !== 10'd600)  begin errors=errors+1; $display("  FAIL vmax"); end
        if (vmin !== 10'd400)  begin errors=errors+1; $display("  FAIL vmin"); end
        if (vpp  !== 10'd200)  begin errors=errors+1; $display("  FAIL vpp"); end
        if (vmean!== 10'd500)  begin errors=errors+1; $display("  FAIL vmean"); end
        if (duty !== 8'd50)    begin errors=errors+1; $display("  FAIL duty"); end
        if (freq !== 16'd7680) begin errors=errors+1; $display("  FAIL freq(上升穿越次数)"); end

        // ---- B) 恒定 512 ----
        for (i = 0; i < 300; i = i + 1) push(10'd512);
        do_frame;
        $display("  B) vmax=%0d vmin=%0d vpp=%0d vmean=%0d duty=%0d freq=%0d",
                 vmax, vmin, vpp, vmean, duty, freq);
        $display("     (expect 512/512/0/512/0/0)");
        if (vmax !== 10'd512 || vmin !== 10'd512) begin errors=errors+1; $display("  FAIL 恒定值 max/min"); end
        if (vpp  !== 10'd0)   begin errors=errors+1; $display("  FAIL 恒定值 vpp 应为 0"); end
        if (vmean!== 10'd512) begin errors=errors+1; $display("  FAIL 恒定值 vmean"); end
        if (freq !== 16'd0)   begin errors=errors+1; $display("  FAIL 恒定值不应有上升穿越"); end

        // ---- C) 0..1023 满量程，检查 sum 不溢出（256*1023=261888 < 2^18）----
        for (i = 0; i < 256; i = i + 1) push(10'd1023);
        do_frame;
        $display("  C) 满量程 vmean=%0d (expect 1023，检查 18bit 累加不溢出) vpp=%0d", vmean, vpp);
        if (vmean !== 10'd1023) begin errors=errors+1; $display("  FAIL 满量程平均溢出"); end

        if (errors == 0) $display("[tb_scope_meas] PASS");
        else             $display("[tb_scope_meas] FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
