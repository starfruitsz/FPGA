`timescale 1ns / 1ps
//==============================================================================
// tb_func_gen: 验证内置函数发生器（4 波形 / 频率 / 幅度档）
//==============================================================================
module tb_func_gen;
    reg clk = 1'b0, rst = 1'b1;
    reg [1:0] wave = 2'd0;
    reg [2:0] fsel = 3'd3;      // 50Hz
    reg [1:0] asel = 2'd0;
    wire [9:0] data;
    wire valid;

    func_gen #(.CLK_HZ(12_000), .FS_HZ(12_000)) dut (
        .clk(clk), .rst(rst), .wave(wave), .freq_sel(fsel),
        .amp_sel(asel), .phase_idx(4'd0), .data(data), .valid(valid));

    always #5 clk = ~clk;   // DIV=1，每拍出一个采样点

    integer errors = 0;
    integer vmin, vmax, cnt;

    task measure;
        begin
            repeat (8) @(posedge clk);   // 让寄存器输出跟上新的波形/幅度设置
            vmin = 1023; vmax = 0; cnt = 0;
            repeat (600) begin
                @(posedge clk);
                if (valid) begin
                    cnt = cnt + 1;
                    if (data < vmin) vmin = data;
                    if (data > vmax) vmax = data;
                end
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst = 1'b0;

        wave = 2'd0; fsel = 3'd3; asel = 2'd0;      // 正弦 50Hz
        measure;
        $display("  sine  : min=%0d max=%0d n=%0d", vmin, vmax, cnt);
        if (vmin > 200 || vmax < 800) begin $display("  FAIL sine amplitude"); errors = errors + 1; end

        wave = 2'd1;                                 // 方波
        measure;
        $display("  square: min=%0d max=%0d", vmin, vmax);
        if (vmin > 200 || vmax < 800) begin $display("  FAIL square amplitude"); errors = errors + 1; end

        wave = 2'd2;                                 // 三角
        measure;
        $display("  tri   : min=%0d max=%0d", vmin, vmax);
        if (vmin > 250 || vmax < 750) begin $display("  FAIL triangle amplitude"); errors = errors + 1; end

        wave = 2'd3;                                 // 锯齿
        measure;
        $display("  saw   : min=%0d max=%0d", vmin, vmax);
        if (vmin > 250 || vmax < 750) begin $display("  FAIL sawtooth amplitude"); errors = errors + 1; end

        wave = 2'd0; asel = 2'd1;                    // 正弦 1/2 幅度
        measure;
        $display("  sine/2: min=%0d max=%0d", vmin, vmax);
        if (vmax - vmin > 500) begin $display("  FAIL amp halving"); errors = errors + 1; end

        if (errors == 0) $display("[tb_func_gen] PASS");
        else             $display("[tb_func_gen] FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
