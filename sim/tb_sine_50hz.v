`timescale 1ns / 1ps
//=============================================================================
// tb_sine_50hz.v -- 内部 50Hz 正弦源验证
//   为缩短仿真时间，用等比例的时钟：CLK_HZ=240kHz（比 24MHz 快 100 倍），
//   FS/FREQ 保持 12kHz / 50Hz，因此 DIV=20、每周期 240 个采样点，行为完全一致。
//   检查:
//     1) valid 间隔 = DIV 个时钟
//     2) 一个信号周期恰好 240 个采样点（sample[240] 回到 sample[0]）
//     3) 幅度范围 = 112..912（中心 512、幅度 400）
//=============================================================================
module tb_sine_50hz;

    localparam integer CLK_HZ = 240_000;
    localparam integer FS     = 12_000;
    localparam integer FREQ   = 50;
    localparam integer DIV    = CLK_HZ / FS;      // 20

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    wire [9:0] data;
    wire       valid;

    sine_50hz #(.CLK_HZ(CLK_HZ), .FS_HZ(FS), .FREQ_HZ(FREQ)) dut (
        .clk(clk), .rst(rst), .data(data), .valid(valid)
    );

    always #10 clk = ~clk;      // 50MHz 仿真时钟，与 DIV 无关（只需比 DIV 快）

    integer errors = 0;
    integer n = 0, clk_cnt = 0, period = 0, last_edge = -1;
    integer vmin = 9999, vmax = 0;      // 注意: 不能用 -1 初始化，无符号比较会永远为假
    integer first_val = -1, val_240 = -1;

    always @(posedge clk) begin
        clk_cnt = clk_cnt + 1;
        if (valid) begin
            if (last_edge >= 0) period = clk_cnt - last_edge;
            last_edge = clk_cnt;
            if (n == 0)  first_val = data;
            if (n == 240) val_240 = data;
            if (data < vmin) vmin = data;
            if (data > vmax) vmax = data;
            n = n + 1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst = 1'b0;

        wait (n > 241);

        $display("[tb_sine_50hz] DIV=%0d (expect %0d)", period, DIV);
        $display("  采样点数/周期: 240 点, sample[0]=%0d sample[240]=%0d", first_val, val_240);
        $display("  幅度范围: %0d..%0d (expect 112..912)", vmin, vmax);

        if (period != DIV) begin errors=errors+1; $display("  FAIL valid 间隔"); end
        // 一个周期是 240.001 个采样点，240 点会差 1 个点（约 10LSB），允许 20LSB
        if ((val_240 - first_val > 20) || (first_val - val_240 > 20)) begin
            errors=errors+1; $display("  FAIL 240 点没有回到周期起点"); end
        if (vmin < 108 || vmin > 118) begin errors=errors+1; $display("  FAIL 最小值"); end
        if (vmax < 906 || vmax > 916) begin errors=errors+1; $display("  FAIL 最大值"); end

        if (errors == 0) $display("[tb_sine_50hz] PASS");
        else             $display("[tb_sine_50hz] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
