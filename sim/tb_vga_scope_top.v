`timescale 1ns / 1ps
//=============================================================================
// tb_vga_scope_top.v -- vga_scope_top 整屏仿真（此前完全没有验证过）
//
// 配置: 640x480, PIX_DIV=1 (SparkRoad 实际配置, 像素时钟=系统时钟), 帧周期 800x525 clk
//
// 场景 0: SW4 自动量程（两路同时进屏）
//   CH0 = 100/700 方波(中点 400, 峰值 412)，CH1 = 700/900 方波(中点 800, 峰值 388)
//   档位按 max(peak0,peak1)=412 选 vs=4；两路各自居中后
//   CH0 占 y=92..355、CH1 占 y=180..267，必须同时完整落在 0..447 内
//   同时检查: 两通道档位一致、自动量程不改 ch0_en/ch1_en
// 场景 A: CH0 恒定 512, CH1 恒定 300
//   - 电平 512 -> y = 447-(512*7>>4) = 223，波形应是一条水平直线
//   - 电平 300 -> y = 447-(300*7>>4) = 316
//   - 检查: y=223 整行(除 x=0)都是 COL_CH0；y=224 整行都是 COL_AXIS
// 场景 B: CH0 改成每拍 +1 的斜坡
//   - 检查: 波形纵向铺开(ymax-ymin>200)，证明 y 映射与竖线连接工作
// 场景 D: 两路不同幅度（CH0 ±400、CH1 ±100）共用一个 vs
//   - 检查: 像素幅度严格 4:1（y 范围 48..398 / 180..266），证明没有各通道单独归一化
// 场景 E: 菜单两页 OSD
//   - P0 = 9 行(面板 y=8..87)，P1 = 8 行(面板 y=8..79)，每行都有文字像素
//   - P1 的 w0..w7 必须分别接 CH0/CH1 两套 wave/freq/amp/phase
// 场景 F: AD/DA 模式（adc_mode=1）P1 信号源页不可用，菜单回到 P0
// 另外检查: 每帧 de 像素 = 640*480 = 307200, 行周期 800 clk = 16000ns
//=============================================================================
module tb_vga_scope_top;

`ifdef PIX2
    localparam integer PIX_DIV = 2;                  // Gowin 老工程配置
`else
    localparam integer PIX_DIV = 1;                  // SparkRoad 实际配置
`endif
    localparam integer CLK_NS  = 20;                 // 50MHz 仿真时钟
    localparam integer H_VIS   = 640;
    localparam integer V_VIS   = 480;

    localparam [11:0] COL_BG   = 12'h012;
    localparam [11:0] COL_GRID = 12'h151;
    localparam [11:0] COL_AXIS = 12'h2A2;
    localparam [11:0] COL_CH0  = 12'h1F1;
    localparam [11:0] COL_CH1  = 12'hFF1;
    localparam [11:0] COL_TEXT = 12'hFFF;
    // 菜单 OSD 的三种自用颜色（menu_layer 内部的 C_BG/C_BORDER/C_SELBG）
    localparam [11:0] COL_MENU_BG     = 12'h123;
    localparam [11:0] COL_MENU_BORDER = 12'hCC3;
    localparam [11:0] COL_MENU_SEL    = 12'h553;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg [9:0]  ch0_in = 10'd100;      // 场景 0：自动量程用的 CH0 方波(100/700)
    reg [9:0]  ch1_in = 10'd700;      // 场景 0：自动量程用的 CH1 方波(700/900)
    reg        adc_valid = 1'b1;
    reg        key_in = 1'b1;
    reg        ramp = 1'b0;
    reg        auto_sig = 1'b1;       // 场景 0：两路自动量程测试波形
    reg        two_tone = 1'b0;       // 场景 D：两路不同幅度的方波（幅度比 4:1）
    reg        sw_auto  = 1'b1;       // 场景 0：SW4 拨上（自动量程）
    reg        sw_menu  = 1'b0;       // SW0：1=菜单打开
    reg        sw_page  = 1'b0;       // SW2：菜单开=翻页；菜单关=通道选择（拨上=CH1）
    reg        adc_mode = 1'b0;       // SW8：1=AD/DA 模式（信号源页不可用）
    reg [6:0]  sq_cnt = 7'd0;
    reg [4:0]  tt_cnt = 5'd0;         // 场景 D 的方波分频（最高位翻转 -> 32 拍一个周期）

    // 串口配置全置 0（用 scope_app 的默认值，仅把 tb_div 改成 0 以快速填满 RAM）
    reg        cfg_tb_we = 1'b0;   reg [15:0] cfg_tb = 16'd0;
    wire [11:0] vga_rgb;
    wire        vga_hs, vga_vs, vga_de;
    wire        sel_ch_o;             // 选中通道 0=CH0 1=CH1（SW2 复用结果）

    vga_scope_top #(
        .H_VIS(H_VIS), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(V_VIS), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(PIX_DIV),
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224), .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10), .CLK_HZ(24_000_000),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) dut (
        .clk(clk), .rst(rst), .ch0_in(ch0_in), .ch1_in(ch1_in),
        .adc_valid(adc_valid), .adc_mode(adc_mode), .key_n(4'b1111), .sw_menu(sw_menu), .sw_run(1'b0), .sw_page(sw_page), .sw_roll(1'b0), .sw_roll2(1'b1), .sw_auto(sw_auto), .sw_hzfree(1'b0), .sw_move(1'b0),
        .cfg_tb_we(cfg_tb_we), .cfg_tb(cfg_tb),
        .cfg_run_we(1'b0), .cfg_run(1'b1),
        .cfg_ten_we(1'b0), .cfg_ten(1'b0),
        .cfg_lvl_we(1'b0), .cfg_lvl(10'd512),
        .cfg_edg_we(1'b0), .cfg_edg(1'b0),
        .cfg_scr_we(1'b0), .cfg_scr(1'b0),
        .cfg_tmode_we(1'b0), .cfg_tmode(2'd0),
        .cfg_tsrc_we(1'b0), .cfg_tsrc(1'b0),
        .cfg_pre_we(1'b0), .cfg_pre(10'd0),
        .cfg_hold_we(1'b0), .cfg_hold(16'd0),
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de),
        .sel_ch_o(sel_ch_o)
    );

    always #(CLK_NS/2) clk = ~clk;

    // 波形发生（合并到一个 always 块，避免同一个寄存器被两个过程块驱动）
    //   场景 0（自动量程）：CH0 方波 100/700、CH1 方波 700/900（幅度/偏置都不同）
    //   场景 B（斜坡）    ：CH0 每拍 +1
    always @(posedge clk) begin
        tt_cnt <= tt_cnt + 5'd1;
        if (two_tone) begin
            // 场景 D：两路同频方波、幅度 4:1（CH0 ±400、CH1 ±100），
            // 用来验证"共用同一个 vs"时屏幕上的幅度比例保持不变。
            ch0_in <= tt_cnt[4] ? 10'd912 : 10'd112;
            ch1_in <= tt_cnt[4] ? 10'd612 : 10'd412;
        end
        else if (auto_sig) begin
            sq_cnt <= (sq_cnt == 7'd49) ? 7'd0 : (sq_cnt + 7'd1);
            ch0_in <= (sq_cnt < 7'd25) ? 10'd100 : 10'd700;
            ch1_in <= (sq_cnt < 7'd25) ? 10'd700 : 10'd900;
        end
        else if (ramp) ch0_in <= ch0_in + 10'd1;
    end

    //------------------------------------------------------------------
    // 帧捕获：按 vga_de 逐像素统计
    //------------------------------------------------------------------
    integer x_cnt = 0, y_cnt = 0, de_total = 0;
    integer frame_captured = 0;
    reg     cap_en = 1'b0;

    integer n_bg = 0, n_grid = 0, n_axis = 0, n_ch0 = 0, n_ch1 = 0, n_text = 0;
    integer ch0_y_min = 99999, ch0_y_max = -1;
    integer ch1_y_min = 99999, ch1_y_max = -1;
    // 菜单 OSD 逐行像素统计（只统计 y<96：P0 面板最高到 y=87）
    integer menu_row_pix [0:95];
    integer menu_txt_pix [0:95];
    reg [11:0] line223 [0:H_VIS-1];
    reg [11:0] line224 [0:H_VIS-1];

    always @(posedge clk) begin
        // 必须按像素节拍采样：PIX_DIV=2 时一个像素占 2 个时钟，
        // 若按时钟计数会把一帧算成两帧，且坐标翻倍。
        if (cap_en && vga_de && dut.pix_ce) begin
            de_total = de_total + 1;
            case (vga_rgb)
                COL_BG  : n_bg   = n_bg   + 1;
                COL_GRID: n_grid = n_grid + 1;
                COL_AXIS: n_axis = n_axis + 1;
                COL_CH0 : begin
                    n_ch0 = n_ch0 + 1;
                    if (y_cnt < ch0_y_min) ch0_y_min = y_cnt;
                    if (y_cnt > ch0_y_max) ch0_y_max = y_cnt;
                end
                COL_CH1 : begin
                    n_ch1 = n_ch1 + 1;
                    if (y_cnt < ch1_y_min) ch1_y_min = y_cnt;
                    if (y_cnt > ch1_y_max) ch1_y_max = y_cnt;
                end
                COL_TEXT: n_text = n_text + 1;
                default : ;
            endcase
            if (y_cnt < 96) begin
                if ((vga_rgb == COL_MENU_BG) || (vga_rgb == COL_MENU_BORDER) ||
                    (vga_rgb == COL_MENU_SEL))
                    menu_row_pix[y_cnt] = menu_row_pix[y_cnt] + 1;
                if (vga_rgb == COL_TEXT) menu_txt_pix[y_cnt] = menu_txt_pix[y_cnt] + 1;
            end
            if (y_cnt == 223 && x_cnt < H_VIS) line223[x_cnt] = vga_rgb;
            if (y_cnt == 224 && x_cnt < H_VIS) line224[x_cnt] = vga_rgb;
            if (x_cnt == H_VIS-1) begin
                x_cnt = 0;
                y_cnt = y_cnt + 1;
                if (y_cnt == V_VIS) frame_captured = 1;
            end
            else x_cnt = x_cnt + 1;
        end
    end

    // 行同步周期测量
    time    t_hs1 = 0, hs_period = 0;
    integer hs_seen = 0;
    always @(posedge vga_hs) begin
        // 只统计复位后的稳定间隔（复位释放瞬间 vga_hs 从 X 变 1 会产生伪边沿）
        if (hs_seen > 0) hs_period = $time - t_hs1;
        t_hs1 = $time;
        hs_seen = hs_seen + 1;
    end

    integer errors = 0;
    integer i, bad, bad_first, tmo;
    integer mi;

    task reset_stats;
        begin
            x_cnt = 0; y_cnt = 0; de_total = 0; frame_captured = 0;
            n_bg = 0; n_grid = 0; n_axis = 0; n_ch0 = 0; n_ch1 = 0; n_text = 0;
            ch0_y_min = 99999; ch0_y_max = -1;
            ch1_y_min = 99999; ch1_y_max = -1;
            for (mi = 0; mi < 96; mi = mi + 1) begin
                menu_row_pix[mi] = 0;
                menu_txt_pix[mi] = 0;
            end
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_vga_scope_top.vcd");
            $dumpvars(0, tb_vga_scope_top);
        end

        repeat (8) @(posedge clk);
        rst = 1'b0;

        // tb_div = 0: 每个时钟采一个点，快速填满 1024 点 RAM
        @(posedge clk); cfg_tb_we <= 1'b1;
        @(posedge clk); cfg_tb_we <= 1'b0;

        repeat (3000) @(posedge clk);

        //==================== 场景 0：SW4 自动量程（两路同时进屏）====================
        //   CH0 100/700 方波：中点 400，峰值 max(700-512, 512-100)=412
        //   CH1 700/900 方波：中点 800，峰值 max(900-512, 512-700<0)=388
        //   档位只看 max(412,388)=412 -> vs=4（412*7/16 = 180 <= 201px）
        //   各自精细居中后：CH0 占 y=92..355、CH1 占 y=180..267
        //   => 两路波形同时完整落在 0..447 的绘图区里（这是本次改动的目标）
        $display("[tb_vga_scope_top] 场景 0: SW4 自动量程 CH0=100/700 CH1=700/900");
        tmo = 0;
        while ((dut.u_auto.mid_out0 !== 10'd400) && (tmo < 200000)) begin
            @(posedge clk);
            tmo = tmo + 1;
        end
        $display("  autoset: vs=%0d mid0=%0d mid1=%0d peak=%0d (expect 4/400/800/412)",
                 dut.u_auto.vs_out, dut.u_auto.mid_out0, dut.u_auto.mid_out1, dut.u_auto.peak_out);
        if (dut.u_auto.vs_out   !== 3'd4)     begin errors=errors+1; $display("  FAIL 自动档位不是 4"); end
        if (dut.u_auto.mid_out0 !== 10'd400)  begin errors=errors+1; $display("  FAIL CH0 中点不是 400"); end
        if (dut.u_auto.mid_out1 !== 10'd800)  begin errors=errors+1; $display("  FAIL CH1 中点不是 800"); end
        if (dut.u_auto.peak_out !== 10'd412)  begin errors=errors+1; $display("  FAIL peak_out 不是 max(peak0,peak1)=412"); end
        if (dut.vsc0_eff !== dut.vsc1_eff)    begin errors=errors+1; $display("  FAIL 两通道档位不一致"); end
        // 通道显不显示只由 ch0_en/ch1_en 决定，自动量程不许动它们
        if (dut.ch0_en !== 1'b1 || dut.ch1_en !== 1'b1)
                          begin errors=errors+1; $display("  FAIL 自动量程改变了通道使能"); end

        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        $display("  CH0 波形行范围 : %0d..%0d (expect 92..355)", ch0_y_min, ch0_y_max);
        $display("  CH1 波形行范围 : %0d..%0d (expect 180..267)", ch1_y_min, ch1_y_max);
        $display("  CH0/CH1 像素数 : %0d/%0d", n_ch0, n_ch1);
        if (n_ch0 == 0 || n_ch1 == 0) begin errors=errors+1; $display("  FAIL 有通道没显示出来"); end
        // "完整落在屏幕内"：既不能贴边(0/447)，也不能整段跑到屏外
        if (ch0_y_min < 1 || ch0_y_max > 447)
                begin errors=errors+1; $display("  FAIL CH0 波形没有完整落在屏幕内"); end
        if (ch1_y_min < 1 || ch1_y_max > 447)
                begin errors=errors+1; $display("  FAIL CH1 波形没有完整落在屏幕内"); end
        if (ch0_y_min != 92 || ch0_y_max != 355)
                begin errors=errors+1; $display("  FAIL CH0 居中位置不对 (expect 92..355)"); end
        if (ch1_y_min != 180 || ch1_y_max != 267)
                begin errors=errors+1; $display("  FAIL CH1 居中位置不对 (expect 180..267)"); end

        // 关掉自动量程、恢复固定电平，准备场景 A（手动档 vs0=4、pos=5 居中）
        //   注意：波形发生器用的是非阻塞赋值，直接在本拍改写 din 会被寄存器更新
        //   覆盖掉（NBA 区在活动区之后执行），所以先停波形，等一拍再给固定电平。
        auto_sig = 1'b0;
        @(posedge clk);
        sw_auto  = 1'b0;
        ch0_in   = 10'd512;
        ch1_in   = 10'd300;
        repeat (3000) @(posedge clk);

        //==================== 场景 A：恒定电平 ====================
        $display("[tb_vga_scope_top] 场景 A: CH0=512, CH1=300");
        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        $display("  每帧 de 像素   : %0d (expect %0d)", de_total, H_VIS*V_VIS);
        $display("  行同步周期     : %0d ns (expect %0d ns)", hs_period, 800*CLK_NS*PIX_DIV);
        $display("  颜色计数 bg/grid/axis/ch0/ch1/text = %0d/%0d/%0d/%0d/%0d/%0d",
                 n_bg, n_grid, n_axis, n_ch0, n_ch1, n_text);
        $display("  CH0 波形行范围 : %0d..%0d (expect 223..223)", ch0_y_min, ch0_y_max);
        $display("  CH1 波形行范围 : %0d..%0d (expect 316..316)", ch1_y_min, ch1_y_max);

        if (de_total != H_VIS*V_VIS) begin errors=errors+1; $display("  FAIL de 像素数"); end
        if (hs_period != 800*CLK_NS*PIX_DIV) begin errors=errors+1; $display("  FAIL 行周期"); end
        if (n_text == 0) begin errors=errors+1; $display("  FAIL 没有文字像素"); end
        if (n_grid == 0) begin errors=errors+1; $display("  FAIL 没有网格像素"); end
        if (n_axis == 0) begin errors=errors+1; $display("  FAIL 没有零轴像素"); end
        if (n_bg   == 0) begin errors=errors+1; $display("  FAIL 没有背景像素"); end
        if (n_ch0  == 0) begin errors=errors+1; $display("  FAIL 没有 CH0 波形"); end
        if (ch0_y_min != 223 || ch0_y_max != 223)
                         begin errors=errors+1; $display("  FAIL CH0 波形不在 y=223"); end
        if (ch1_y_min != 316 || ch1_y_max != 316)
                         begin errors=errors+1; $display("  FAIL CH1 波形不在 y=316"); end

        // y=223 整行应为 CH0（x=0 被 trace_layer 的 px!=0 排除，是网格）
        // 修复后 PIX_DIV=1 / PIX_DIV=2 都应 0 坏列；修复前 PIX_DIV=1 的 x=639 恒为背景。
        bad = 0; bad_first = -1;
        for (i = 1; i < H_VIS; i = i + 1)
            if (line223[i] !== COL_CH0) begin
                if (bad_first < 0) bad_first = i;
                bad = bad + 1;
            end
        $display("  y=223 异常列   : %0d 个 (expect 0)", bad);
        if (bad != 0) begin
            errors = errors + 1;
            $display("  FAIL y=223 有 %0d 列不是波形色，首列 x=%0d color=%03X",
                     bad, bad_first, line223[bad_first]);
        end

        // y=224 是零轴，优先级高于网格，整行应为 COL_AXIS
        bad = 0; bad_first = -1;
        for (i = 0; i < H_VIS; i = i + 1)
            if (line224[i] !== COL_AXIS) begin
                if (bad_first < 0) bad_first = i;
                bad = bad + 1;
            end
        $display("  y=224 异常列   : %0d 个 (expect 0)", bad);
        if (bad != 0) begin
            errors = errors + 1;
            $display("  FAIL y=224 有 %0d 列不是零轴色，首列 x=%0d color=%03X",
                     bad, bad_first, line224[bad_first]);
        end

        //==================== 场景 B：斜坡输入 ====================
        ramp = 1'b1;
        repeat (4000) @(posedge clk);
        $display("[tb_vga_scope_top] 场景 B: CH0 斜坡");
        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        $display("  CH0 波形行范围 : %0d..%0d (应纵向铺开 >200)", ch0_y_min, ch0_y_max);
        $display("  CH0 像素数     : %0d", n_ch0);
        // 像素数只当"波形可见"的底线：一屏 640 列、斜坡每列至少 1 个像素，
        // 但窗口是否跨过 1023->0 的回绕点取决于缓冲相位（跨过时多一条整列竖线，
        // 像素数会多出约 447 个），所以这里不卡具体数值。
        if (n_ch0 < 500) begin errors=errors+1; $display("  FAIL 波形像素太少"); end
        if ((ch0_y_max - ch0_y_min) < 200)
            begin errors=errors+1; $display("  FAIL 波形没有纵向铺开"); end

        //==================== 场景 D：两路共用 vs，幅度比例不变 ====================
        //   需求：自动量程/手动档位都是"两路共用一个 vs"，不做各通道单独归一化。
        //   CH0 方波 112/912（±400）、CH1 方波 412/612（±100），幅度比 4:1。
        //   共用 vs=4（手动档，SW4=0）时像素幅度也必须是 4:1：
        //     CH0: y = 223 ± (400*7>>4) = 48..398
        //     CH1: y = 223 ± (100*7>>4) = 180..267（负数算术右移向下取整）
        ramp     = 1'b0;
        two_tone = 1'b1;
        repeat (4000) @(posedge clk);
        $display("[tb_vga_scope_top] 场景 D: 两路不同幅度共用一个 vs");
        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        $display("  vsc0_eff=%0d vsc1_eff=%0d (expect 4/4，共用一个档位)",
                 dut.vsc0_eff, dut.vsc1_eff);
        $display("  CH0 波形行范围 : %0d..%0d (expect 48..398)", ch0_y_min, ch0_y_max);
        $display("  CH1 波形行范围 : %0d..%0d (expect 180..267)", ch1_y_min, ch1_y_max);
        if (dut.vsc0_eff !== dut.vsc1_eff) begin
            errors=errors+1; $display("  FAIL 两通道没有共用同一个 vs"); end
        if (ch0_y_min != 48 || ch0_y_max != 398) begin
            errors=errors+1; $display("  FAIL CH0 幅度映射不对（共用 vs 失效？）"); end
        if (ch1_y_min != 180 || ch1_y_max != 267) begin
            errors=errors+1; $display("  FAIL CH1 幅度映射不对（是否被单独归一化了？）"); end

        //==================== 场景 E：菜单 OSD 两页 ====================
        //   需求：P1 信号源页 = CH0 四项 + CH1 四项（8 项）。
        //   版面高度 = 项数*8 + 8，所以 P0(9 项) 面板 y=8..87、P1(8 项) y=8..79：
        //   用"面板底边所在行"就能判定页内项数，再逐行检查有没有画出文字。
        two_tone = 1'b0;
        sw_menu  = 1'b1;
        sw_page  = 1'b0;
        repeat (3000) @(posedge clk);
        $display("[tb_vga_scope_top] 场景 E: 菜单两页");
        if (dut.menu_on !== 1'b1) begin
            errors=errors+1; $display("  FAIL 菜单没有打开"); end
        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        $display("  P0: menu_page=%b rows=%0d (expect 0/9)", dut.menu_page, dut.u_menu.rows);
        if (dut.menu_page !== 1'b0 || dut.u_menu.rows !== 4'd9) begin
            errors=errors+1; $display("  FAIL P0 项数/页号不对"); end
        bad = 0;
        for (i = 8; i <= 87; i = i + 1) if (menu_row_pix[i] == 0) bad = bad + 1;
        for (i = 88; i <= 95; i = i + 1) if (menu_row_pix[i] != 0) bad = bad + 1;
        for (mi = 0; mi < 9; mi = mi + 1) begin
            tmo = 0;
            for (i = 12 + mi*8; i <= 19 + mi*8; i = i + 1) tmo = tmo + menu_txt_pix[i];
            if (tmo < 5) bad = bad + 1;          // 这一行没有文字
        end
        $display("  P0 面板/文字异常行数 : %0d (expect 0)", bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL P0 菜单面板高度/行文字不对"); end

        // 翻到 P1（SW2 拨上）
        sw_page = 1'b1;
        repeat (3000) @(posedge clk);
        $display("  P1: menu_page=%b pg=%b rows=%0d (expect 1/1/8)",
                 dut.menu_page, dut.u_menu.pg, dut.u_menu.rows);
        if (dut.menu_page !== 1'b1 || dut.u_menu.pg !== 1'b1 || dut.u_menu.rows !== 4'd8) begin
            errors=errors+1; $display("  FAIL P1 没有扩成 8 项"); end
        // 8 个菜单项必须分别接 CH0/CH1 两套参数（0..3=CH0，4..7=CH1）
        if (dut.u_menu.w0 !== {2'd0, dut.u_app.wave0}) begin
            errors=errors+1; $display("  FAIL P1 项0 不是 CH0 WAV"); end
        if (dut.u_menu.w1 !== {1'b0, dut.u_app.fsel0}) begin
            errors=errors+1; $display("  FAIL P1 项1 不是 CH0 FRE"); end
        if (dut.u_menu.w2 !== {2'd0, dut.u_app.asel0}) begin
            errors=errors+1; $display("  FAIL P1 项2 不是 CH0 ATT"); end
        if (dut.u_menu.w3 !== dut.u_app.phase0) begin
            errors=errors+1; $display("  FAIL P1 项3 不是 CH0 PHA"); end
        if (dut.u_menu.w4 !== {2'd0, dut.u_app.wave1}) begin
            errors=errors+1; $display("  FAIL P1 项4 不是 CH1 WAV"); end
        if (dut.u_menu.w5 !== {1'b0, dut.u_app.fsel1}) begin
            errors=errors+1; $display("  FAIL P1 项5 不是 CH1 FRE"); end
        if (dut.u_menu.w6 !== {2'd0, dut.u_app.asel1}) begin
            errors=errors+1; $display("  FAIL P1 项6 不是 CH1 ATT"); end
        if (dut.u_menu.w7 !== dut.u_app.phase1) begin
            errors=errors+1; $display("  FAIL P1 项7 不是 CH1 PHA"); end

        @(posedge dut.frame);
        reset_stats;
        cap_en <= 1'b1;
        wait (frame_captured);
        cap_en <= 1'b0;

        bad = 0;
        for (i = 8; i <= 79; i = i + 1) if (menu_row_pix[i] == 0) bad = bad + 1;
        for (i = 80; i <= 95; i = i + 1) if (menu_row_pix[i] != 0) bad = bad + 1;
        for (mi = 0; mi < 8; mi = mi + 1) begin
            tmo = 0;
            for (i = 12 + mi*8; i <= 19 + mi*8; i = i + 1) tmo = tmo + menu_txt_pix[i];
            if (tmo < 5) bad = bad + 1;
        end
        $display("  P1 面板/文字异常行数 : %0d (expect 0)", bad);
        if (bad != 0) begin errors=errors+1; $display("  FAIL P1 菜单面板高度/行文字不对"); end

        //==================== 场景 F：AD/DA 模式 P1 不可用 ====================
        sw_menu = 1'b0;
        sw_page = 1'b0;
        repeat (100) @(posedge clk);
        adc_mode = 1'b1;
        sw_menu  = 1'b1;
        sw_page  = 1'b1;
        repeat (3000) @(posedge clk);
        $display("[tb_vga_scope_top] 场景 F: AD/DA 模式 (adc_mode=1)");
        $display("  menu_page=%b pg=%b rows=%0d gen_ena_eff=%b (expect 0/0/9/0)",
                 dut.menu_page, dut.u_menu.pg, dut.u_menu.rows, dut.gen_ena_eff);
        if (dut.menu_page !== 1'b0) begin
            errors=errors+1; $display("  FAIL AD/DA 模式下不该能进 P1"); end
        if (dut.u_menu.pg !== 1'b0 || dut.u_menu.rows !== 4'd9) begin
            errors=errors+1; $display("  FAIL AD/DA 模式下菜单页不对"); end
        if (dut.gen_ena_eff !== 1'b0) begin
            errors=errors+1; $display("  FAIL AD/DA 模式下信号源没有关掉"); end
        adc_mode = 1'b0;
        sw_menu  = 1'b0;
        sw_page  = 1'b0;
        repeat (3000) @(posedge clk);

        //==================== 场景 C：SW2 复用（菜单关闭 = 通道选择）====================
        //   场景 F 结束时已经把 SW0 关掉（菜单关闭），所以 SW2 只当通道选择用：
        //   拨上应选中 CH1（sel_ch_o=1）、拨下选中 CH0（sel_ch_o=0）。
        //   这里只验证顶层端口有没有把 scope_app 的选择结果引出来；按键行为
        //   （U/D 只调选中通道）在 tb_scope_app 里逐条验证。
        $display("[tb_vga_scope_top] 场景 C: SW2 通道选择");
        sw_page = 1'b1;
        repeat (10) @(posedge clk);
        $display("  SW2 拨上: sel_ch_o=%b (expect 1=CH1)", sel_ch_o);
        if (sel_ch_o !== 1'b1) begin errors=errors+1; $display("  FAIL SW2 拨上没选中 CH1"); end
        sw_page = 1'b0;
        repeat (10) @(posedge clk);
        $display("  SW2 拨下: sel_ch_o=%b (expect 0=CH0)", sel_ch_o);
        if (sel_ch_o !== 1'b0) begin errors=errors+1; $display("  FAIL SW2 拨下没选中 CH0"); end

        if (errors == 0) $display("[tb_vga_scope_top] PASS");
        else             $display("[tb_vga_scope_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
