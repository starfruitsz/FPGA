//==============================================================================
// 层: 顶层(SparkRoad-V / EG4S20BG256)  文件: sparkroad_scope_top.v
// 功能: 把示波器移植到 SparkRoad-V：
//   24MHz(K14) -> VGA 640x480@~57Hz(24MHz 像素时钟) -> GM7123 24bit RGB
//   并口 AD/DA 模块(24 脚 AD0..AD9/ADCLK + DA0..DA9/DACLK)
//       -> ad_da_par -> 示波器采集/触发/测量 -> VGA
//   ADRC: CH0(外部 AD 采样) -> y=ch0-512 -> eso.v(每采样一次, sys_clk 域)
//         -> u -> da=clamp(u+512,0,1023) -> DA0..DA9
//   CH0/CH1 数据源由 SW8(N8) 选择: 0=内置函数发生器(CH0/CH1 各自独立一套参数) 1=AD 采样 / ADRC 的 u
//   UART(115200) 接 scope_cmd(VGA 参数)；AD7606 已从本顶层移除
// 说明: VGA 颜色为 RGB444 内部格式，输出时把每 4bit 复制成 8bit。
//       SW8(N8) 拨下=自发生(内置函数发生器)，拨上=AD/DA(外部并口 AD)。
//       ADCLK/DACLK = 系统时钟/8：24MHz 顶层 3.0MHz，25.2MHz PLL 顶层 3.15MHz。
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
    input  wire [8:0]  sw,           // SW0..SW8 (T4/R5/T5/T6/M6/P6/N6/P8, SW8=N8)
    // 串口
    output wire        uart_tx,      // F16
    input  wire        uart_rx,      // E16
    // 并口 AD/DA 模块（24 脚，AD0 为最低位）
    input  wire        ad0,          // AD0..AD9：外部 ADC 并行数据（ad0=LSB）
    input  wire        ad1,
    input  wire        ad2,
    input  wire        ad3,
    input  wire        ad4,
    input  wire        ad5,
    input  wire        ad6,
    input  wire        ad7,
    input  wire        ad8,
    input  wire        ad9,
    output wire        adclk,        // ADCLK = clk/8（24MHz->3MHz / 25.2MHz->3.15MHz）
    output wire        da0,          // DA0..DA9：DA 输出码（da0=LSB），反相沿更新
    output wire        da1,
    output wire        da2,
    output wire        da3,
    output wire        da4,
    output wire        da5,
    output wire        da6,
    output wire        da7,
    output wire        da8,
    output wire        da9,
    output wire        daclk,        // DACLK = clk/8，与 ADCLK 同频同相
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
    output wire [15:0] led           // LED0..15，低电平点亮
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
    // SW8(N8)：工作模式（拨上=ADC 模式，拨下=自发生模式）
    wire sw8_lv;
    sw_edge u_sw8 (.clk(clk), .rst(rst), .sw_in(sw[8]), .lv(sw8_lv), .rise());
    // 函数发生器参数：CH0/CH1 各一套，完全独立（菜单 P1 页分别调整）
    wire [1:0] gen_wave0, gen_wave1;
    wire [2:0] gen_freq0, gen_freq1;
    wire [1:0] gen_amp0,  gen_amp1;
    wire [3:0] gen_phase0, gen_phase1;
    wire       menu_on;
    wire       sel_ch;               // 选中通道 0=CH0 1=CH1（菜单关闭时由 SW2 选择）
    wire [7:0] dbg_status;

    // 演示信号源（DEMO_SINE=1 时不接 ADC，用内置函数发生器给示波器灌信号）
    //   上电后自动下发一次 T0 / A1 / M1 / L512：
    //     T0    -> tb_div=0（ADC 侧已经给好采样率，前端不再分频）
    //     A1    -> 触发使能
    //     M1    -> 连续刷新（跟踪模式，画面实时跟随信号；改成 M2 则为单次冻结）
    //     L512  -> 触发电平 = 中点
    //------------------------------------------------------------------
    wire [9:0] gen0_data, gen1_data;
    wire       gen0_valid, gen1_valid;

    // 内置函数发生器 x2：CH0 用 u_gen0、CH1 用 u_gen1，参数各自独立
    //   DDS 波形可选（正弦/方波/三角/锯齿）+ 8 档频率 + 4 档幅度 + 10 档相位
    //   两个实例的 CLK_HZ/FS_HZ 相同，所以 valid 节拍天然对齐（同一拍出采样点），
    //   采集侧只用一个采样节拍就能同时取到两路数据。
    func_gen #(.CLK_HZ(CLK_HZ), .FS_HZ(12_000)) u_gen0 (
        .clk(clk), .rst(rst),
        .wave(gen_wave0), .freq_sel(gen_freq0), .amp_sel(gen_amp0), .phase_idx(gen_phase0),
        .data(gen0_data), .valid(gen0_valid)
    );

    func_gen #(.CLK_HZ(CLK_HZ), .FS_HZ(12_000)) u_gen1 (
        .clk(clk), .rst(rst),
        .wave(gen_wave1), .freq_sel(gen_freq1), .amp_sel(gen_amp1), .phase_idx(gen_phase1),
        .data(gen1_data), .valid(gen1_valid)
    );

    //------------------------------------------------------------------
    // 工作模式 SW8(N8)
    //   0 = 自发生模式: CH0 显示 u_gen0 的 gen0_data，CH1 显示 u_gen1 的 gen1_data
    //       （两个函数发生器各有一套 wave/freq/amp/phase，菜单 P1 页分别调整；
    //         上电默认 CH0=正弦满幅、CH1=方波半幅，一眼就能看出两路互相独立）
    //   1 = AD/DA 模式: CH0 显示外部并口 AD 采样值 ad_val，
    //                    CH1 显示 ADRC(eso) 算出的控制量 u（偏移二进制 u+512）
    //   模式同时送进 vga_scope_top：ADC 模式下内置信号源相关路径全部关闭，
    //   触发源与自动量程也跟着 ch0 的数据源走（见 vga_scope_top 的 mode_chg）。
    //------------------------------------------------------------------
    wire adc_mode = sw8_lv;

    //------------------------------------------------------------------
    // 并口 AD/DA 引脚（外接 24 脚: AD0..AD9 + ADCLK，DA0..DA9 + DACLK）
    //   引脚是 10 个独立端口（约束文件里叫 ad0..ad9 / da0..da9），这里拼成
    //   内部总线：ad0/da0 是最低位，与模块丝印 AD0/DA0 一一对应。
    //------------------------------------------------------------------
    wire [9:0] ad_bus = {ad9, ad8, ad7, ad6, ad5, ad4, ad3, ad2, ad1, ad0};
    wire [9:0] da_bus;

    assign da0 = da_bus[0];
    assign da1 = da_bus[1];
    assign da2 = da_bus[2];
    assign da3 = da_bus[3];
    assign da4 = da_bus[4];
    assign da5 = da_bus[5];
    assign da6 = da_bus[6];
    assign da7 = da_bus[7];
    assign da8 = da_bus[8];
    assign da9 = da_bus[9];

    //------------------------------------------------------------------
    // 并口 AD/DA 驱动（FPGA/src/ad_da_par.v）
    //   ADCLK/DACLK = 系统时钟 / 8，占空比 50%
    //       24MHz   主板 -> 3.0MHz
    //       25.2MHz PLL -> 3.15MHz（板级实际使用 sparkroad_scope_pll）
    //   AD: adclk 反相沿锁存 ad_bus -> 两拍同步 -> ad_val/ad_val_valid
    //   DA: daclk 反相沿更新 da_out -> da_bus -> DA0..DA9
    //       数据保持一个完整 DACLK 周期，外部 DAC 在正相沿锁存
    //------------------------------------------------------------------
    wire [9:0] ad_val;                  // 同步后的外部 AD 采样值（= ch0）
    wire       ad_val_valid;            // 外部 AD 采样有效（单拍，每周期一次）
    wire [9:0] da_loop;                 // DA 锁存后的回环值

    //------------------------------------------------------------------
    // ADRC 链路（FPGA/src/eso.v，算法与参数未改，只加了采样使能 en）
    //   ch0    = ad_val                 （AD 采样值，0..1023）
    //   y      = ch0 - 512              （搬到零点，-512..+511）
    //   eso    = 扩展状态观测器 + 状态误差反馈，每个有效采样算一次 u
    //   da     = clamp(u + 512, 0, 1023)（偏移二进制，驱动 DA0..DA9）
    //
    //   时钟域：eso 跑在 sys_clk（clk）域，en = ad_val_valid && adc_mode，
    //   每来一个有效采样只推进一拍，绝不拿 adclk 当寄存器时钟。
    //   自发生模式（SW8=0）下 en=0，观测器状态与 DA 输出都保持不动。
    //   B01/B02/B03/b0 保持 eso.v 的 parameter 默认值（90/2700/27000/5000），
    //   调参走"改 parameter 再综合"的离线流程，见 ADRC_TUNING.md。
    //------------------------------------------------------------------
    // 位宽：ad_val 是 0..1023 的无符号码，先补 1 位再做有符号减法，
    //       否则 >511 的码会被当成负数（10bit 有符号只有 -512..511）。
    wire signed [10:0] ad_y11 = $signed({1'b0, ad_val}) - 11'sd512;
    wire signed [9:0]  ad_y   = ad_y11[9:0];        // -512..+511 正好装进 10bit 补码
    wire signed [9:0]  eso_u;                       // eso 输出的控制量 u（有符号补码）
    wire signed [10:0] u_off  = eso_u + 11'sd512;   // 偏移二进制，正常范围 0..1023

    // clamp(u+512, 0, 1023)：u 正常不会越界，这里是对观测器发散/毛刺的兜底
    wire [9:0] adrc_da = (u_off < 11'sd0)    ? 10'd0    :
                         (u_off > 11'sd1023) ? 10'd1023 : u_off[9:0];

    // 只有 AD/DA 模式才推进观测器；自发生模式整条 ADRC 链路保持
    wire adrc_en = ad_val_valid && adc_mode;

    eso u_eso (
        .ad_clk    (clk),           // 系统时钟域（不是 adclk）
        .sys_rst_n (rst_n),         // eso 的复位是低有效
        .en        (adrc_en),       // 每个有效采样推进一次（自发生模式保持）
        .e_in      (ad_y),          // y = ad_val - 512（eso 内部会再取负）
        .u_out     (eso_u),         // 控制量反馈：与 out_da 同源，构成 u(k-1)
        .out_da    (eso_u),
        .c_flag    (1'b0),          // 参数在线改写未启用：保持 c=150、k=20
        .k_flag    (1'b0),
        .c_date    (12'd150),
        .k_date    (12'd20),
        .z1k0      (),
        .z2k0      (),
        .z3k0      ()
    );

    //------------------------------------------------------------------
    // 通道数据源选择
    //   自发生(SW8=0): CH0 = gen0_data、CH1 = gen1_data
    //                  （两路是各自独立的函数发生器，参数互不影响）
    //   AD/DA  (SW8=1): CH0 = ad_val(AD 采样)  CH1 = adrc_da(u+512)
    //                  （这一路行为完全没变）
    //   采样有效：两个发生器同节拍，取"或"既覆盖也对齐；AD 模式用外部 AD 的 valid。
    //------------------------------------------------------------------
    wire [9:0] ch0_val;                 // CH0 源值（送显示/采集/测量/自动量程）
    wire [9:0] ch1_val;                 // CH1 源值（送显示/采集）
    wire       ch_val;                  // 采样有效

    assign ch0_val = adc_mode ? ad_val  : gen0_data;
    assign ch1_val = adc_mode ? adrc_da : gen1_data;
    assign ch_val  = adc_mode ? ad_val_valid : (gen0_valid | gen1_valid);

    // 自发生模式：DA 输入回接自身锁存值 -> 每个反相沿只是重锁同一个码，
    // 引脚保持最后一次 AD/DA 模式算出的电压（"AD/DA 输出保持"）。
    wire [9:0] da_src = adc_mode ? adrc_da : da_loop;

    ad_da_par #(.DIV_LOG2(3)) u_ad_da (
        .clk     (clk),
        .rst     (rst),
        .ad_data (ad_bus),
        .ad_clk  (adclk),           // ADCLK 输出
        .s_data  (ad_val),
        .s_valid (ad_val_valid),
        .da_data (da_src),          // AD 模式 = clamp(u+512)；自发生模式保持
        .da_clk  (daclk),           // DACLK 输出（与 ADCLK 同频同相）
        .da_out  (da_loop)
    );

    assign da_bus = da_loop;            // DA0..DA9 直接来自锁存后的码值

    reg [7:0] boot_cnt;
    always @(posedge clk) begin
        if (rst) boot_cnt <= 8'd0;
        else if (boot_cnt != 8'hFF) boot_cnt <= boot_cnt + 8'd1;
    end

    // 自发生模式(SW8=0)与编译期演示固件(DEMO_SINE=1)都走一遍演示配置，
    // 上电自动给出 T0/A1/M1/L512，不接外部模块也能直接看到稳定波形
    wire demo_cfg = (DEMO_SINE != 0) || (!adc_mode);
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
        .GEN_ENA(1)              // 信号源始终存在；ADC 模式下由 adc_mode 动态关闭
    ) u_scope (
        .clk       (clk),
        .rst       (rst),
        .ch0_in    (ch0_val),
        .ch1_in    (ch1_val),
        .adc_valid (ch_val),
        .adc_mode  (adc_mode),     // ADC 模式: 关掉内置信号源(GEN_ENA)相关路径
        .key_n     (key_n),
        .sw_menu   (sw0_lv),          // 电平：拨上=菜单开
        .sw_run    (sw1_lv),          // 电平：拨上=运行
        .sw_page   (sw2_lv),          // 电平：拨上=信号源页
        .sw_roll   (sw3_lv),          // 电平：拨上=滚动模式（与串口 S 命令同源）
        .sw_roll2  (sw5_lv),          // SW5(P6) 滚动开关
        .sw_auto   (sw4_lv),          // SW4(M6) 自动量程
        .sw_hzfree (sw6_lv),          // SW6(N6) 横轴缩放不设上限
        .sw_move   (sw7_lv),          // SW7(P8) U/D 移动基线
        // 上电自动配置(T0/A1/M1/L512)与串口配置并存，串口后写优先：
        //   自发生模式(SW8=0)和演示固件(DEMO_SINE=1)上电自动下发一次，
        //   之后串口命令随时可以改（不会被演示配置一直压住）。
        .cfg_tb_we (demo_tb_we | cfg_tb_we),    .cfg_tb(cfg_tb_we ? cfg_tb : 16'd0),
        .cfg_run_we(cfg_run_we),  .cfg_run(cfg_run),
        .cfg_ten_we(demo_ten_we | cfg_ten_we),  .cfg_ten(cfg_ten_we ? cfg_ten : 1'b1),
        .cfg_lvl_we(demo_lvl_we | cfg_lvl_we),  .cfg_lvl(cfg_lvl_we ? cfg_lvl : 10'd512),
        .cfg_edg_we(cfg_edg_we),  .cfg_edg(cfg_edg),
        .cfg_scr_we(cfg_scr_we),  .cfg_scr(cfg_scr),
        // 演示用 M1(normal)：采满一屏后自动重触发，画面实时跟随信号；
        //   串口 M2(single) 发下来后走单次冻结。
        .cfg_tmode_we(demo_tmode_we | cfg_tmode_we), .cfg_tmode(cfg_tmode_we ? cfg_tmode : 2'd1),
        .cfg_tsrc_we (cfg_tsrc_we),  .cfg_tsrc(cfg_tsrc),
        .cfg_pre_we  (cfg_pre_we),   .cfg_pre(cfg_pre),
        .cfg_hold_we (cfg_hold_we),  .cfg_hold(cfg_hold),
        .vga_rgb   (vga_rgb),
        .vga_hs    (vga_hs),
        .vga_vs    (vga_vs),
        .vga_de    (vga_de),
        .gen_wave0 (gen_wave0),
        .gen_freq0 (gen_freq0),
        .gen_amp0  (gen_amp0),
        .gen_phase0(gen_phase0),
        .gen_wave1 (gen_wave1),
        .gen_freq1 (gen_freq1),
        .gen_amp1  (gen_amp1),
        .gen_phase1(gen_phase1),
        .menu_on_o (menu_on),
        .sel_ch_o  (sel_ch),
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
    // 演示固件显示采集完成次数；正常固件显示外部 AD 采样码值
    wire [9:0] seg_data = (DEMO_SINE != 0) ? cap_cnt : ad_val;
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
        .pi_data  ({6'd0, ad_val}),   // 串口上报外部 AD 采样码值
        .pi_flag  (tx_req),
        .tx       (uart_tx)
    );

    //------------------------------------------------------------------
    // LED 调试指示（16 个，低电平点亮）
    //   LED[15:9] = 预留（以前的电平条会随波形闪烁，先关掉）
    //   LED[8]    = 选中通道（菜单关闭时 SW2 选择：亮=CH1 灭=CH0）
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

    wire [15:0] led_map = { 7'h00,          // 15:9 预留
                            sel_ch,          // 8 选中通道（1=CH1）
                            dbg_status[2],   // 7 运行
                            dbg_status[3],   // 6 滚动
                            dbg_status[0],   // 5 菜单
                            trig_hi,         // 4 触发命中
                            done_hi,         // 3 采集完成
                            dbg_status[5:4], // 2:1 采集状态
                            (DEMO_SINE != 0) }; // 0 信号源使能

    assign led = ~led_map;                // 低电平点亮

endmodule