`timescale 1ns / 1ps
module tb_eso_dbg2;
    reg clk=0, rstn=0, en=0;
    reg signed [9:0] e_in = 10'sd0;
    wire signed [19:0] z1,z2,z3;
    wire signed [9:0] out_da;
    eso dut(.ad_clk(clk), .sys_rst_n(rstn), .en(en), .e_in(e_in), .u_out(out_da),
            .out_da(out_da), .c_flag(1'b0), .k_flag(1'b0), .c_date(12'd150), .k_date(12'd20),
            .z1k0(z1), .z2k0(z2), .z3k0(z3));
    always #10.4165 clk = ~clk;
    integer i;
    integer vmin=999999, vmax=-999999, vsum=0, cnt=0, v;
    initial begin
        repeat (5) @(negedge clk);
        rstn = 1'b1;
        e_in = -10'sd100;
        for (i=0;i<2400;i=i+1) begin
            @(negedge clk); en = 1'b1;
            @(negedge clk); en = 1'b0;
            @(posedge clk); #1;
            if (i > 2000) begin
                v = z1;
                if (v < vmin) vmin = v;
                if (v > vmax) vmax = v;
                vsum = vsum + v; cnt = cnt + 1;
            end
            repeat (6) @(negedge clk);
        end
        $display("window2000..2399: z1 min=%0d max=%0d avg=%0d (cnt=%0d)", vmin, vmax, vsum/cnt, cnt);
        $display("final z1=%0d z2=%0d z3=%0d out=%0d", z1, z2, z3, out_da);
        $finish;
    end
endmodule
