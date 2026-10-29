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
    parameter integer CLK_HZ = 24_000_000
)(
    // 时钟/复位/按键
    input  wire        clk,          // K14 24MHz
    input  wire        rst_n,        // G11 BUTTON_C，低有效
    input  wire        key,          // H14 BUTTON_L
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
    // 示波器显示（VGA 640x480，24MHz 像素时钟）
    //------------------------------------------------------------------
    wire [11:0] vga_rgb;
    wire        vga_de;

    vga_scope_top #(
        .H_VIS(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VIS(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
        .H_POL(0), .V_POL(0),
        .PIX_DIV(1),            // 24MHz 直接作为像素时钟
        .PLOT_H(448), .GRID_STEP(64), .AXIS_Y(224),
        .TEXT_Y0(448), .TEXT_X0(8),
        .DEPTH_LOG2(10),
        .CLK_HZ(CLK_HZ),
        .FEAT_TRIG(1), .FEAT_MEAS(1), .FEAT_SCROLL(1), .FEAT_UART(1)
    ) u_scope (
        .clk       (clk),
        .rst       (rst),
        .ch0_in    (adc_data[9:0]),
        .ch1_in    (10'd512),      // 板上无 DAC，CH1 暂接中点
        .adc_valid (adc_valid),
        .key_in    (key),
        .cfg_tb_we (cfg_tb_we),   .cfg_tb(cfg_tb),
        .cfg_run_we(cfg_run_we),  .cfg_run(cfg_run),
        .cfg_ten_we(cfg_ten_we),  .cfg_ten(cfg_ten),
        .cfg_lvl_we(cfg_lvl_we),  .cfg_lvl(cfg_lvl),
        .cfg_edg_we(cfg_edg_we),  .cfg_edg(cfg_edg),
        .cfg_scr_we(cfg_scr_we),  .cfg_scr(cfg_scr),
        .cfg_tmode_we(cfg_tmode_we), .cfg_tmode(cfg_tmode),
        .cfg_tsrc_we (cfg_tsrc_we),  .cfg_tsrc(cfg_tsrc),
        .cfg_pre_we  (cfg_pre_we),   .cfg_pre(cfg_pre),
        .cfg_hold_we (cfg_hold_we),  .cfg_hold(cfg_hold),
        .vga_rgb   (vga_rgb),
        .vga_hs    (vga_hs),
        .vga_vs    (vga_vs),
        .vga_de    (vga_de)
    );

    // RGB444 -> RGB888（每 4bit 复制一次，满量程）
    assign vga_r = {vga_rgb[11:8], vga_rgb[11:8]};
    assign vga_g = {vga_rgb[7:4],  vga_rgb[7:4]};
    assign vga_b = {vga_rgb[3:0],  vga_rgb[3:0]};
    assign vga_clk = clk;          // GM7123 像素时钟

    //------------------------------------------------------------------
    // 数码管显示 AD 码值
    //------------------------------------------------------------------
    seg u_seg (
        .clk    (clk),
        .rst_n  (rst_n),
        .point  (4'b0000),
        .data   (adc_data[9:0]),
        .seg_en (1'b1),
        .sign   (1'b0),
        .sel    (sel),
        .seg    (seg)
    );

    //------------------------------------------------------------------
    // 串口上报：每 1ms 发一帧(16bit)
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

    uart_tx #(
        .UART_BPS (115200),
        .CLK_FREQ (CLK_HZ)
    ) u_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .pi_data  (adc_data),
        .pi_flag  (tx_pulse),
        .tx       (uart_tx)
    );

endmodule
