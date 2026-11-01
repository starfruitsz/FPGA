`timescale 1ns/1ps
module tb_bpf_ctrl;
  reg clk=0, rst=1; reg [9:0] din=512;
  wire [9:0] dout; wire dvalid;
  reg [11:0] div=0; wire en; assign en=(div==12'd0);
  bpf_ctrl dut(.clk(clk),.rst(rst),.en(en),.din(din),.dout(dout),.dvalid(dvalid));
  always #19.841 clk=~clk;
  always @(posedge clk) div <= div + 12'd1;
  integer n=0, mx=0, mn=1023, hits=0; real ph, g;
  always @(posedge clk) if(!rst && en) begin
    ph = 6.2831853*48.0*n/6152.34;
    din <= 512 + $rtoi(47.0*$sin(ph)); n <= n + 1;
  end
  always @(posedge clk) #1 if (dvalid && n>2000) begin
    hits=hits+1; if(dout>mx) mx=dout; if(dout<mn) mn=dout;
  end
  initial begin repeat(8) @(posedge clk); rst=0; repeat(3000000) @(posedge clk);
    g = ((mx-mn)/2.0)/47.0;
    $display("  n=%0d hits=%0d mx=%0d mn=%0d amp=%0.2f gain=%0.3f", n, hits, mx, mn, (mx-mn)/2.0, g);
    if (g>0.85 && g<1.15) $display("  [tb_bpf_ctrl] PASS"); else $display("  [tb_bpf_ctrl] FAIL");
    $finish; end
endmodule
