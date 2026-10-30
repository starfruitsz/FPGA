`timescale 1ns / 1ps
//=============================================================================
// tb_vga_test_top.v -- 屏幕自检顶层 5 幅图案验证（此前未验证）
//
// 配置: PIX_DIV=1（压缩仿真时间）, AUTO_FRAMES=1（每帧换一幅图）
// 方法: 连续抓 5 帧，按"画面内容"分类而不是按顺序假定，最后要求 5 种画面全部出现。
//   mode0 彩条 : 8 色竖条，垂直方向恒定
//   mode1 灰阶 : R=G=B，按 py[8:6] 分 8 级
//   mode2 棋盘 : 只有黑白两色，各约一半
//   mode3 边框 : 四边白框 + 红十字 + 绿色移动方块
//   mode4 文字 : 背景 + 少量白色字模像素
//
// 注: PIX_DIV=1 时坐标类图案会整体右移 1 像素（与 vga_scope_top 同一流水线特性），
//     因此取样点都选在离图案边界 >2 像素的位置。
//=============================================================================
module tb_vga_test_top;

    localparam integer PIX_DIV = 1;
    localparam integer CLK_NS  = 20;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg key_in = 1'b1;

    wire [11:0] vga_rgb;
    wire vga_hs, vga_vs, vga_de;

    vga_test_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(PIX_DIV),
        .AUTO_FRAMES(1)
    ) dut (
        .clk(clk), .rst(rst), .key_in(key_in),
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de)
    );

    always #(CLK_NS/2) clk = ~clk;

    // 每帧统计与取样点
    integer x_cnt = 0, y_cnt = 0, frame_captured = 0;
    reg     cap_en = 1'b0;
    integer n_white = 0, n_black = 0;
    reg [11:0] s_b0, s_b1, s_b2, s_b3, s_b0v;
    reg [11:0] s_g0, s_g1, s_g2;
    reg [11:0] s_bord, s_cross;

    always @(posedge clk) begin
        if (cap_en && vga_de && dut.pix_ce) begin
            if (vga_rgb == 12'hFFF) n_white = n_white + 1;
            if (vga_rgb == 12'h000) n_black = n_black + 1;

            if (y_cnt == 100) begin
                if (x_cnt == 10)  s_b0  = vga_rgb;
                if (x_cnt == 74)  s_b1  = vga_rgb;
                if (x_cnt == 138) s_b2  = vga_rgb;
                if (x_cnt == 202) s_b3  = vga_rgb;
            end
            if (x_cnt == 10  && y_cnt == 300) s_b0v = vga_rgb;
            if (x_cnt == 300 && y_cnt == 10)  s_g0  = vga_rgb;
            if (x_cnt == 300 && y_cnt == 74)  s_g1  = vga_rgb;
            if (x_cnt == 300 && y_cnt == 138) s_g2  = vga_rgb;
            if (x_cnt == 2   && y_cnt == 2)   s_bord = vga_rgb;
            if (x_cnt == 319 && y_cnt == 239) s_cross = vga_rgb;

            if (x_cnt == 639) begin
                x_cnt = 0; y_cnt = y_cnt + 1;
                if (y_cnt == 480) frame_captured = 1;
            end
            else x_cnt = x_cnt + 1;
        end
    end

    integer seen [0:4];
    integer f, m, errors = 0;
    integer mode_det;

    task clear_frame;
        begin
            x_cnt = 0; y_cnt = 0; frame_captured = 0;
            n_white = 0; n_black = 0;
            s_b0 = 0; s_b1 = 0; s_b2 = 0; s_b3 = 0; s_b0v = 0;
            s_g0 = 0; s_g1 = 0; s_g2 = 0; s_bord = 0; s_cross = 0;
        end
    endtask

    initial begin
        for (m = 0; m < 5; m = m + 1) seen[m] = 0;
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_vga_test_top.vcd");
            $dumpvars(0, tb_vga_test_top);
        end

        repeat (8) @(posedge clk);
        rst = 1'b0;

        $display("[tb_vga_test_top] 连续抓 5 帧，按内容识别画面");

        for (f = 0; f < 5; f = f + 1) begin
            @(posedge dut.frame);
            clear_frame;
            cap_en <= 1'b1;
            wait (frame_captured);
            cap_en <= 1'b0;

            // 分类
            if (n_white > 140000 && n_black > 140000)              mode_det = 2;
            else if (s_b0==12'hFFF && s_b1==12'hFF0 && s_b2==12'h0FF && s_b3==12'h0F0
                     && s_b0v==s_b0)                               mode_det = 0;
            else if (s_g0==12'h000 && s_g1==12'h111 && s_g2==12'h222) mode_det = 1;
            else if (s_bord==12'hFFF && s_cross==12'hF00)          mode_det = 3;
            else if (n_white > 20 && n_white < 20000)              mode_det = 4;
            else                                                   mode_det = -1;

            $display("  帧%0d: white=%0d black=%0d -> 识别为 mode %0d", f, n_white, n_black, mode_det);
            if (mode_det >= 0 && mode_det <= 4) seen[mode_det] = seen[mode_det] + 1;
            else begin errors = errors + 1; $display("  FAIL 第 %0d 帧无法识别", f); end
        end

        $display("  画面统计: 彩条=%0d 灰阶=%0d 棋盘=%0d 边框=%0d 文字=%0d",
                 seen[0], seen[1], seen[2], seen[3], seen[4]);
        for (m = 0; m < 5; m = m + 1)
            if (seen[m] == 0) begin
                errors = errors + 1;
                $display("  FAIL 缺少 mode %0d 画面", m);
            end

        if (errors == 0) $display("[tb_vga_test_top] PASS");
        else             $display("[tb_vga_test_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
