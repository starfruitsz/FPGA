`timescale 1ns/1ps
//=============================================================================
// tb_bpf50.v -- 显示平滑滤波（一阶稳态卡尔曼）自检
//   判据：
//     1) filt_on=0 时直通：dout 必须等于 din
//     2) filt_on=1 时是"一阶低通"：阶跃后单调收敛，无过冲
//        tb_idx=0(adc_mode=1) K=55435/65536≈0.846，约 6 拍收敛到 ±1 码
//     3) 收敛后 dout 等于输入，不引入直流偏置（内部以 512 为零点）
//=============================================================================
module tb_bpf50;
    reg clk = 0, rst = 1, en = 0;
    reg filt_on = 1'b0;
    reg adc_mode = 1'b1;
    reg [3:0] tb_idx = 4'd0;
    reg [9:0] din = 10'd512;
    wire [9:0] dout;

    bpf50 dut(.clk(clk), .rst(rst), .en(en), .filt_on(filt_on),
              .adc_mode(adc_mode), .tb_idx(tb_idx), .din(din), .dout(dout));
    always #5 clk = ~clk;

    integer errors = 0, i, overshoot_hi = 0, overshoot_lo = 0;
    reg [9:0] got;

    task push;
        input [9:0] v;
        begin
            din = v; en = 1'b1; @(posedge clk); #1 en = 1'b0; @(posedge clk);
        end
    endtask

    initial begin
        $display("[tb_bpf50] 显示平滑滤波（卡尔曼）");
        repeat (4) @(posedge clk); rst = 0;

        // 1) 直通
        filt_on = 1'b0;
        push(10'd321); #1 got = dout;
        $display("  直通: din=321 dout=%0d (expect 321)", got);
        if (got !== 10'd321) begin errors=errors+1; $display("  FAIL filt_on=0 时没有直通"); end
        push(10'd888); #1 got = dout;
        if (got !== 10'd888) begin errors=errors+1; $display("  FAIL 直通第二点不对"); end

        // 2) 阶跃 512 -> 700，检查单调收敛、无过冲
        filt_on = 1'b1;
        for (i = 0; i < 4; i = i + 1) push(10'd512);
        overshoot_hi = 0; overshoot_lo = 0;
        for (i = 0; i < 30; i = i + 1) begin
            push(10'd700);
            #1;
            if (dout > 10'd700) overshoot_hi = overshoot_hi + 1;
            if (dout < 10'd512) overshoot_lo = overshoot_lo + 1;
        end
        #1 got = dout;
        $display("  阶跃 512->700 后 30 拍: dout=%0d (expect 700±1) 过冲上/下=%0d/%0d",
                 got, overshoot_hi, overshoot_lo);
        if (got < 10'd699 || got > 10'd701) begin errors=errors+1;
            $display("  FAIL 没有收敛到输入值"); end
        if (overshoot_hi != 0 || overshoot_lo != 0) begin errors=errors+1;
            $display("  FAIL 出现超调（一阶滤波器不该有过冲）"); end

        // 3) 反向阶跃 700 -> 400
        for (i = 0; i < 30; i = i + 1) push(10'd400);
        #1 got = dout;
        $display("  阶跃 700->400 后 30 拍: dout=%0d (expect 400±1)", got);
        if (got < 10'd399 || got > 10'd401) begin errors=errors+1;
            $display("  FAIL 反向阶跃没有收敛"); end

        // 4) 关掉滤波后应立刻直通（状态不影响输出）
        filt_on = 1'b0;
        push(10'd1023); #1 got = dout;
        $display("  重新直通: din=1023 dout=%0d (expect 1023)", got);
        if (got !== 10'd1023) begin errors=errors+1; $display("  FAIL 关滤波后没有立即直通"); end

        if (errors == 0) $display("[tb_bpf50] PASS");
        else             $display("[tb_bpf50] FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
