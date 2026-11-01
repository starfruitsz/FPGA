`timescale 1ns/1ps
module tb_decim;
  reg clk=0, rst=1, en=0; reg [9:0] din=512;
  wire [9:0] dout; wire dvalid;
  decim512 dut(.clk(clk),.rst(rst),.en(en),.din(din),.dout(dout),.dvalid(dvalid));
  always #19.841 clk=~clk;
  integer k, cnt=0, dv=0;
  always @(posedge clk) #1 if (dvalid) dv = dv + 1;
  initial begin
    repeat(6) @(posedge clk); rst=0;
    // 512 个 100 码 + 512 个 900 码，两个窗口
    for (k=0;k<512;k=k+1) begin @(posedge clk); en=1; din=10'd100; @(posedge clk); en=0; end
    repeat(4) @(posedge clk);
    for (k=0;k<512;k=k+1) begin @(posedge clk); en=1; din=10'd900; @(posedge clk); en=0; end
    repeat(8) @(posedge clk);
    $display("  dvalid 次数=%0d  dout=%0d (期望 100, 然后 900)", dv, dout);
    if (dv==2 && dout==900) $display("  [tb_decim] PASS"); else $display("  [tb_decim] FAIL");
    $finish;
  end
endmodule
