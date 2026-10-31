`timescale 1ns / 1ps
// 临时诊断：验证"显示基准在 done 时锁存"——窗口内容跨帧应保持不变
module tb_demo_frames;
    reg clk = 1'b0, rst_n = 1'b0, key = 1'b1, uart_rx = 1'b1;
    wire [7:0] vga_r, vga_g, vga_b, seg;
    wire [3:0] sel;
    wire vga_hs, vga_vs, vga_clk, uart_tx;
    wire convst, cs_n, sclk, adc_rst, ser;

    sparkroad_scope_demo dut (
        .clk(clk), .rst_n(rst_n), .key_l(key), .key_u(1'b1), .key_d(1'b1), .key_r(1'b1),
        .sw(4'b0000), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel),
        .ad7606_convst(convst), .ad7606_busy(1'b0), .ad7606_cs_n(cs_n),
        .ad7606_sclk(sclk), .ad7606_douta(1'b0), .ad7606_reset(adc_rst),
        .ad7606_ser(ser)
    );

    always #20.833 clk = ~clk;   // 24MHz

    integer frames = 0, n_done = 0;
    reg [10:0] a0, a1, a2, a3;

    always @(posedge clk) begin
        if (dut.u_top.u_scope.frame) begin
            frames = frames + 1;
            a0 = {dut.u_top.u_scope.buf_disp0, (dut.u_top.u_scope.rd_base_d0 + 10'd0)};
            a1 = {dut.u_top.u_scope.buf_disp0, (dut.u_top.u_scope.rd_base_d0 + 10'd100)};
            a2 = {dut.u_top.u_scope.buf_disp0, (dut.u_top.u_scope.rd_base_d0 + 10'd300)};
            a3 = {dut.u_top.u_scope.buf_disp0, (dut.u_top.u_scope.rd_base_d0 + 10'd600)};
            $display("frame %0d: state=%0d dis=%b wr=%b rd_base=%0d base_d=%0d done=%0d  win=[%0d %0d %0d %0d]",
                frames, dut.u_top.u_scope.u_cap0.state,
                dut.u_top.u_scope.buf_disp0, dut.u_top.u_scope.buf_wr0,
                dut.u_top.u_scope.rd_base0, dut.u_top.u_scope.rd_base_d0, n_done,
                dut.u_top.u_scope.u_ram0.mem[a0], dut.u_top.u_scope.u_ram0.mem[a1],
                dut.u_top.u_scope.u_ram0.mem[a2], dut.u_top.u_scope.u_ram0.mem[a3]);
        end
        if (dut.u_top.u_scope.done0) n_done = n_done + 1;
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (500) @(posedge clk);
        repeat (5400000) @(posedge clk);
        $display("结束: frames=%0d done=%0d", frames, n_done);
        $finish;
    end
endmodule
