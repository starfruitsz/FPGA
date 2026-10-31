//==============================================================================
// 层: 顶层(SparkRoad-V / EG4S20BG256)  文件: sparkroad_scope_top.v
// 功能: 把示波器移植到 SparkRoad-V：
//   24MHz(K14) -> VGA 640x480@~57Hz(24MHz 像素时钟) -> GM7123 24bit RGB
//   AD7606(SPI 串行) CH0 -> ADC HAL -> 示波器采集/触发/测量 -> VGA
//   UART(115200) 同时接 scope_cmd(VGA 参数) 与 adc_cmd(ADC 参数)
// 说明: VGA 颜色为 RGB444 内部格式，输出时把每 4bit 复制成 8bit。
//==============================================================================
`timescale 1ns / 1ps

module sparkroad_scope_top #(
    parameter integer CLK_HZ = 24_000_000,
    parameter integer TX_MODE = 0,       // 0=连续发送(默认) 1=每 1ms 一帧
    parameter integer DEMO_SINE = 0      // 1=用内部 50Hz 正弦替代 ADC（不接 ADC 演示用）
)(
    // 时钟/复位/按键
    input  wire        clk,          // K14 24MHz
    input  wire        rst_n,        // G11 BUTTON_C，低有效
    input  wire        key_l,        // H14 BUTTON_L
    input  wire        key_u,        // J13 BUTTON_U
    input  wire        key_d,        // G12 BUTTON_D
    input  wire        key_r,        // L12 BUTTON_R
    input  wire [7:0]  sw,           // SW0..SW7 (T4/R5/T5/T6/M6/P6/N6/P8)
    // 串口
    output wire        uart_tx,      // F16
    input  wire        uart_rx,      // E16
    // VGA (GM7123)
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_clk,
    // 数码管
    output wire [7:0]  seg,
    output wire [3:0]  sel,
    output wire [15:0] led,          // LED0..15，低电平点亮
    // AD7606 (串行模式)
    output wire        ad7606_convst,
    input  wire        ad7606_busy,
    output wire        ad7606_cs_n,
    output wire        ad7606_sclk,
    input  wire        ad7606_douta,
    output wire        ad7606_reset,
    output wire        ad7606_ser
);
    wire rst = ~rst_n;

    //------------------------------------------------------------------
    // 串口接收（24MHz 时钟，115200）
    //------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .UART_BPS (115200),
        .CLK_FREQ (CLK_HZ)
    ) u_rx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .rx       (uart_rx),
        .po_data  (rx_data),
        .po_flag  (rx_valid)
    );

    //------------------------------------------------------------------
    // 示波器命令（VGA 参数）
    //------------------------------------------------------------------
    wire        cfg_tb_we, cfg_run_we, cfg_ten_we, cfg_lvl_we, cfg_edg_we, cfg_scr_we;
    wire        cfg_tmode_we, cfg_tsrc_we, cfg_pre_we, cfg_hold_we;
    wire [15:0] cfg_tb, cfg_hold;
    wire        cfg_run, cfg_ten, cfg_edg, cfg_scr, cfg_tsrc;
    wire [9:0]  cfg_lvl, cfg_pre;
    wire [1:0]  cfg_tmode;

    scope_cmd u_scope_cmd (
        .clk      (clk),
        .rst      (rst),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .tb_we    (cfg_tb_we),   .tb_val(cfg_tb),
        .run_we   (cfg_run_we),  .run_val(cfg_run),
        .ten_we   (cfg_ten_we),  .ten_val(cfg_ten),
        .lvl_we   (cfg_lvl_we),  .lvl_val(cfg_lvl),
        .edg_we   (cfg_edg_we),  .edg_val(cfg_edg),
        .scr_we   (cfg_scr_we),  .scr_val(cfg_scr),
        .tmode_we (cfg_tmode_we), .tmode_val(cfg_tmode),
        .tsrc_we  (cfg_tsrc_we),  .tsrc_val(cfg_tsrc),
        .pre_we   (cfg_pre_we),   .pre_val(cfg_pre),
        .hold_we  (cfg_hold_we),  .hold_val(cfg_hold)
    );

    //------------------------------------------------------------------
    // ADC 命令（量程/过采样/SCLK/采样率）
    //------------------------------------------------------------------
    wire [7:0]  adc_csr_addr;
    wire [31:0] adc_csr_wdata;
    wire        adc_csr_we;

    adc_cmd u_adc_cmd (
        .clk      (clk),
        .rst      (rst),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .csr_addr (adc_csr_addr),
        .csr_wdata(adc_csr_wdata),
        .csr_we   (adc_csr_we)
    );

    //------------------------------------------------------------------
    // AD7606 采集（CH0）
    //------------------------------------------------------------------
    wire [15:0] adc_data;
    wire [1:0]  adc_ch;
    wire        adc_valid;
    wire        adc_locked, adc_error;

    adc_ad7606_top #(
        .RES(10), .DW(16), .SDIV_DEF(4), .OS_DEF(0), .RANGE_DEF(1)
    ) u_adc (
        .clk      (clk),
        .rst      (rst),
        .csr_addr (adc_csr_addr),
        .csr_wdata(adc_csr_wdata),
        .csr_we   (adc_csr_we),
        .csr_rdata(),
        .convst   (ad7606_convst),
        .cs_n     (ad7606_cs_n),
        .sclk     (ad7606_sclk),
        .douta    (ad7606_douta),
        .busy     (ad7606_busy),
        .adc_reset(ad7606_reset),
        .ser      (ad7606_ser),
        .os       (),
        .range    (),
        .stby     (),
        .s_data   (adc_data),
        .s_ch     (adc_ch),
        .s_valid  (adc_valid),
        .s_ready  (1'b1),
        .locked   (adc_locked),
        .error    (adc_error)
    );

    //------------------------------------------------------------------
    //------------------------------------------------------------------
    // 4 键（低有效）与函数发生器设置
    //------------------------------------------------------------------
    wire [3:0] key_n = {key_u, key_d, key_l, key_r};

    // 拨动开关同步 + 消抖
    wire sw0_lv, sw1_lv, sw2_lv, sw3_lv, sw4_lv, sw5_lv, sw6_lv, sw7_lv;
    wire sw0_rise, sw1_rise, sw2_rise, sw3_rise;
    sw_edge u_sw0 (.clk(clk), .rst(rst), .sw_in(sw[0]), .lv(sw0_lv), .rise(sw0_rise));
    sw_edge u_sw1 (.clk(clk), .rst(rst), .sw_in(sw[1]), .lv(sw1_lv), .rise(sw1_rise));
    sw_edge u_sw2 (.clk(clk), .rst(rst), .sw_in(sw[2]), .lv(sw2_lv), .rise(sw2_rise));
    sw_edge u_sw3 (.clk(clk), .rst(rst), .sw_in(sw[3]), .lv(sw3_lv), .rise(sw3_rise));
    // SW5(P6)：滚动开关（拨上=非滚动、拨下=滚动）
    sw_edge u_sw5 (.clk(clk), .rst(rst), .sw_in(sw[5]), .lv(sw5_lv), .rise());
    // SW4(M6)：自动量程（拨上=持续自适应）
    sw_edge u_sw4 (.clk(clk), .rst(rst), .sw_in(sw[4]), .lv(sw4_lv), .rise());
    // SW6(N6)：横轴缩放放开上限；SW7(P8)：U/D 移动基线
    sw_edge u_sw6 (.clk(clk), .rst(rst), .sw_in(sw[6]), .lv(sw6_lv), .rise());
    sw_edge u_sw7 (.clk(clk), .rst(rst), .sw_in(sw[7]), .lv(sw7_lv), .rise());
    wire [1:0] gen_wave;
    wire [2:0] gen_freq;
    wire [1:0] gen_amp;
    wire       menu_on;
    wire [3:0] gen_phase;
    wire [7:0] dbg_status;

    // 演示信号源（DEMO_SINE=1 时不接 ADC，用内置函数发生器给示波器灌信号）
    //   上电后自动下发一次 T0 / A1 / M1 / L512：
    //     T0    -> tb_div=0（ADC 侧已经给好采样率，前端不再分频）
    //     A1    -> 触发使能
    //     M1    -> 连续刷新（跟踪模式，画面实时跟随信号；改成 M2 则为单次冻结）
    //     L512  -> 触发电平 = 中点
    //------------------------------------------------------------------
    wire [9:0] gen_data;
    wire       gen_valid;

    // 内置函数发生器：DDS 波形可选（正弦/方波/三角/锯齿）+ 8 档频率 + 4 档幅度
    func_gen #(.CLK_HZ(CLK_HZ), .FS_HZ(12_000)) u_gen (
        .clk(clk), .rst(rst),
        .wave(gen_wave), .freq_sel(gen_freq), .amp_sel(gen_amp), .phase_idx(gen_phase),
        .data(gen_data), .valid(gen_valid)
    );

    wire [9:0] scope_ch0 = DEMO_SINE ? gen_data  : adc_data[9:0];
    wire       scope_val = DEMO_SINE ? gen_valid : adc_valid;

    reg [7:0] boot_cnt;
    always @(posedge clk) begin
        if (rst) boot_cnt <= 8'd0;
        else if (boot_cnt != 8'hFF) boot_cnt <= boot_cnt + 8'd1;
    end

    wire demo_cfg = (DEMO_SINE != 0);
    wire demo_tb_we    = demo_cfg && (boot_cnt == 8'd120);
    wire demo_ten_we   = demo_cfg && (boot_cnt == 8'd130);
    wire demo_tmode_we = demo_cfg && (boot_cnt == 8'd140);
    wire demo_lvl_we   = demo_cfg && (boot_cnt == 8'd150);

    //------------------------------------------------------------------
    // 示波器显示（VGA 640x480，24MHz 像素时钟）
    //------------------------------------------------------------------
    wire [11:0] vga_rgb;
    wire        vga_de;

    //------------------------------------------------------------------
    // 示波器显示（VGA 640x480，24MHz 像素时钟，场频 57.14Hz）
    //   若需严格 60Hz：用 sparkroad_scope_pll 顶层（PLL 25.2MHz），时序完全标准。
    //   注意：不要靠压缩行同步宽度去凑场频，显示器会锁不住行频。
    //------------------------------------------------------------------
    vga_scope_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
        .H_POL(0), .V_POL(0),
        .PIX_DIV(1),            // 24MHz 直接作为像素时钟
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224),
        .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10),
        .CLK_HZ(CLK_HZ),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1),
        .GEN_ENA(DEMO_SINE)
    ) u_scope (
        .clk       (clk),
        .rst       (rst),
        .ch0_in    (scope_ch0),
        .ch1_in    (10'd512),      // 板上无 DAC，CH1 暂接中点
        .adc_valid (scope_val),
        .key_n     (key_n),
        .sw_menu   (sw0_lv),          // 电平：拨上=菜单开
        .sw_run    (sw1_lv),          // 电平：拨上=运行
        .sw_page   (sw2_lv),          // 电平：拨上=信号源页
        .sw_roll   (sw3_lv),          // 电平：拨上=滚动模式（与串口 S 命令同源）
        .sw_roll2  (sw5_lv),          // SW5(P6) 滚动开关
        .sw_auto   (sw4_lv),          // SW4(M6) 自动量程
        .sw_hzfree (sw6_lv),          // SW6(N6) 横轴缩放不设上限
        .sw_move   (sw7_lv),          // SW7(P8) U/D 移动基线
        .cfg_tb_we (demo_cfg ? demo_tb_we    : cfg_tb_we),    .cfg_tb(demo_cfg ? 16'd0  : cfg_tb),
        .cfg_run_we(cfg_run_we),  .cfg_run(cfg_run),
        .cfg_ten_we(demo_cfg ? demo_ten_we   : cfg_ten_we),   .cfg_ten(demo_cfg ? 1'b1 : cfg_ten),
        .cfg_lvl_we(demo_cfg ? demo_lvl_we   : cfg_lvl_we),   .cfg_lvl(demo_cfg ? 10'd512 : cfg_lvl),
        .cfg_edg_we(cfg_edg_we),  .cfg_edg(cfg_edg),
        .cfg_scr_we(cfg_scr_we),  .cfg_scr(cfg_scr),
        // 演示用 M2（single）：采一屏就冻结。用 M1(normal) 会每 85ms 重新采集，
        // 而本设计没有双缓冲，写指针会扫过正在显示的 RAM，屏幕上出现波形撕裂/重影。
        .cfg_tmode_we(demo_cfg ? demo_tmode_we : cfg_tmode_we), .cfg_tmode(demo_cfg ? 2'd1 : cfg_tmode),
        .cfg_tsrc_we (cfg_tsrc_we),  .cfg_tsrc(cfg_tsrc),
        .cfg_pre_we  (cfg_pre_we),   .cfg_pre(cfg_pre),
        .cfg_hold_we (cfg_hold_we),  .cfg_hold(cfg_hold),
        .vga_rgb   (vga_rgb),
        .vga_hs    (vga_hs),
        .vga_vs    (vga_vs),
        .vga_de    (vga_de),
        .gen_wave  (gen_wave),
        .gen_freq  (gen_freq),
        .gen_amp   (gen_amp),
        .menu_on_o (menu_on),
        .gen_phase (gen_phase),
        .dbg_status(dbg_status)
    );

    // RGB444 -> RGB888（每 4bit 复制一次，满量程）
    assign vga_r = {vga_rgb[11:8], vga_rgb[11:8]};
    assign vga_g = {vga_rgb[7:4],  vga_rgb[7:4]};
    assign vga_b = {vga_rgb[3:0],  vga_rgb[3:0]};
    assign vga_clk = clk;          // GM7123 像素时钟

    //------------------------------------------------------------------
    // 数码管：演示模式下显示"采集完成次数"；正常模式下显示 AD 码值
    //   （数字在涨 = 采集在跑；一直不动 = 采集卡住）
    //------------------------------------------------------------------
    // 演示模式下显示"采集完成计数器"，可以直接看出采集有没有在跑
    //   （数字在涨 = 每采满一屏就完成一次；一直是 0 = 采集卡住了）
    reg [9:0] cap_cnt;
    always @(posedge clk) begin
        if (rst)                    cap_cnt <= 10'd0;
        else if (dbg_status[7])     cap_cnt <= cap_cnt + 10'd1;
    end
    wire [9:0] seg_data = (DEMO_SINE != 0) ? cap_cnt : adc_data[9:0];
    // 板上数码管为共阳：段码低有效、位码高有效，故输出取反
    wire [3:0] sel_i;
    wire [7:0] seg_i;

    seg u_seg (
        .clk    (clk),
        .rst_n  (rst_n),
        .point  (4'b0000),
        .data   (seg_data),
        .seg_en (1'b1),
        .sign   (1'b0),
        .sel    (sel_i),
        .seg    (seg_i)
    );

    assign sel = ~sel_i;
    assign seg = ~seg_i;

    //------------------------------------------------------------------
    // 串口上报：TX_MODE=0 连续发送(默认)；TX_MODE=1 每 1ms 一帧
    //------------------------------------------------------------------
    localparam integer SEND_DIV = CLK_HZ / 1000;
    reg [15:0] tx_cnt;
    reg        tx_pulse;

    always @(posedge clk) begin
        if (rst) begin
            tx_cnt   <= 16'd0;
            tx_pulse <= 1'b0;
        end
        else if (tx_cnt >= SEND_DIV - 1) begin
            tx_cnt   <= 16'd0;
            tx_pulse <= 1'b1;
        end
        else begin
            tx_cnt   <= tx_cnt + 16'd1;
            tx_pulse <= 1'b0;
        end
    end

    wire tx_req = (TX_MODE == 0) ? 1'b1 : tx_pulse;

    uart_tx #(
        .UART_BPS (115200),
        .CLK_FREQ (CLK_HZ)
    ) u_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .pi_data  (adc_data),
        .pi_flag  (tx_req),
        .tx       (uart_tx)
    );

    //------------------------------------------------------------------
    // LED 调试指示（16 个，低电平点亮）
    //   LED[15:8] = 当前采样值高 8 位（电平条，一眼看出信号在不在动）
    //   LED[7]    = 运行
    //   LED[6]    = 滚动模式
    //   LED[5]    = 菜单打开
    //   LED[4]    = 触发命中（展宽 0.2s）
    //   LED[3]    = 采集完成（展宽 0.2s）
    //   LED[2:1]  = 采集状态 0=IDLE 1=ARMED 2=FILL 3=DONE
    //   LED[0]    = 信号源使能(演示模式)
    //------------------------------------------------------------------
    localparam integer STRETCH = CLK_HZ / 5;      // 0.2 秒
    reg [23:0] trig_cnt, done_cnt;
    reg        trig_hi,  done_hi;

    always @(posedge clk) begin
        if (rst) begin
            trig_cnt <= 24'd0;  trig_hi <= 1'b0;
            done_cnt <= 24'd0;  done_hi <= 1'b0;
        end
        else begin
            if (dbg_status[6]) begin trig_cnt <= STRETCH[23:0]; trig_hi <= 1'b1; end
            else if (trig_cnt != 0) begin trig_cnt <= trig_cnt - 24'd1; end
            else               trig_hi <= 1'b0;

            if (dbg_status[7]) begin done_cnt <= STRETCH[23:0]; done_hi <= 1'b1; end
            else if (done_cnt != 0) begin done_cnt <= done_cnt - 24'd1; end
            else               done_hi <= 1'b0;
        end
    end

    wire [15:0] led_map = { 8'h00,          // 15:8 预留（以前的电平条会随波形闪烁，先关掉） 电平条
                            dbg_status[2],   // 7 运行
                            dbg_status[3],   // 6 滚动
                            dbg_status[0],   // 5 菜单
                            trig_hi,         // 4 触发命中
                            done_hi,         // 3 采集完成
                            dbg_status[5:4], // 2:1 采集状态
                            (DEMO_SINE != 0) }; // 0 信号源使能

    assign led = ~led_map;                // 低电平点亮

endmodule