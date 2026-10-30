`timescale 1ns / 1ps
//=============================================================================
// tb_dump.v -- 把 vga_scope_top 的**真实输出像素**导出一帧，用于出图
//   波形源（plusarg 选择）:
//     （默认） 方波: 周期 90 采样点, 800/200
//     +saw     锯齿波: 周期 128, 0 -> 1016 (每点 +8)
//     +sine    正弦波: 周期 128, 查 sine.hex (128 项, 由 gen_sine.py 生成)
//   触发: single 模式，捕获完成后停在 DONE，缓冲冻结，保证导出的是同一幅完整画面
//=============================================================================
module tb_dump;
    localparam integer CLK_NS = 20;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [9:0] ch0_in = 10'd512;
    reg adc_valid = 1'b1, key_in = 1'b1;

    reg [6:0] sq_cnt = 7'd0;      // 方波 0..89
    reg [6:0] idx = 7'd0;         // 锯齿/正弦 0..127
    reg [2:0] wave_mode = 3'd0;   // 0=方波 1=锯齿 2=正弦
    reg [9:0] sine_tab [0:127];

    reg cfg_tb_we=0, cfg_ten_we=0, cfg_tmode_we=0;
    reg [15:0] cfg_tb=0;
    reg cfg_ten=0;
    reg [1:0] cfg_tmode=0;
    wire [11:0] vga_rgb;
    wire vga_hs, vga_vs, vga_de;

    vga_scope_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(1),
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224), .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10), .CLK_HZ(24_000_000),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) dut (
        .clk(clk), .rst(rst), .ch0_in(ch0_in), .ch1_in(10'd512),
        .adc_valid(adc_valid), .key_n(4'b1111), .sw_menu(1'b0), .sw_run(1'b1), .sw_page(1'b0), .sw_roll(1'b0),
        .cfg_tb_we(cfg_tb_we), .cfg_tb(cfg_tb),
        .cfg_run_we(1'b0), .cfg_run(1'b1),
        .cfg_ten_we(cfg_ten_we), .cfg_ten(cfg_ten),
        .cfg_lvl_we(1'b0), .cfg_lvl(10'd512),
        .cfg_edg_we(1'b0), .cfg_edg(1'b0),
        .cfg_scr_we(1'b0), .cfg_scr(1'b0),
        .cfg_tmode_we(cfg_tmode_we), .cfg_tmode(cfg_tmode),
        .cfg_tsrc_we(1'b0), .cfg_tsrc(1'b0),
        .cfg_pre_we(1'b0), .cfg_pre(10'd0),
        .cfg_hold_we(1'b0), .cfg_hold(16'd0),
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de)
    );

    always #(CLK_NS/2) clk = ~clk;

    always @(posedge clk) begin
        sq_cnt <= (sq_cnt == 7'd89) ? 7'd0 : (sq_cnt + 7'd1);
        idx    <= (idx == 7'd127) ? 7'd0 : (idx + 7'd1);
        case (wave_mode)
            3'd0: ch0_in <= (sq_cnt < 7'd45) ? 10'd800 : 10'd200;
            3'd1: ch0_in <= {idx, 3'b000};          // 0,8,...,1016
            3'd2: ch0_in <= sine_tab[idx];
            default: ch0_in <= 10'd512;
        endcase
    end

    integer fd, n, dumped;
    initial begin
        if ($test$plusargs("saw"))  wave_mode = 3'd1;
        if ($test$plusargs("sine")) wave_mode = 3'd2;
        if (wave_mode == 3'd2) $readmemh("sine.hex", sine_tab);

        fd = $fopen("frame.raw", "wb");
        repeat (5) @(posedge clk); rst = 0;
        @(posedge clk); cfg_tb_we <= 1; @(posedge clk); cfg_tb_we <= 0;
        @(posedge clk); cfg_ten_we <= 1; cfg_ten <= 1; @(posedge clk); cfg_ten_we <= 0;
        @(posedge clk); cfg_tmode_we <= 1; cfg_tmode <= 2'd2; @(posedge clk); cfg_tmode_we <= 0;

        wait (dut.u_cap0.state == 2'd3);   // single 模式: 完成后停住, 缓冲冻结
        @(posedge dut.frame);
        n = 0; dumped = 0;
        while (dumped < 640*480 && n < 3*420000) begin
            @(posedge clk);
            n = n + 1;
            if (vga_de && dut.pix_ce) begin
                $fwrite(fd, "%c%c", vga_rgb[7:0], {4'd0, vga_rgb[11:8]});
                dumped = dumped + 1;
            end
        end
        $fclose(fd);
        $display("[tb_dump] wave_mode=%0d 导出 %0d 像素", wave_mode, dumped);
        $finish;
    end
endmodule
