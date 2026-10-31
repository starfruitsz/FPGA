`timescale 1ns / 1ps
//=============================================================================
// tb_vga_timing.v -- 验证 vga_timing.v 的 640x480 时序
//   50MHz 系统时钟, PIX_DIV=2 => 25MHz 像素节拍
//   期望: 行 800 像素 = 32000ns, 行同步 96 像素 = 3840ns
//         场 525 行 = 16.8ms, 场同步 2 行 = 64000ns
//         de 每行 640 像素 = 25600ns
//=============================================================================
module tb_vga_timing;

    localparam integer PIX_DIV      = 2;
    localparam integer CLK_NS       = 20;              // 50MHz
    localparam integer PIX_NS       = CLK_NS * PIX_DIV; // 40ns/像素

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire pix_ce, hs, vs, de;
    wire [11:0] px, py;

    vga_timing #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0),   .V_POL(0),  .PIX_DIV(PIX_DIV)
    ) dut (
        .clk(clk), .rst(rst), .pix_ce(pix_ce),
        .hs(hs), .vs(vs), .de(de), .px(px), .py(py)
    );

    always #(CLK_NS/2) clk = ~clk;

    time    t_de1, t_de2, t_hs1, t_hs2, t_hs3, t_hs4, t_vs1, t_vs2, t_vs3;
    integer de_high, hs_period, hs_low, vs_low, vs_period;
    integer px_max = 0, py_max = 0;
    integer errors = 0;

    always @(posedge clk) begin
        if (px > px_max) px_max = px;
        if (py > py_max) py_max = py;
    end

    initial begin
        // 本用例跑满一整场（16.8ms@50MHz），全量 dump 会到 100MB+，默认关闭；
        // 需要波形时按: vvp ... +vcd
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_vga_timing.vcd");
            $dumpvars(0, tb_vga_timing);
        end
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // de 每行宽度
        @(negedge de); @(posedge de); t_de1 = $time;
        @(negedge de);                t_de2 = $time;
        de_high = t_de2 - t_de1;

        // 行同步周期与低电平宽度（H_POL=0 -> 同步期间 hs 为低）
        @(negedge hs); t_hs1 = $time;
        @(negedge hs); t_hs2 = $time;
        @(negedge hs); t_hs3 = $time;
        @(posedge hs); t_hs4 = $time;
        hs_period = t_hs3 - t_hs2;
        hs_low    = t_hs4 - t_hs3;

        // 场同步（V_POL=0 -> 同步期间 vs 为低）
        @(negedge vs); t_vs1 = $time;
        @(posedge vs); t_vs2 = $time;
        @(negedge vs); t_vs3 = $time;
        vs_low    = t_vs2 - t_vs1;
        vs_period = t_vs3 - t_vs1;

        $display("[tb_vga_timing] 640x480 PIX_DIV=%0d", PIX_DIV);
        $display("  de 每行 : %0d ns (expect 25600)", de_high);
        $display("  hs 周期 : %0d ns (expect 32000)", hs_period);
        $display("  hs 低宽 : %0d ns (expect 3840)",  hs_low);
        $display("  vs 低宽 : %0d ns (expect 64000)", vs_low);
        $display("  vs 周期 : %0d ns (expect 16800000)", vs_period);
        $display("  px_max  : %0d (expect 799)  py_max: %0d (expect 524)", px_max, py_max);

        if (de_high   != 25600)     begin errors=errors+1; $display("  FAIL de_high");   end
        if (hs_period != 32000)     begin errors=errors+1; $display("  FAIL hs_period"); end
        if (hs_low    != 3840)      begin errors=errors+1; $display("  FAIL hs_low");    end
        if (vs_low    != 64000)     begin errors=errors+1; $display("  FAIL vs_low");    end
        if (vs_period != 16800000)  begin errors=errors+1; $display("  FAIL vs_period"); end
        if (px_max    != 799)       begin errors=errors+1; $display("  FAIL px range");  end
        if (py_max    != 524)       begin errors=errors+1; $display("  FAIL py range");  end

        if (errors == 0) $display("[tb_vga_timing] PASS");
        else             $display("[tb_vga_timing] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
