`timescale 1ns / 1ps
// 验证演示版能否走完 IDLE->ARMED->FILL->DONE 并冻结（跑到 3M 时钟）
module tb_demo_check;
    reg clk = 1'b0, rst_n = 1'b0, key = 1'b1, uart_rx = 1'b1;
    wire [7:0] vga_r, vga_g, vga_b, seg;
    wire [3:0] sel;
    wire vga_hs, vga_vs, vga_clk, uart_tx;
    wire convst, cs_n, sclk, adc_rst, ser;

    sparkroad_scope_demo dut (
        .clk(clk), .rst_n(rst_n), .key(key), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel),
        .ad7606_convst(convst), .ad7606_busy(1'b0), .ad7606_cs_n(cs_n),
        .ad7606_sclk(sclk), .ad7606_douta(1'b0), .ad7606_reset(adc_rst),
        .ad7606_ser(ser)
    );

    always #20.833 clk = ~clk;      // 24MHz

    reg [1:0] st_prev = 2'd3;
    integer n_we = 0;
    always @(posedge clk) begin
        if (dut.u_top.u_scope.u_cap0.state != st_prev) begin
            $display("  t=%0t clk=%0d  state %0d -> %0d   (we0=%b waddr=%0d post=%0d)",
                $time, $time/41666, st_prev, dut.u_top.u_scope.u_cap0.state,
                dut.u_top.u_scope.we0, dut.u_top.u_scope.u_cap0.waddr,
                dut.u_top.u_scope.u_cap0.post_cnt);
            st_prev = dut.u_top.u_scope.u_cap0.state;
        end
        if (dut.u_top.u_scope.we0) n_we = n_we + 1;
    end

    integer i;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (500) @(posedge clk);
        $display("配置: tb_div=%0d ten=%b tmode=%0d lvl=%0d boot_cnt=%0d",
            dut.u_top.u_scope.tb_div, dut.u_top.u_scope.trig_en,
            dut.u_top.u_scope.trig_mode, dut.u_top.u_scope.trig_level,
            dut.u_top.boot_cnt);

        repeat (3000000) @(posedge clk);
        $display("结束: state=%0d we0=%b 累计写次数=%0d",
            dut.u_top.u_scope.u_cap0.state, dut.u_top.u_scope.we0, n_we);
        if (dut.u_top.u_scope.u_cap0.state == 2'd3 && dut.u_top.u_scope.we0 === 1'b0)
            $display("[tb_demo_check] PASS 已冻结");
        else
            $display("[tb_demo_check] FAIL 未冻结");
        $finish;
    end
endmodule
