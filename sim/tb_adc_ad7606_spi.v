`timescale 1ns / 1ps
//=============================================================================
// tb_adc_ad7606_spi.v -- 验证 AD7606 串行驱动（此前完全没有验证过的环节）
//   接 ad7606_model，检查：
//     1) 上电复位后 adc_reset 脉冲 + locked=1
//     2) CONVST 高电平宽度 = CONV_CYC(8) 个 clk
//     3) CS 低电平期间 SCLK 下降沿正好 64 个
//     4) 4 路 16bit 补码被正确还原（含负数与边界值），r_ch 依次 0,1,2,3
//=============================================================================
module tb_adc_ad7606_spi;

    localparam integer CONV_CYC = 8;
    localparam integer RST_CYC  = 200;
    localparam integer SDIV     = 2;         // SCLK 半周期 = 2 clk

    reg         clk   = 1'b0;
    reg         rst   = 1'b1;
    reg         enable = 1'b1;
    reg  [15:0] rate   = 16'd0;              // 连续转换
    reg  [15:0] sdiv   = SDIV;
    reg  [2:0]  os_sel = 3'd0;
    reg         range_sel = 1'b1;

    wire        convst, cs_n, sclk, adc_reset, ser, stby, range;
    wire [2:0]  os;
    wire        busy, douta;
    wire [15:0] r_data;
    wire [1:0]  r_ch;
    wire        r_valid, locked, error;

    // 被测设计
    adc_ad7606_spi #(.RW(16), .CONV_CYC(CONV_CYC), .RST_CYC(RST_CYC)) dut (
        .clk(clk), .rst(rst), .enable(enable), .rate(rate), .sdiv(sdiv),
        .os_sel(os_sel), .range_sel(range_sel),
        .convst(convst), .cs_n(cs_n), .sclk(sclk), .douta(douta),
        .adc_reset(adc_reset), .ser(ser), .os(os), .range(range), .stby(stby),
        .busy(busy),
        .r_data(r_data), .r_ch(r_ch), .r_valid(r_valid), .r_ready(1'b1),
        .locked(locked), .error(error)
    );

    // 器件模型：故意选能暴露位序错误的值
    localparam [15:0] CH1 = 16'h1234;   // 正
    localparam [15:0] CH2 = 16'hEDCC;   // 负
    localparam [15:0] CH3 = 16'h0001;   // 最小正
    localparam [15:0] CH4 = 16'h8000;   // 最小负

    ad7606_model #(.CONV_CLK(60)) u_adc (
        .clk(clk), .rst(rst), .convst(convst), .cs_n(cs_n), .sclk(sclk),
        .adc_reset(adc_reset), .busy(busy), .douta(douta),
        .ch1(CH1), .ch2(CH2), .ch3(CH3), .ch4(CH4)
    );

    always #10 clk = ~clk;                   // 50MHz

    // ---------- 观测 ----------
    reg [15:0] got_data [0:3];
    reg [1:0]  got_ch   [0:3];
    integer n_valid = 0;
    integer errors  = 0;

    time t_conv_rise = 0, t_conv_fall = 0;
    time t_cs_fall = 0, t_cs_rise = 0;
    integer sclk_fall_in_cs = 0;
    integer convst_width, cs_low_width;
    reg     reset_seen = 1'b0;
    time    t_rst_rise = 0, t_rst_fall = 0;

    always @(posedge clk) begin
        if (r_valid) begin
            if (n_valid < 4) begin
                got_data[n_valid] = r_data;
                got_ch[n_valid]   = r_ch;
            end
            n_valid = n_valid + 1;
        end
    end

    always @(posedge adc_reset) begin t_rst_rise = $time; reset_seen = 1'b1; end
    always @(negedge adc_reset) t_rst_fall = $time;
    always @(posedge convst) t_conv_rise = $time;
    always @(negedge convst) t_conv_fall = $time;
    always @(negedge cs_n) begin t_cs_fall = $time; sclk_fall_in_cs = 0; end
    always @(posedge cs_n) t_cs_rise = $time;
    always @(negedge sclk) if (!cs_n) sclk_fall_in_cs = sclk_fall_in_cs + 1;

    integer i;

    initial begin
        $dumpfile("tb_adc_ad7606_spi.vcd");
        $dumpvars(0, tb_adc_ad7606_spi);

        repeat (5) @(posedge clk);
        rst = 1'b0;

        // 等待第一帧采完 4 个通道
        i = 0;
        while ((n_valid < 4) && (i < 8000)) begin
            @(posedge clk);
            i = i + 1;
        end

        convst_width = t_conv_fall - t_conv_rise;
        cs_low_width = t_cs_rise - t_cs_fall;

        $display("[tb_adc_ad7606_spi] AD7606 串行驱动");
        // 注意：CONVST 与 CS 低电平都比“名义参数”多 1 个 clk，这是 FSM 打拍导致的：
        //   S_IDLE 装载 conv_cnt=CONV_CYC 并拉高 -> 再数 CONV_CYC 次才清零拉低 = CONV_CYC+1 拍
        //   第 64 位在上升沿采到后 state<=S_END，下一拍 S_END 才把 cs_n 拉高 = 64*2*sdiv+1 拍
        $display("  adc_reset 脉冲   : %0d ns (>= %0d ns 即可)", t_rst_fall - t_rst_rise, RST_CYC*20);
        $display("  locked / error   : %b / %b (expect 1 / 0)", locked, error);
        $display("  CONVST 高宽度    : %0d ns (expect %0d ns = (CONV_CYC+1)*20)", convst_width, (CONV_CYC+1)*20);
        $display("  CS 低宽度        : %0d ns (expect %0d ns = (64*2*SDIV+1)*20)", cs_low_width, (64*2*SDIV+1)*20);
        $display("  CS 内 SCLK 下降沿: %0d 个 (expect 64)", sclk_fall_in_cs);
        $display("  收到 r_valid     : %0d 个 (expect >=4)", n_valid);
        for (i = 0; i < 4; i = i + 1)
            $display("    ch%0d: r_data=0x%04X r_ch=%0d (expect 0x%04X / %0d)",
                     i, got_data[i], got_ch[i],
                     (i==0)?CH1:(i==1)?CH2:(i==2)?CH3:CH4, i);

        if (!reset_seen)                       begin errors=errors+1; $display("  FAIL 没有复位脉冲"); end
        if (((t_rst_fall - t_rst_rise) < RST_CYC*20) || ((t_rst_fall - t_rst_rise) > (RST_CYC+8)*20))
                                               begin errors=errors+1; $display("  FAIL RESET 宽度"); end
        if (locked !== 1'b1)                   begin errors=errors+1; $display("  FAIL locked"); end
        if (error  !== 1'b0)                   begin errors=errors+1; $display("  FAIL error 置位"); end
        if (convst_width != (CONV_CYC+1)*20)      begin errors=errors+1; $display("  FAIL CONVST 宽度"); end
        if (cs_low_width != (64*2*SDIV+1)*20)     begin errors=errors+1; $display("  FAIL CS 低宽度"); end
        if (sclk_fall_in_cs != 64)             begin errors=errors+1; $display("  FAIL SCLK 个数"); end
        if (n_valid < 4)                       begin errors=errors+1; $display("  FAIL 采样流不足"); end
        if (got_data[0] !== CH1 || got_ch[0] !== 2'd0) begin errors=errors+1; $display("  FAIL ch0 数据"); end
        if (got_data[1] !== CH2 || got_ch[1] !== 2'd1) begin errors=errors+1; $display("  FAIL ch1 数据"); end
        if (got_data[2] !== CH3 || got_ch[2] !== 2'd2) begin errors=errors+1; $display("  FAIL ch2 数据"); end
        if (got_data[3] !== CH4 || got_ch[3] !== 2'd3) begin errors=errors+1; $display("  FAIL ch3 数据"); end

        if (errors == 0) $display("[tb_adc_ad7606_spi] PASS");
        else             $display("[tb_adc_ad7606_spi] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
