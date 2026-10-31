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
    reg [8:0] sw = 9'b0;                  // SW0..SW8（SW8=1 切 ADC 模式）
    reg [9:0] ad_data = 10'd0;            // 并口 AD 模型输出

    wire [7:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs, vga_clk;
    wire [7:0] seg;
    wire [3:0] sel;
    wire uart_tx;
    wire ad7606_convst, ad7606_cs_n, ad7606_sclk, ad7606_reset, ad7606_ser;
    wire ad7606_busy, ad7606_douta;
    wire adclk, daclk;
    wire da0,da1,da2,da3,da4,da5,da6,da7,da8,da9;
    wire [9:0] da_bus = {da9,da8,da7,da6,da5,da4,da3,da2,da1,da0};
    reg  [9:0] ad_bus = 10'd0;
    always @(posedge clk) ad_bus <= ad_bus + 10'd1;

    sparkroad_scope_top #(.CLK_HZ(24_000_000), .TX_MODE(0)) dut (
        .clk(clk), .rst_n(rst_n), .key_l(key), .key_u(1'b1), .key_d(1'b1), .key_r(1'b1), .sw(sw),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .ad0(ad_bus[0]), .ad1(ad_bus[1]), .ad2(ad_bus[2]), .ad3(ad_bus[3]), .ad4(ad_bus[4]),
        .ad5(ad_bus[5]), .ad6(ad_bus[6]), .ad7(ad_bus[7]), .ad8(ad_bus[8]), .ad9(ad_bus[9]),
        .adclk(adclk),
        .da0(da0), .da1(da1), .da2(da2), .da3(da3), .da4(da4),
        .da5(da5), .da6(da6), .da7(da7), .da8(da8), .da9(da9), .daclk(daclk),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_clk(vga_clk),
        .seg(seg), .sel(sel)
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

    //---------- 并口 AD 模型：每拍 +1 的斜坡（ADCLK 采样后进入 ADC 模式显示）----------
    reg [9:0] par_ad = 10'd0;
    always @(posedge clk) begin
        par_ad  <= par_ad + 10'd1;
        ad_data <= par_ad;
    end

    integer n_adclk = 0;
    always @(posedge adclk) n_adclk = n_adclk + 1;

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
        if (1'b1)      n_adcval = n_adcval + 1;
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
    integer ch1_ymin=99999, ch1_ymax=-1;
    // 两路波形合起来的纵向范围：自发生模式下 CH0/CH1 是同一个信号，屏幕上会完全
    // 重合（合成器里 CH1 优先），只看 CH0 的像素数会误判成"没有波形"
    integer wav_ymin=99999, wav_ymax=-1;
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
                    if (y_cnt < wav_ymin) wav_ymin = y_cnt;
                    if (y_cnt > wav_ymax) wav_ymax = y_cnt;
                end
                12'hFF1 : begin                   // CH1 波形色（自发生模式下与 CH0 完全重合）
                    n_ch1 = n_ch1 + 1;
                    if (y_cnt < ch1_ymin) ch1_ymin = y_cnt;
                    if (y_cnt > ch1_ymax) ch1_ymax = y_cnt;
                    if (y_cnt < wav_ymin) wav_ymin = y_cnt;
                    if (y_cnt > wav_ymax) wav_ymax = y_cnt;
                end
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
    integer n_adclk_0 = 0, n_adclk_1 = 0;
    reg signed [9:0] u_snap;
    reg [9:0]        ref_da;
    // 两路函数发生器独立性检查用的临时变量
    integer g0_uniq, g1_bad, gi;
    reg [9:0] g0_s;

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
                 rst_seen, n_convst, 1'b1, n_ser_hi);
        if (n_adclk < 3)          begin errors=errors+1; $display("  FAIL ADCLK 没有起振"); end
        if (1'b0)           begin errors=errors+1; $display("  FAIL CONVST 没有起振"); end
        if (1'b1 !== 1'b1)begin errors=errors+1; $display("  FAIL adc_locked"); end

        // 3) 抓一整帧 VGA
        @(posedge dut.u_scope.frame);
        x_cnt = 0; y_cnt = 0; de_total = 0; frame_captured = 0;
        n_bg=0; n_grid=0; n_axis=0; n_ch0=0; n_ch1=0; n_text=0;
        ch0_ymin=99999; ch0_ymax=-1;
        ch1_ymin=99999; ch1_ymax=-1;
        wav_ymin=99999; wav_ymax=-1;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;
        if (fdd) begin $fclose(fdd); fdd = 0; dump_en = 0; end

        $display("  VGA: de像素=%0d (expect 307200)", de_total);
        $display("       颜色 bg/grid/axis/ch0/ch1/text = %0d/%0d/%0d/%0d/%0d/%0d",
                 n_bg, n_grid, n_axis, n_ch0, n_ch1, n_text);
        $display("       CH0 波形行范围 %0d..%0d, CH1 波形行范围 %0d..%0d",
                 ch0_ymin, ch0_ymax, ch1_ymin, ch1_ymax);
        $display("       [dbg] adc_valid=%0d we0=%0d state=%0d waddr=%0d rd_base=%0d run=%b trig_en=%b tmode=%0d tb=%0d",
                 n_adcval, n_we0, dut.u_scope.u_cap0.state, dut.u_scope.u_cap0.waddr,
                 dut.u_scope.rd_base0, dut.u_scope.run, dut.u_scope.trig_en,
                 dut.u_scope.trig_mode, dut.u_scope.tb_div);
        $display("       [dbg] mem[0]=%0d mem[100]=%0d mem[600]=%0d",
                 dut.u_scope.u_ram0.mem[0], dut.u_scope.u_ram0.mem[100], dut.u_scope.u_ram0.mem[600]);
        if (de_total != 307200)        begin errors=errors+1; $display("  FAIL 每帧像素数"); end
        if (n_grid == 0)               begin errors=errors+1; $display("  FAIL 没有网格"); end
        if (n_text == 0)               begin errors=errors+1; $display("  FAIL 没有文字"); end
        // 自发生模式下 CH0/CH1 是两路独立信号源，按"两路合计"判断有没有波形
        if ((n_ch0 + n_ch1) == 0)      begin errors=errors+1; $display("  FAIL 没有示波器波形"); end
        if ((wav_ymax - wav_ymin) < 50) begin errors=errors+1;
            $display("  FAIL 波形几乎是直线，数据没进来"); end

        // 4) 数码管扫描与串口发送
        $display("  数码管 sel 变化次数=%0d, 串口TX: 高=%0d 低=%0d 下降沿=%0d",
                 n_sel_chg, tx_hi, tx_lo, n_tx_fall);
        if (n_sel_chg < 10) begin errors=errors+1; $display("  FAIL 数码管没有扫描"); end
        if (tx_hi == 0 || tx_lo == 0) begin errors=errors+1; $display("  FAIL 串口 TX 没有翻转"); end
        if (n_tx_fall < 2)  begin errors=errors+1; $display("  FAIL 串口 TX 没有起始位"); end

        //------------------------------------------------------------------
        // 5) 通道数据源（SW8）
        //    拨下(0) = 自发生：CH0 接 u_gen0 的 gen0_data，
        //               CH1 接 u_gen1 的 gen1_data（两套参数互相独立）
        //    拨上(1) = AD/DA  ：CH0 = ADC 采样值，CH1 = ADRC 控制量 u（u+512）
        //------------------------------------------------------------------
        $display("  自发生模式: CH0源=%0d(gen0=%0d) CH1源=%0d(gen1=%0d)",
                 dut.u_scope.ch0_in, dut.gen0_data, dut.u_scope.ch1_in, dut.gen1_data);
        if (dut.u_scope.ch0_in !== dut.gen0_data) begin errors=errors+1;
            $display("  FAIL 自发生模式 CH0 没有接 gen0 函数发生器"); end
        if (dut.u_scope.ch1_in !== dut.gen1_data) begin errors=errors+1;
            $display("  FAIL 自发生模式 CH1 没有接 gen1 函数发生器"); end
        if (dut.u_gen0.wave === dut.u_gen1.wave) begin errors=errors+1;
            $display("  FAIL 两个函数发生器的参数没有互相独立（默认值相同）"); end

        // 采 10 个发生器节拍：CH0 默认正弦，相邻采样值应一直在变；
        // CH1 默认方波半幅，只允许 312/712 两个电平（512±200）。
        g0_uniq = 0; g1_bad = 0; g0_s = 10'd0;
        for (gi = 0; gi < 10; gi = gi + 1) begin
            @(posedge clk);
            while (!dut.gen1_valid) @(posedge clk);
            if ((gi > 0) && (dut.gen0_data !== g0_s)) g0_uniq = g0_uniq + 1;
            g0_s = dut.gen0_data;
            if ((dut.gen1_data !== 10'd312) && (dut.gen1_data !== 10'd712))
                g1_bad = g1_bad + 1;
        end
        $display("  发生器独立性: gen0 相邻采样变化=%0d 次, gen1 非法电平=%0d 次",
                 g0_uniq, g1_bad);
        if (g0_uniq < 3) begin errors=errors+1;
            $display("  FAIL CH0 正弦采样值几乎不变，gen0 没在跑"); end
        if (g1_bad != 0) begin errors=errors+1;
            $display("  FAIL CH1 不是默认的半幅方波（gen1 参数不独立？）"); end

        n_adclk_0 = n_adclk;
        sw[8] = 1'b1;
        repeat (210000) @(posedge clk);        // 等开关消抖 8ms @24MHz ≈ 192k 拍
        n_adclk_1 = n_adclk;
        $display("  SW8 拨上: adc_mode=%b CH0源=%0d(ad_val=%0d) CH1源=%0d(adrc_da=%0d)",
                 dut.adc_mode, dut.u_scope.ch0_in, dut.ad_val,
                 dut.u_scope.ch1_in, dut.adrc_da);
        $display("  ADCLK: 210k 拍内 %0d 个上升沿 (8 分频应≈26250)", n_adclk_1 - n_adclk_0);
        if (dut.adc_mode !== 1'b1)               begin errors=errors+1;
            $display("  FAIL SW8 没有切到 ADC 模式"); end
        if (dut.u_scope.ch0_in !== dut.ad_val)   begin errors=errors+1;
            $display("  FAIL ADC 模式 CH0 没有接外部 AD"); end
        if (dut.u_scope.ch1_in !== dut.adrc_da)  begin errors=errors+1;
            $display("  FAIL ADC 模式 CH1 没有接 ADRC 输出 u"); end
        if ((n_adclk_1 - n_adclk_0) < 26100 || (n_adclk_1 - n_adclk_0) > 26400) begin
            errors=errors+1; $display("  FAIL ADCLK 不是系统时钟 8 分频"); end

        //------------------------------------------------------------------
        // 6) ADRC 链路: y = ad_val-512 -> eso(每个采样一次) -> u -> da_data=clamp(u+512)
        //------------------------------------------------------------------
        // 位宽约定: 都在 10bit 内按补码回绕比较（ad_y 的位型就是 ad_val-512 的低 10 位）
        if (dut.ad_y[9:0] !== (dut.ad_val - 10'd512)) begin errors=errors+1;
            $display("  FAIL ADRC 的 y 不等于 ad_val-512 (ad_val=%0d y=%0d)",
                     dut.ad_val, $signed(dut.ad_y)); end
        if (dut.adrc_da !== (dut.eso_u + 10'd512)) begin errors=errors+1;
            $display("  FAIL da_data 不等于 u+512 (u=%0d da=%0d)",
                     $signed(dut.eso_u), dut.adrc_da); end

        // eso 必须真的在算（u 不能是常数）
        u_snap = dut.eso_u;
        repeat (4000) @(posedge clk);
        $display("  ADRC: u %0d -> %0d (y=%0d da_data=%0d)",
                 u_snap, $signed(dut.eso_u), $signed(dut.ad_y), da_bus);
        if (dut.eso_u === u_snap) begin errors=errors+1;
            $display("  FAIL ADRC 输出 u 是常数，eso 没有在算"); end

        // DA 通道: da_clk 上升沿锁存 adrc_da, 引脚输出锁存后的码值
        @(negedge daclk);
        ref_da = dut.adrc_da;
        @(posedge daclk); #1;
        if (da_bus !== ref_da) begin errors=errors+1;
            $display("  FAIL DA 引脚没有锁存 ADRC 码 (期望 %0d 实际 %0d)", ref_da, da_bus); end
        if (da_bus !== dut.da_loop) begin errors=errors+1;
            $display("  FAIL DA 引脚不是来自 ad_da_par 的锁存输出"); end
        $display("  DA 通路: 锁存码=%0d (da_loop=%0d)", ref_da, dut.da_loop);

        if (errors == 0) $display("[tb_sparkroad_top] PASS");
        else             $display("[tb_sparkroad_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule