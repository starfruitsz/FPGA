`timescale 1ns / 1ps
// 演示顶层 + SW4 自动量程：逐帧观察自动档位/中点/居中偏移
module tb_demo_auto;
    reg clk = 1'b0, rst_n = 1'b0, key = 1'b1, uart_rx = 1'b1;
    wire [7:0] vga_r, vga_g, vga_b, seg;
    wire [3:0] sel;
    wire vga_hs, vga_vs, vga_clk, uart_tx;
    wire convst, cs_n, sclk, adc_rst, ser;

    sparkroad_scope_demo dut (
        .clk(clk), .rst_n(rst_n), .key_l(key), .key_u(1'b1), .key_d(1'b1), .key_r(1'b1),
        .sw(6'b110000), .uart_tx(uart_tx), .uart_rx(uart_rx),   // SW5=1 非滚动, SW4=1 自动, SW1=0 运行
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel),
        .ad7606_convst(convst), .ad7606_busy(1'b0), .ad7606_cs_n(cs_n),
        .ad7606_sclk(sclk), .ad7606_douta(1'b0), .ad7606_reset(adc_rst),
        .ad7606_ser(ser)
    );
    always #20.833 clk = ~clk;

    integer frames = 0;
    always @(posedge clk) begin
        if (dut.u_top.u_scope.frame) begin
            frames = frames + 1;
            $display("frame %0d: vs_auto=%0d mid0=%0d mid1=%0d vsc0_eff=%0d fine0=%0d fine1=%0d voff0=%0d voff1=%0d run=%b scroll=%b st=%0d",
                frames,
                dut.u_top.u_scope.u_auto.vs_out,
                dut.u_top.u_scope.u_auto.mid_out0,
                dut.u_top.u_scope.u_auto.mid_out1,
                dut.u_top.u_scope.vsc0_eff,
                dut.u_top.u_scope.fine0,
                dut.u_top.u_scope.fine1,
                dut.u_top.u_scope.voff0,
                dut.u_top.u_scope.voff1,
                dut.u_top.u_scope.run,
                dut.u_top.u_scope.scroll_en,
                dut.u_top.u_scope.u_cap0.state);
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (4000000) @(posedge clk);
        $display("结束 frames=%0d", frames);
        $finish;
    end
endmodule
