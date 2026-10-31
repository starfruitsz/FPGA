`timescale 1ns / 1ps
//=============================================================================
// tb_bcd.v -- 验证 bcd.v 的 4 位 BCD 转换（P4 修复）
//   期望: 10bit 输入 0..1023 -> thou/hun/ten/unit 四位十进制
//   重点: 1000 与 1023 不再丢千位（修复前会得到 000 / 023）
//=============================================================================
module tb_bcd;

    reg         clk   = 1'b0;
    reg         rst_n = 1'b0;
    reg  [9:0]  data  = 10'd0;
    wire [3:0]  unit, ten, hun, thou;

    bcd dut (
        .clk(clk), .rst_n(rst_n), .data(data),
        .unit(unit), .ten(ten), .hun(hun), .thou(thou)
    );

    always #5 clk = ~clk;          // 100MHz，仿真用，不影响功能

    integer errors = 0;
    integer i;

    // 一次转换 24 拍，连续转换；改完 data 后等两轮确保重新装入
    task check_value(input [9:0] v);
        integer e_unit, e_ten, e_hun, e_thou;
        begin
            data = v;
            repeat (60) @(posedge clk);
            e_unit = v % 10;
            e_ten  = (v / 10) % 10;
            e_hun  = (v / 100) % 10;
            e_thou = (v / 1000) % 10;
            if ({thou,hun,ten,unit} !== {e_thou[3:0],e_hun[3:0],e_ten[3:0],e_unit[3:0]}) begin
                $display("  FAIL data=%0d : got %0d%0d%0d%0d, expect %0d%0d%0d%0d",
                         v, thou, hun, ten, unit, e_thou, e_hun, e_ten, e_unit);
                errors = errors + 1;
            end else begin
                $display("  ok   data=%4d -> %0d%0d%0d%0d", v, thou, hun, ten, unit);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_bcd.vcd");
        $dumpvars(0, tb_bcd);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        $display("[tb_bcd] 4 位 BCD 转换");
        check_value(10'd0);
        check_value(10'd9);
        check_value(10'd99);
        check_value(10'd512);
        check_value(10'd999);
        check_value(10'd1000);      // 修复前 -> 000
        check_value(10'd1023);      // 修复前 -> 023
        check_value(10'd1);

        if (errors == 0) $display("[tb_bcd] PASS");
        else             $display("[tb_bcd] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
