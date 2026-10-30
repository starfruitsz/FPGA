`timescale 1ns / 1ps
//=============================================================================
// tb_vga_scope_top.v -- vga_scope_top 整屏仿真（此前完全没有验证过）
//
// 配置: 640x480, PIX_DIV=1 (SparkRoad 实际配置, 像素时钟=系统时钟), 帧周期 800x525 clk
//
// 场景 A: CH0 恒定 512, CH1 恒定 300
//   - 电平 512 -> y = 447-(512*7>>4) = 223，波形应是一条水平直线
//   - 电平 300 -> y = 447-(300*7>>4) = 316
//   - 检查: y=223 整行(除 x=0)都是 COL_CH0；y=224 整行都是 COL_AXIS
// 场景 B: CH0 改成每拍 +1 的斜坡
//   - 检查: 波形纵向铺开(ymax-ymin>200)，证明 y 映射与竖线连接工作
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

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg [9:0]  ch0_in = 10'd512;
    reg [9:0]  ch1_in = 10'd300;
    reg        adc_valid = 1'b1;
    reg        key_in = 1'b1;
    reg        ramp = 1'b0;

    // 串口配置全置 0（用 scope_app 的默认值，仅把 tb_div 改成 0 以快速填满 RAM）
    reg        cfg_tb_we = 1'b0;   reg [15:0] cfg_tb = 16'd0;
    wire [11:0] vga_rgb;
    wire        vga_hs, vga_vs, vga_de;

    vga_scope_top #(
        .H_VIS(H_VIS), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(V_VIS), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_POL(0), .V_POL(0), .PIX_DIV(PIX_DIV),
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224), .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10), .CLK_HZ(24_000_000),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) dut (
        .clk(clk), .rst(rst), .ch0_in(ch0_in), .ch1_in(ch1_in),
        .adc_valid(adc_valid), .key_in(key_in),
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
        .vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de)
    );

    always #(CLK_NS/2) clk = ~clk;

    // 斜坡发生器（场景 B 用）
    always @(posedge clk) if (ramp) ch0_in <= ch0_in + 10'd1;

    //------------------------------------------------------------------
    // 帧捕获：按 vga_de 逐像素统计
    //------------------------------------------------------------------
    integer x_cnt = 0, y_cnt = 0, de_total = 0;
    integer frame_captured = 0;
    reg     cap_en = 1'b0;

    integer n_bg = 0, n_grid = 0, n_axis = 0, n_ch0 = 0, n_ch1 = 0, n_text = 0;
    integer ch0_y_min = 99999, ch0_y_max = -1;
    integer ch1_y_min = 99999, ch1_y_max = -1;
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
    integer i, bad, bad_first;

    task reset_stats;
        begin
            x_cnt = 0; y_cnt = 0; de_total = 0; frame_captured = 0;
            n_bg = 0; n_grid = 0; n_axis = 0; n_ch0 = 0; n_ch1 = 0; n_text = 0;
            ch0_y_min = 99999; ch0_y_max = -1;
            ch1_y_min = 99999; ch1_y_max = -1;
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
        if (n_ch0 < 1000) begin errors=errors+1; $display("  FAIL 波形像素太少"); end
        if ((ch0_y_max - ch0_y_min) < 200)
            begin errors=errors+1; $display("  FAIL 波形没有纵向铺开"); end

        if (errors == 0) $display("[tb_vga_scope_top] PASS");
        else             $display("[tb_vga_scope_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
