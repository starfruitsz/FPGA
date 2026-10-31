//==============================================================================
// 层: 顶层(集成)  文件: vga_scope_top.v   [v3: 双路独立信号源参数 / 菜单 P1 8 项]
// 装配 HAL/ABS/APP，不含算法。像素流水线与 v1 相同：
//   像素周期 = PIX_DIV 个 clk；BSRAM 同步读 1 拍；后半拍求值，pix_ce 打寄存器；
//   hs/vs/de 固定延迟 2 拍（=1 像素）对齐。
// 新增连线：
//   - 触发源选择(trig_src) → capture.trig_din
//   - capture.state/rd_base → 显示读地址(触发基准) 与状态显示
//   - meas 扩展输出 → 文本第 2 页
//   - 信号源参数两套（gen_*0 / gen_*1）→ 板级顶层两个 func_gen 实例；
//     菜单 P1 页 8 项（CH0/CH1 各 WAV/FRE/ATT/PHA）由 menu_layer 显示
//==============================================================================
`timescale 1ns / 1ps

module vga_scope_top #(
    parameter integer H_VIS     = 640,
    parameter integer H_FP      = 16,
    parameter integer H_SYNC    = 96,
    parameter integer H_BP      = 48,
    parameter integer V_VIS     = 480,
    parameter integer V_FP      = 10,
    parameter integer V_SYNC    = 2,
    parameter integer V_BP      = 33,
    parameter integer H_POL     = 0,
    parameter integer V_POL     = 0,
    parameter integer PIX_DIV   = 2,
    parameter integer PLOT_H    = 448,
    parameter integer GRID_STEP = 64,
    parameter integer AXIS_Y    = 224,
    parameter integer TEXT_Y0   = 448,
    parameter integer TEXT_X0   = 8,
    parameter integer DEPTH_LOG2 = 10,
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer FEAT_TRIG   = 1,
    parameter integer FEAT_MEAS   = 1,
    parameter integer FEAT_SCROLL = 1,
    parameter integer FEAT_UART   = 1,
    parameter integer GEN_ENA     = 1,   // 1=内置函数发生器可用(ADC 未接) 0=走外部 ADC，信号源菜单失效
    parameter [11:0] COL_BG   = 12'h012,
    parameter [11:0] COL_GRID = 12'h151,
    parameter [11:0] COL_AXIS = 12'h2A2,
    parameter [11:0] COL_CH0  = 12'h1F1,
    parameter [11:0] COL_CH1  = 12'hFF1,
    parameter [11:0] COL_TEXT = 12'hFFF
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  ch0_in,
    input  wire [9:0]  ch1_in,
    input  wire        adc_valid,   // ADC 采样有效(S2: 由 adc_top 提供)
    input  wire        adc_mode,      // 1=ADC 模式(SW8)：关闭内置信号源(GEN_ENA)相关路径
    input  wire [3:0]  key_n,         // {U,D,L,R} 4 个按键，低有效
    input  wire        sw_menu,       // SW0 上升沿: 菜单开/关
    input  wire        sw_run,        // SW1 上升沿: 运行/冻结
    input  wire        sw_page,       // SW2 电平  : 菜单开=信号源页；菜单关=通道选择(1=CH1)
    input  wire        sw_roll,       // SW3 电平: 滚动模式
    input  wire        sw_roll2,      // SW5 备用滚动开关
    input  wire        sw_auto,       // SW4：1=自动量程（持续自适应）
    input  wire        sw_hzfree,     // SW6：1=横轴缩放不设上限
    input  wire        sw_move,       // SW7：1=U/D 移动基线

    // 串口配置
    input  wire        cfg_tb_we,    input wire [15:0] cfg_tb,
    input  wire        cfg_run_we,   input wire        cfg_run,
    input  wire        cfg_ten_we,   input wire        cfg_ten,
    input  wire        cfg_lvl_we,   input wire [9:0]  cfg_lvl,
    input  wire        cfg_edg_we,   input wire        cfg_edg,
    input  wire        cfg_scr_we,   input wire        cfg_scr,
    input  wire        cfg_tmode_we, input wire [1:0]  cfg_tmode,
    input  wire        cfg_tsrc_we,  input wire        cfg_tsrc,
    input  wire        cfg_pre_we,   input wire [9:0]  cfg_pre,
    input  wire        cfg_hold_we,  input wire [15:0] cfg_hold,

    output wire [11:0] vga_rgb,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_de,
    // 函数发生器设置（送到板级顶层驱动两路内置信号源）
    //   CH0/CH1 各一套完全独立的参数，板级顶层据此例化两个 func_gen 实例
    output wire [1:0]  gen_wave0,    // CH0 波形
    output wire [2:0]  gen_freq0,    // CH0 频率档
    output wire [1:0]  gen_amp0,     // CH0 幅度档
    output wire [3:0]  gen_phase0,   // CH0 相位档 0..9
    output wire [1:0]  gen_wave1,    // CH1 波形
    output wire [2:0]  gen_freq1,    // CH1 频率档
    output wire [1:0]  gen_amp1,     // CH1 幅度档
    output wire [3:0]  gen_phase1,   // CH1 相位档 0..9
    output wire        menu_on_o,
    output wire        sel_ch_o,     // 选中通道 0=CH0 1=CH1（菜单关闭时由 SW2 选择）
    output wire [7:0]  dbg_status    // {done,trig,state[1:0],scroll,run,roll,menu}
);

    //------------------------------------------------------------------
    // HAL: 时序
    //------------------------------------------------------------------
    wire        pix_ce;
    wire        hs, vs, de;
    wire [11:0] px, py;

    vga_timing #(
        .H_VIS(H_VIS), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_VIS(V_VIS), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .H_POL(H_POL), .V_POL(V_POL), .PIX_DIV(PIX_DIV)
    ) u_timing (
        .clk(clk), .rst(rst), .pix_ce(pix_ce),
        .hs(hs), .vs(vs), .de(de), .px(px), .py(py)
    );

    reg vs_d;
    always @(posedge clk) vs_d <= vs;
    wire frame = vs & (~vs_d);

    //------------------------------------------------------------------
    // APP: 配置与状态
    //------------------------------------------------------------------
    wire        run, arm;
    wire [15:0] tb_div;
    wire        trig_en, trig_src, trig_edge, scroll_en;
    wire [1:0]  trig_mode;
    wire [9:0]  trig_level, pre_trig;
    wire [15:0] holdoff;
    wire        page;
    wire [2:0]  state_o;

    wire [9:0] s0, s1;
    wire        we0, we1;
    wire [DEPTH_LOG2-1:0] wa0, wa1;
    wire        done0, done1, trig_det0;
    wire [DEPTH_LOG2-1:0] rd_base0, rd_base1;
    wire [1:0]  state0, state1;
    wire        buf_wr0, buf_disp0, buf_wr1, buf_disp1;

    // 按键配置（由 scope_app 产生）
    wire        ch0_en, ch1_en;
    wire [2:0]  vsc0, vsc1;
    wire [3:0]  pos0, pos1;          // 垂直位置档位 0..9（5=居中）
    wire        roll;
    wire [6:0]  hscale;              // 横轴缩放系数 S(1..102): pxz=(px*S)>>6，64=1:1
    wire signed [12:0] yoff;         // 基线偏移（SW7 时由 U/D 调整）
    wire        menu_page;
    wire [3:0]  tb_idx;
    wire        menu_on;
    wire [3:0]  menu_sel;

    //------------------------------------------------------------------
    // 自动量程（SW4）：0.5s 统计一次两路峰值，选"刚好装得下"的档位
    //   两路同时进 autoset（din0=ch0_in、din1=ch1_in）：
    //     - 每路各自统计 vmax/vmin -> 峰值 peak0/peak1、中点 mid0/mid1
    //     - 档位只看 peak_out = max(peak0, peak1)：两通道共用同一档，
    //       按"幅度大的那一路也装得下"来选，于是两路同时落在屏幕内；
    //     - 中点分开用：fine0 跟 mid0、fine1 跟 mid1，各回各的中心。
    //   注意：自动量程只改档位和居中偏移，绝不碰 ch0_en/ch1_en
    //        （通道显示与否只由菜单/按键决定）。
    //------------------------------------------------------------------
    wire [2:0] vs_auto;
    wire [9:0] mid_auto0, mid_auto1;
    wire [9:0] peak_auto;            // 两路峰值里较大的那个（对称峰值，供夹紧用）
    wire       as_busy;

    scope_autoset u_auto (
        .clk(clk), .rst(rst), .en(sw_auto),
        .din0(ch0_in), .din1(ch1_in), .valid(adc_valid), .tb_div(tb_div), .frame(frame),
        .vs_out(vs_auto),
        .mid_out0(mid_auto0), .mid_out1(mid_auto1),
        .peak_out(peak_auto), .busy(as_busy)
    );

    // SW4 拨上：用自动档；拨下：回到手动档（菜单 VS 项/按键）
    wire [2:0] vsc0_eff = sw_auto ? vs_auto : vsc0;
    wire [2:0] vsc1_eff = sw_auto ? vs_auto : vsc1;

    // 精细居中：y = 223 - (s-512)*7/2^vs + voff，要把中点放在 y=223，
    // 就要 voff = +(mid-512)*7/2^vs（符号不能反：mid>512 时波形偏上，
    // 需要往下压，也就是 voff 必须为正）。只在 SW4 拨上时生效。
    //   两路各用各的中点（CH0 用 mid0、CH1 用 mid1）：每路波形都绕 y=223
    //   对称展开；档位又是按 max(peak0,peak1) 选的，半幅不超过 201 像素，
    //   所以两路一定同时完整落在 0..447 的绘图区里。
    wire signed [12:0] mid_d0 = $signed({3'b000, mid_auto0}) - 13'sd512;
    wire signed [12:0] mid_d1 = $signed({3'b000, mid_auto1}) - 13'sd512;
    wire signed [12:0] fine_raw0 = (mid_d0 * 13'sd7) >>> vsc0_eff;
    wire signed [12:0] fine_raw1 = (mid_d1 * 13'sd7) >>> vsc1_eff;
    wire signed [12:0] fine0  = sw_auto ? fine_raw0 : 13'sd0;
    wire signed [12:0] fine1  = sw_auto ? fine_raw1 : 13'sd0;

    //------------------------------------------------------------------
    // 基线夹紧（SW7 手动移基线时用）：两路共用 autoset 给的同一个对称峰值
    //   波形半幅 zp = peak_out * 7 / 2^vs（与 trace_layer 的映射同一套式子）
    //   向下推：上沿 223 - zp + voff 不能越过 447-4=443 -> voff <= 220 + zp
    //   向上推：下沿 223 + zp + voff 不能越过 0+4=4   -> voff >= -(220 + zp)
    //   两路按各自档位换算，但输入是同一份 peak_out —— 谁都不会被挤出屏幕。
    //   饱和说明：peak<=1023、vs>=2 -> 220+zp <= 2010，13bit 有符号够用。
    //------------------------------------------------------------------
    wire signed [18:0] pk_x  = $signed({9'b0, peak_auto});
    wire signed [18:0] zpk0  = (pk_x * 19'sd7) >>> vsc0_eff;
    wire signed [18:0] zpk1  = (pk_x * 19'sd7) >>> vsc1_eff;
    wire signed [18:0] lim0  = 19'sd220 + zpk0;
    wire signed [18:0] lim1  = 19'sd220 + zpk1;
    wire signed [12:0] ylim0 = lim0[12:0];
    wire signed [12:0] ylim1 = lim1[12:0];

    // 档位 -> 像素偏移：每档 24 像素，(5) 为居中；再叠加精细居中
    //   SW7 打开时改由 yoff 控制基线，并把 yoff 夹紧到上面算出的基线范围
    //   （基线可以移到屏外，但波形至少留 4 像素可见）。
    //------------------------------------------------------------------
    wire signed [12:0] yoff0    = (yoff >  ylim0) ?  ylim0 : (yoff < -ylim0) ? -ylim0 : yoff;
    wire signed [12:0] yoff1    = (yoff >  ylim1) ?  ylim1 : (yoff < -ylim1) ? -ylim1 : yoff;
    wire signed [12:0] base0 = sw_move ? yoff0 : (($signed({9'b0, pos0}) - 13'sd5) * 13'sd24);
    wire signed [12:0] base1 = sw_move ? yoff1 : (($signed({9'b0, pos1}) - 13'sd5) * 13'sd24);
    wire signed [12:0] voff0 = base0 + fine0;
    wire signed [12:0] voff1 = base1 + fine1;

    //------------------------------------------------------------------
    // 工作模式(SW8): GEN_ENA 是编译期参数，这里再串一层运行期开关
    //   ADC 模式下作用与 GEN_ENA=0 完全一致: 信号源菜单页失效、GEN 相关菜单项不可调
    //------------------------------------------------------------------
    wire gen_ena_eff = (GEN_ENA != 0) && (!adc_mode);

    //------------------------------------------------------------------
    // 模式切换(SW8)时，触发源/自动量程都要跟着 ch0 的数据源走
    //   - 自动量程 scope_autoset 两路都吃（din0=ch0_in、din1=ch1_in），ch0_in 在顶层已按模式切换；
    //   - 触发源却可以被串口 TSRC 设成 CH1，而 AD/DA 模式下 CH1 是控制量 u，
    //     对着 u 触发的话屏幕上根本看不到输入波形。所以模式一进 ADC，
    //     就把触发源强制拉回 CH0(被测信号 ad_val)。
    //   - 借用 scope_app 已有的 ext_tsrc 写通道下发（它写 trig_src 的同时会 arm
    //     一次），这样切换瞬间采集会重新布防，不会把两种数据源混在同一屏里。
    //   ADC 模式退出后(自发生模式)，触发源恢复成串口设置的值(默认 CH0)。
    //------------------------------------------------------------------
    reg adc_mode_d;
    always @(posedge clk) begin
        if (rst) adc_mode_d <= 1'b0;
        else     adc_mode_d <= adc_mode;
    end
    wire mode_chg  = adc_mode ^ adc_mode_d;          // 模式变化的单拍脉冲
    wire tsrc_we_e = (FEAT_UART ? cfg_tsrc_we : 1'b0) | mode_chg;
    wire tsrc_e    = adc_mode ? 1'b0 : cfg_tsrc;     // ADC 模式: 触发源固定 CH0

    scope_app #(
        .CLK_HZ(CLK_HZ)
    ) u_app (
        .gen_ena(gen_ena_eff),
        .sw_menu(sw_menu), .sw_run(sw_run), .sw_page(sw_page),
        .sw_roll(sw_roll), .sw_roll2(sw_roll2),
        .clk(clk), .rst(rst), .key_n(key_n),
        .ext_tb_we(cfg_tb_we),       .ext_tb(cfg_tb),
        .ext_run_we(cfg_run_we),     .ext_run(cfg_run),
        .ext_ten_we(cfg_ten_we),     .ext_ten(cfg_ten),
        .ext_lvl_we(cfg_lvl_we),     .ext_lvl(cfg_lvl),
        .ext_edg_we(cfg_edg_we),     .ext_edg(cfg_edg),
        .ext_scr_we(cfg_scr_we),     .ext_scr(cfg_scr),
        .ext_tmode_we(FEAT_UART ? cfg_tmode_we : 1'b0), .ext_tmode(cfg_tmode),
        .ext_tsrc_we (tsrc_we_e), .ext_tsrc(tsrc_e),   // 模式切换也会走这条写通道
        .ext_pre_we  (FEAT_UART ? cfg_pre_we   : 1'b0), .ext_pre(cfg_pre),
        .ext_hold_we (FEAT_UART ? cfg_hold_we  : 1'b0), .ext_hold(cfg_hold),
        .cap_done(done0), .cap_state(state0),
        .tb_div(tb_div), .run(run), .arm(arm),
        .trig_en(trig_en), .trig_mode(trig_mode), .trig_src(trig_src),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .scroll_en(scroll_en), .tb_idx(tb_idx), .page(page), .state_o(state_o),
        .ev_short_o(), .ev_long_o(),
        .ch0_en(ch0_en), .ch1_en(ch1_en), .sel_ch(sel_ch_o),
        .vs0(vsc0), .vs1(vsc1), .pos0(pos0), .pos1(pos1),
        .roll(roll), .hscale(hscale), .yoff(yoff), .menu_page(menu_page),
        .sw_hzfree(sw_hzfree), .sw_move(sw_move),
        // 两套完全独立的信号源参数（菜单 P1 的 0..3 改 CH0、4..7 改 CH1）
        .wave0(gen_wave0),  .fsel0(gen_freq0),  .asel0(gen_amp0),  .phase0(gen_phase0),
        .wave1(gen_wave1),  .fsel1(gen_freq1),  .asel1(gen_amp1),  .phase1(gen_phase1),
        .menu_on(menu_on), .menu_sel(menu_sel)
    );

    assign menu_on_o = menu_on;
    // roll 与 scroll_en 现在是同一份状态，这里并排放是为了兼容老的 LED 位定义
    assign dbg_status = {done0, trig_det0, state0, scroll_en, run, roll, menu_on};

    //------------------------------------------------------------------
    // APP: 采集（两通道共用参数，触发源可选 CH0/CH1）
    //------------------------------------------------------------------

    wire [9:0] trig_din = trig_src ? ch1_in : ch0_in;

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap0 (
        .clk(clk), .rst(rst),
        .din(ch0_in), .trig_din(trig_din),
        .rate_div(tb_div), .sample_valid(adc_valid), .run(run), .arm(arm),
        .trig_en(FEAT_TRIG ? trig_en : 1'b0),
        .trig_mode(trig_mode), .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        // 滚动模式必须同时告诉采集侧：自由循环写、不响应触发、不翻乒乓半区
        .roll(FEAT_SCROLL ? scroll_en : 1'b0),
        .we(we0), .waddr(wa0), .trig_det(trig_det0), .done(done0),
        .rd_base(rd_base0), .state(state0),
        .buf_wr(buf_wr0), .buf_disp(buf_disp0)
    );

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) u_cap1 (
        .clk(clk), .rst(rst),
        .din(ch1_in), .trig_din(trig_din),
        .rate_div(tb_div), .sample_valid(adc_valid), .run(run), .arm(arm),
        .trig_en(FEAT_TRIG ? trig_en : 1'b0),
        .trig_mode(trig_mode), .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .roll(FEAT_SCROLL ? scroll_en : 1'b0),
        .we(we1), .waddr(wa1), .trig_det(), .done(done1),
        .rd_base(rd_base1), .state(state1),
        .buf_wr(buf_wr1), .buf_disp(buf_disp1)
    );

    //------------------------------------------------------------------
    // 读地址：显示缓冲区 + 触发基准 + 像素列（乒乓双缓冲）
    //   每通道 RAM 深度 2x1024：一半正在写、另一半正在显示，互不干扰，
    //   因此跟踪模式下不再出现"新数据覆盖到哪就断在哪"的截断。
    //   滚动状态 scroll_en 由 scope_app 统一给出（SW3 电平变化 / 菜单 ROL /
    //   串口 S 三处都能改），这里只做二选一：
    //     scroll_en=1 -> 读正在写的那半(buf_wr)，地址 = 帧基准-640+px，最右列最新
    //     scroll_en=0 -> 读已采完的那半(buf_disp)，触发 + 乒乓换页
    //   换回乒乓时 buf_disp 只在 FILL 采满一屏后才更新，所以不会切到半屏数据。
    //------------------------------------------------------------------
    wire [DEPTH_LOG2:0] raddr0, raddr1;

    //------------------------------------------------------------------
    // 显示触发基准：只在"捕获完成"那一刻跟随 rd_base 更新
    //    rd_base 在每次 arm 时会清 0，而屏幕这时还在显示上一屏的缓冲；
    //    若直接用 rd_base 做读地址，画面会在每次重新布防后整体平移一次
    //    （看上去像"慢慢滚动/跳变"）。把基准和 buf_disp 一起在 done 时锁存，
    //    显示的基准与显示的半区就永远属于同一屏。
    //------------------------------------------------------------------
    reg [DEPTH_LOG2-1:0] rd_base_d0, rd_base_d1;
    always @(posedge clk) begin
        if (rst) begin
            rd_base_d0 <= {DEPTH_LOG2{1'b0}};
            rd_base_d1 <= {DEPTH_LOG2{1'b0}};
        end
        else begin
            if (done0) rd_base_d0 <= rd_base0;
            if (done1) rd_base_d1 <= rd_base1;
        end
    end

    //------------------------------------------------------------------
    // 横轴缩放：像素列 -> 采样地址（连续，没有档位台阶）
    //   pxz = (px * S) >> 6      S = scope_app 输出的 7bit 缩放系数(1..102)
    //     S = 64  -> 1:1（640 像素正好覆盖 640 个点）
    //     S < 64  -> 放大（S=32 即 2 倍，S=1 时 640 像素只覆盖 10 个点 = 64 倍）
    //     S = 102 -> 约"适应全屏"（640 像素覆盖 1018 个点，已经贴住 1024 缓冲深度）
    //   S 每变 1/8，屏幕上的水平比例就变 1/8，所以长按 L/R 时是丝滑缩放。
    //   位宽：px 最大 799、S 最大 102，积最大 81498（17bit，不会溢出）；
    //   取积的 bit[15:6] 就是 (px*S)>>6 的低 10 位 —— 可见区 px<=639 时
    //   结果最大 1018，不会截断；消隐期 px>639 时被 de 屏蔽，取模不影响显示。
    //------------------------------------------------------------------
    wire [16:0] px_mul = px[9:0] * {10'b0, hscale};
    wire [9:0]  pxz    = px_mul[15:6];

    generate
        if (FEAT_SCROLL != 0) begin : g_scroll
            reg [DEPTH_LOG2-1:0] rd_base_s;
            always @(posedge clk) begin
                if (rst)        rd_base_s <= {DEPTH_LOG2{1'b0}};
                else if (frame) rd_base_s <= wa0;
            end
            wire [9:0] ra0 = scroll_en ? (rd_base_s - 10'd640 + pxz) : (rd_base_d0 + pxz);
            wire [9:0] ra1 = scroll_en ? (rd_base_s - 10'd640 + pxz) : (rd_base_d1 + pxz);
            // 滚动模式是"纸带式实时"，必须显示正在写入的那半（采集侧此时不会翻半区）；
            // 触发刷新模式显示已采完的那半（乒乓双缓冲，不截断）
            assign raddr0 = {scroll_en ? buf_wr0 : buf_disp0, ra0};
            assign raddr1 = {scroll_en ? buf_wr1 : buf_disp1, ra1};
        end
        else begin : g_noscroll
            assign raddr0 = {buf_disp0, (rd_base_d0 + pxz)};
            assign raddr1 = {buf_disp1, (rd_base_d1 + pxz)};
        end
    endgenerate

    vram_sdp #(.DW(10), .AW(DEPTH_LOG2+1)) u_ram0 (
        .clk(clk), .we(we0), .waddr({buf_wr0, wa0}), .wdata(ch0_in),
        .raddr(raddr0), .rdata(s0)
    );
    vram_sdp #(.DW(10), .AW(DEPTH_LOG2+1)) u_ram1 (
        .clk(clk), .we(we1), .waddr({buf_wr1, wa1}), .wdata(ch1_in),
        .raddr(raddr1), .rdata(s1)
    );

    reg [9:0] s0_prev, s1_prev;
    always @(posedge clk) begin
        s0_prev <= s0;
        s1_prev <= s1;
    end

    //------------------------------------------------------------------
    // APP: 测量（扩展）
    //------------------------------------------------------------------
    wire [9:0]  vpp, vmax, vmin, vmean;
    wire [15:0] freq, period;
    wire [7:0]  duty;

    generate
        if (FEAT_MEAS != 0) begin : g_meas
            scope_meas u_meas (
                .clk(clk), .rst(rst), .din(ch0_in), .tick(we0),   // 用采样节拍统计
                .frame(frame),
                .vpp(vpp), .vmax(vmax), .vmin(vmin), .vmean(vmean),
                .freq(freq), .period(period), .duty(duty)
            );
        end
        else begin : g_nomeas
            assign vpp = 10'd0; assign vmax = 10'd0; assign vmin = 10'd0; assign vmean = 10'd0;
            assign freq = 16'd0; assign period = 16'd0; assign duty = 8'd0;
        end
    endgenerate

    //------------------------------------------------------------------
    // 图层坐标对齐（修复 PIX_DIV=1 时最后一列丢失 / 网格文字左移 1 像素）
    //   三条路径的拍数原本不一致：
    //     网格/文字：px -> 组合逻辑      -> rgb_r  = 1 拍
    //     波形     ：px -> BSRAM同步读 -> 组合 -> rgb_r = 2 拍
    //     同步     ：de -> de1 -> de2             = 2 拍
    //   PIX_DIV=2 时 px 两拍才变一次，1 拍差被吸收；PIX_DIV=1 时则暴露成 1 像素。
    //   这里把 px/py/de 统一打一拍后送三个图层，使三条路径拍数一致。
    //   注意：raddr 仍用未延迟的 px，因为它要配合 BSRAM 的 1 拍读延迟。
    //------------------------------------------------------------------
    reg [11:0] px_d, py_d;
    reg        de_d;
    always @(posedge clk) begin
        px_d <= px;
        py_d <= py;
        de_d <= de;
    end

    //------------------------------------------------------------------
    // ABS: 图层
    //------------------------------------------------------------------
    wire        g_hit;
    wire [11:0] g_col;

    grid_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .STEP(GRID_STEP), .AXIS_Y(AXIS_Y),
        .COL_GRID(COL_GRID), .COL_AXIS(COL_AXIS)
    ) u_grid (.px(px_d), .py(py_d), .de(de_d), .hit(g_hit), .color(g_col));

    wire t0_hit, t1_hit;
    wire [11:0] t0_col, t1_col;

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH0)
    ) u_tr0 (.px(px_d), .py(py_d), .de(de_d), .en(ch0_en),
             .s_now(s0), .s_prev(s0_prev),
             .vshift(vsc0_eff), .voff(voff0), .hit(t0_hit), .color(t0_col));

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH1)
    ) u_tr1 (.px(px_d), .py(py_d), .de(de_d), .en(ch1_en),
             .s_now(s1), .s_prev(s1_prev),
             .vshift(vsc1_eff), .voff(voff1), .hit(t1_hit), .color(t1_col));

    // 文本值：按 page 切换两组测量；菜单模式下锁定第 1 页显示"项号 + 当前值"
    wire        page_eff = menu_on ? 1'b0 : page;

    wire [15:0] menu_val = {12'd0, menu_sel};

    wire [15:0] tv0 = menu_on ? {13'd0, menu_sel} : (page ? {6'd0, vmax}  : {6'd0, ch0_in});
    wire [15:0] tv1 = menu_on ? menu_val          : (page ? {6'd0, vmin}  : {6'd0, ch1_in});
    wire [15:0] tv2 = menu_on ? 16'd0             : (page ? {6'd0, vmean} : tb_div);
    wire [15:0] tv3 = menu_on ? 16'd0 : (page ? period        : {6'd0, vpp});
    wire [15:0] tv4 = menu_on ? 16'd0 : (page ? {8'd0, duty}  : freq);

    wire        tx_hit;
    wire [11:0] tx_col;

    text_layer #(
        .TEXT_Y0(TEXT_Y0), .TEXT_X0(TEXT_X0), .COLS(32), .COL(COL_TEXT)
    ) u_text (
        .px(px_d), .py(py_d), .de(de_d), .page(page_eff),
        .val0(tv0), .val1(tv1), .val2(tv2), .val3(tv3), .val4(tv4),
        .hit(tx_hit), .color(tx_col)
    );

    wire [11:0] rgb_comp;
    compositor u_comp (
        .txt_hit(tx_hit), .txt_col(tx_col),
        .ch1_hit(t1_hit), .ch1_col(t1_col),
        .ch0_hit(t0_hit), .ch0_col(t0_col),
        .grid_hit(g_hit), .grid_col(g_col),
        .bg_col(COL_BG), .rgb(rgb_comp)
    );

    //------------------------------------------------------------------
    // 菜单 OSD（最高优先级，盖在所有图层之上）
    //------------------------------------------------------------------
    wire        menu_hit;
    wire [11:0] menu_col;

    menu_layer u_menu (
        .px(px_d), .py(py_d), .de(de_d),
        .on(menu_on), .sel(menu_sel), .page(menu_page), .ena_sig(gen_ena_eff),
        .v0({3'd0, ch0_en}), .v1({3'd0, ch1_en}),
        .v2({1'b0, vsc0}),   .v3({1'b0, vsc1}),
        .v4(pos0),           .v5(pos1),
        .v6(hscale[6:3]), .v7(tb_idx),   // HSC 显示 S/8（=8 即 1:1，十进制约 1.6x 一格）
        .v8({3'd0, roll}),
        // P1 共 8 项：0..3 = CH0 的 WAV/FRE/ATT/PHA，4..7 = CH1 的同一组参数
        .w0({2'd0, gen_wave0}), .w1({1'b0, gen_freq0}),
        .w2({2'd0, gen_amp0}),  .w3(gen_phase0),
        .w4({2'd0, gen_wave1}), .w5({1'b0, gen_freq1}),
        .w6({2'd0, gen_amp1}),  .w7(gen_phase1),
        .hit(menu_hit), .color(menu_col)
    );

    wire [11:0] rgb_comb = menu_hit ? menu_col : rgb_comp;

    //------------------------------------------------------------------
    // 输出寄存（2 拍 = 1 像素对齐）
    //------------------------------------------------------------------
    reg [11:0] rgb_r;
    reg        hs1, hs2, vs1, vs2, de1, de2;

    always @(posedge clk) begin
        if (rst) begin
            rgb_r <= COL_BG;
            hs1 <= 1'b1; hs2 <= 1'b1;
            vs1 <= 1'b1; vs2 <= 1'b1;
            de1 <= 1'b0; de2 <= 1'b0;
        end
        else begin
            hs1 <= hs; hs2 <= hs1;
            vs1 <= vs; vs2 <= vs1;
            de1 <= de; de2 <= de1;
            if (pix_ce) rgb_r <= rgb_comb;
        end
    end

    assign vga_rgb = rgb_r;
    assign vga_hs  = hs2;
    assign vga_vs  = vs2;
    assign vga_de  = de2;

endmodule