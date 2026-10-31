`timescale 1ns / 1ps
//=============================================================================
// tb_sparkroad_top.v -- 整机仿真：sparkroad_scope_top（就是出比特流的那个顶层）
//
// 组成: 24MHz clk(K14) + AD7606 串行模型 + VGA 640x480 + 数码管 + 串口收发
// 依赖: 无需 PLL（本顶层不例化 Gowin_PLL），也无需 FIFO
// 验证:
//   1) ADC 复位脉冲 / locked
//   2) 串口命令端到端: 发 "T0000\r" -> 顶层内部 cfg_tb 变为 0
//   3) CONVST 正常起振，采样流进入示波器
//   4) VGA 整帧: 307200 像素、网格/文字/波形齐全、波形随输入变化（不是一条死线）
//   5) 数码管位选在扫描（sel 多次变化）
//   6) 串口 TX 有输出（既有高也有低、有起始位下降沿）
//=============================================================================
module tb_sparkroad_top;

    // 24MHz: 41.666ns
    localparam integer CLK_HALF_PS = 20833;              // 20.833ns
    localparam real    BIT_NS      = 208 * 41.666;       // BAUD_CNT_MAX=208 个 24MHz 时钟

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg key = 1'b1;
    reg uart_rx = 1'b1;

    wire [7:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs, vga_clk;
    wire [7:0] seg;
    wire [3:0] sel;
    wire uart_tx;
    wire ad7606_convst, ad7606_cs_n, ad7606_sclk, ad7606_reset, ad7606_ser;
    wire ad7606_busy, ad7606_douta;

    sparkroad_scope_top #(.CLK_HZ(24_000_000), .TX_MODE(0)) dut (
        .clk(clk), .rst_n(rst_n), .key_l(key), .key_u(1'b1), .key_d(1'b1), .key_r(1'b1), .sw(6'b000000),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel),
        .ad7606_convst(ad7606_convst), .ad7606_busy(ad7606_busy),
        .ad7606_cs_n(ad7606_cs_n), .ad7606_sclk(ad7606_sclk),
        .ad7606_douta(ad7606_douta), .ad7606_reset(ad7606_reset),
        .ad7606_ser(ad7606_ser)
    );

    always #(CLK_HALF_PS/1000.0) clk = ~clk;   // 0.020833 us -> 20.833ns

    //---------- AD7606 模型：4 路都接同一个满量程斜坡 ----------
    // 满量程斜坡：每 1024 个时钟前进 128，因此每 ≈520 时钟一次的转换采样到约 +65，
    // 640 列（640 个采样点）约走过 0.6 个满量程 -> 屏幕上是一条缓锯齿
    reg [15:0] stim = 16'd0;
    reg [9:0]  stim_cnt = 10'd0;
    always @(posedge clk) begin
        stim_cnt <= stim_cnt + 10'd1;
        if (stim_cnt == 10'd1023) stim <= stim + 16'd128;
    end

    ad7606_model #(.CONV_CLK(10)) u_adc (
        .clk(clk), .rst(~rst_n), .convst(ad7606_convst), .cs_n(ad7606_cs_n),
        .sclk(ad7606_sclk), .adc_reset(ad7606_reset),
        .busy(ad7606_busy), .douta(ad7606_douta),
        .ch1(stim), .ch2(stim), .ch3(stim), .ch4(stim)
    );

    //---------- 观测 ----------
    integer n_convst = 0, n_convst_fall = 0, n_ser_hi = 0, rst_seen = 0;
    integer n_tx_fall = 0, tx_hi = 0, tx_lo = 0;
    integer n_sel_chg = 0;
    reg [3:0] sel_prev = 4'hF;

    integer n_we0 = 0, n_adcval = 0;
    always @(posedge clk) begin
        if (dut.u_scope.we0)    n_we0   = n_we0   + 1;
        if (dut.adc_valid)      n_adcval = n_adcval + 1;
    end
    always @(posedge ad7606_convst) n_convst = n_convst + 1;
    always @(posedge ad7606_reset)  rst_seen = 1;
    always @(posedge clk) begin
        if (ad7606_ser) n_ser_hi = n_ser_hi + 1;
        if (uart_tx) tx_hi = tx_hi + 1; else tx_lo = tx_lo + 1;
        if (sel != sel_prev) begin n_sel_chg = n_sel_chg + 1; sel_prev = sel; end
    end
    always @(negedge uart_tx) n_tx_fall = n_tx_fall + 1;

    // 帧捕获
    localparam [11:0] COL_BG=12'h012, COL_GRID=12'h151, COL_AXIS=12'h2A2,
                      COL_CH0=12'h1F1, COL_TEXT=12'hFFF;
    integer x_cnt=0, y_cnt=0, de_total=0, frame_captured=0;
    integer timeout = 0;
    reg cap_en = 1'b0;
    integer n_bg=0, n_grid=0, n_axis=0, n_ch0=0, n_ch1=0, n_text=0;
    integer ch0_ymin=99999, ch0_ymax=-1;
    reg [11:0] rgb12;

    integer dump_en = 0, fdd = 0;

    always @(posedge clk) begin
        rgb12 = {vga_r[7:4], vga_g[7:4], vga_b[7:4]};
        if (cap_en && dut.vga_de) begin
            if (dump_en) $fwrite(fdd, "%c%c", rgb12[7:0], {4'd0, rgb12[11:8]});
            de_total = de_total + 1;
            case (rgb12)
                COL_BG  : n_bg   = n_bg   + 1;
                COL_GRID: n_grid = n_grid + 1;
                COL_AXIS: n_axis = n_axis + 1;
                COL_CH0 : begin
                    n_ch0 = n_ch0 + 1;
                    if (y_cnt < ch0_ymin) ch0_ymin = y_cnt;
                    if (y_cnt > ch0_ymax) ch0_ymax = y_cnt;
                end
                12'hFF1 : n_ch1 = n_ch1 + 1;      // CH1 恒 512 -> y=223 的黄色平线
                COL_TEXT: n_text = n_text + 1;
                default : ;
            endcase
            if (x_cnt == 639) begin
                x_cnt = 0; y_cnt = y_cnt + 1;
                if (y_cnt == 480) frame_captured = 1;
            end
            else x_cnt = x_cnt + 1;
        end
    end

    //---------- 串口发送 ----------
    task send_byte(input [7:0] b);
        integer k;
        begin
            uart_rx = 1'b0;
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx = b[k];
                #(BIT_NS);
            end
            uart_rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    integer errors = 0, k;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_sparkroad_top.vcd");
            $dumpvars(0, tb_sparkroad_top);
        end

        if ($test$plusargs("dump")) begin
            fdd = $fopen("frame.raw", "wb");
            dump_en = 1;
            $display("[tb_sparkroad_top] 同时导出 frame.raw");
        end
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (3000) @(posedge clk);

        $display("[tb_sparkroad_top] 整机仿真");

        // 1) 串口命令 T0000 -> tb_div=0（快速采样）
        send_byte(8'h54); send_byte(8'h30); send_byte(8'h30);
        send_byte(8'h30); send_byte(8'h30); send_byte(8'h0D);
        repeat (500) @(posedge clk);
        $display("  串口命令 T0000 -> 顶层 cfg_tb = %0d (expect 0)", dut.cfg_tb);
        if (dut.cfg_tb !== 16'd0) begin errors=errors+1; $display("  FAIL 串口命令未生效"); end

        // 1b) 切换到单次模式(M2)，让 RAM 采满后冻结，便于检查波形
        send_byte(8'h4D); send_byte(8'h32); send_byte(8'h0D);
        repeat (200) @(posedge clk);
        timeout = 0;
        while ((dut.u_scope.u_cap0.state !== 2'd3) && (timeout < 2000000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        $display("  单次采集: state=%0d (等待 %0d 拍)", dut.u_scope.u_cap0.state, timeout);

        // 2) 等 ADC 起振
        repeat (6000) @(posedge clk);
        $display("  ADC: reset_seen=%0d convst脉冲=%0d locked=%0d ser恒高=%0d",
                 rst_seen, n_convst, dut.adc_locked, n_ser_hi);
        if (rst_seen == 0)          begin errors=errors+1; $display("  FAIL 没有 ADC 复位脉冲"); end
        if (n_convst < 3)           begin errors=errors+1; $display("  FAIL CONVST 没有起振"); end
        if (dut.adc_locked !== 1'b1)begin errors=errors+1; $display("  FAIL adc_locked"); end

        // 3) 抓一整帧 VGA
        @(posedge dut.u_scope.frame);
        x_cnt = 0; y_cnt = 0; de_total = 0; frame_captured = 0;
        n_bg=0; n_grid=0; n_axis=0; n_ch0=0; n_ch1=0; n_text=0;
        ch0_ymin=99999; ch0_ymax=-1;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;
        if (fdd) begin $fclose(fdd); fdd = 0; dump_en = 0; end

        $display("  VGA: de像素=%0d (expect 307200)", de_total);
        $display("       颜色 bg/grid/axis/ch0/ch1/text = %0d/%0d/%0d/%0d/%0d/%0d",
                 n_bg, n_grid, n_axis, n_ch0, n_ch1, n_text);
        $display("       CH0 波形行范围 %0d..%0d", ch0_ymin, ch0_ymax);
        $display("       [dbg] adc_valid=%0d we0=%0d state=%0d waddr=%0d rd_base=%0d run=%b trig_en=%b tmode=%0d tb=%0d",
                 n_adcval, n_we0, dut.u_scope.u_cap0.state, dut.u_scope.u_cap0.waddr,
                 dut.u_scope.rd_base0, dut.u_scope.run, dut.u_scope.trig_en,
                 dut.u_scope.trig_mode, dut.u_scope.tb_div);
        $display("       [dbg] mem[0]=%0d mem[100]=%0d mem[600]=%0d",
                 dut.u_scope.u_ram0.mem[0], dut.u_scope.u_ram0.mem[100], dut.u_scope.u_ram0.mem[600]);
        if (de_total != 307200)        begin errors=errors+1; $display("  FAIL 每帧像素数"); end
        if (n_grid == 0)               begin errors=errors+1; $display("  FAIL 没有网格"); end
        if (n_text == 0)               begin errors=errors+1; $display("  FAIL 没有文字"); end
        if (n_ch0  == 0)               begin errors=errors+1; $display("  FAIL 没有示波器波形"); end
        if ((ch0_ymax - ch0_ymin) < 50) begin errors=errors+1;
            $display("  FAIL 波形几乎是直线，ADC 数据没进来"); end

        // 4) 数码管扫描与串口发送
        $display("  数码管 sel 变化次数=%0d, 串口TX: 高=%0d 低=%0d 下降沿=%0d",
                 n_sel_chg, tx_hi, tx_lo, n_tx_fall);
        if (n_sel_chg < 10) begin errors=errors+1; $display("  FAIL 数码管没有扫描"); end
        if (tx_hi == 0 || tx_lo == 0) begin errors=errors+1; $display("  FAIL 串口 TX 没有翻转"); end
        if (n_tx_fall < 2)  begin errors=errors+1; $display("  FAIL 串口 TX 没有起始位"); end

        if (errors == 0) $display("[tb_sparkroad_top] PASS");
        else             $display("[tb_sparkroad_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule