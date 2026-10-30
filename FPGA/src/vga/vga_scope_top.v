//==============================================================================
// 层: 顶层(集成)  文件: vga_scope_top.v   [v2: 触发状态机 / 扩展测量 / 双页文本]
// 装配 HAL/ABS/APP，不含算法。像素流水线与 v1 相同：
//   像素周期 = PIX_DIV 个 clk；BSRAM 同步读 1 拍；后半拍求值，pix_ce 打寄存器；
//   hs/vs/de 固定延迟 2 拍（=1 像素）对齐。
// 新增连线：
//   - 触发源选择(trig_src) → capture.trig_din
//   - capture.state/rd_base → 显示读地址(触发基准) 与状态显示
//   - meas 扩展输出 → 文本第 2 页
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
    input  wire [3:0]  key_n,         // {U,D,L,R} 4 个按键，低有效
    input  wire        sw_menu,       // SW0 上升沿: 菜单开/关
    input  wire        sw_run,        // SW1 上升沿: 运行/冻结
    input  wire        sw_page,       // SW2 电平  : 信号源页
    input  wire        sw_roll,       // SW3 上升沿: 滚动模式

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
    // 函数发生器设置（送到板级顶层驱动内置信号源）
    output wire [1:0]  gen_wave,
    output wire [2:0]  gen_freq,
    output wire [1:0]  gen_amp,
    output wire        menu_on_o,
    output wire [3:0]  gen_phase,    // 信号源相位档 0..9
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
    wire [1:0]  hzoom;               // 0=1x 1=2x 2=4x 3=全屏
    wire        menu_page;
    wire [3:0]  phase_idx;
    wire [2:0]  tb_idx;
    wire        menu_on;
    wire [3:0]  menu_sel;

    // 档位 -> 像素偏移：每档 24 像素，(5) 为居中
    wire signed [9:0] voff0 = ($signed({6'b0, pos0}) - 10'sd5) * 10'sd24;
    wire signed [9:0] voff1 = ($signed({6'b0, pos1}) - 10'sd5) * 10'sd24;

    scope_app #(
        .CLK_HZ(CLK_HZ)
    ) u_app (
        .gen_ena(GEN_ENA != 0),
        .sw_menu(sw_menu), .sw_run(sw_run), .sw_page(sw_page), .sw_roll(sw_roll),
        .clk(clk), .rst(rst), .key_n(key_n),
        .ext_tb_we(cfg_tb_we),       .ext_tb(cfg_tb),
        .ext_run_we(cfg_run_we),     .ext_run(cfg_run),
        .ext_ten_we(cfg_ten_we),     .ext_ten(cfg_ten),
        .ext_lvl_we(cfg_lvl_we),     .ext_lvl(cfg_lvl),
        .ext_edg_we(cfg_edg_we),     .ext_edg(cfg_edg),
        .ext_scr_we(cfg_scr_we),     .ext_scr(cfg_scr),
        .ext_tmode_we(FEAT_UART ? cfg_tmode_we : 1'b0), .ext_tmode(cfg_tmode),
        .ext_tsrc_we (FEAT_UART ? cfg_tsrc_we  : 1'b0), .ext_tsrc(cfg_tsrc),
        .ext_pre_we  (FEAT_UART ? cfg_pre_we   : 1'b0), .ext_pre(cfg_pre),
        .ext_hold_we (FEAT_UART ? cfg_hold_we  : 1'b0), .ext_hold(cfg_hold),
        .cap_done(done0), .cap_state(state0),
        .tb_div(tb_div), .run(run), .arm(arm),
        .trig_en(trig_en), .trig_mode(trig_mode), .trig_src(trig_src),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .scroll_en(scroll_en), .tb_idx(tb_idx), .page(page), .state_o(state_o),
        .ev_short_o(), .ev_long_o(),
        .ch0_en(ch0_en), .ch1_en(ch1_en),
        .vs0(vsc0), .vs1(vsc1), .pos0(pos0), .pos1(pos1),
        .roll(roll), .hzoom(hzoom), .menu_page(menu_page), .phase_idx(phase_idx),
        .wave(gen_wave), .fsel(gen_freq), .asel(gen_amp),
        .menu_on(menu_on), .menu_sel(menu_sel)
    );

    assign menu_on_o = menu_on;
    assign gen_phase  = phase_idx;
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
        .we(we1), .waddr(wa1), .trig_det(), .done(done1),
        .rd_base(rd_base1), .state(state1),
        .buf_wr(buf_wr1), .buf_disp(buf_disp1)
    );

    //------------------------------------------------------------------
    // 读地址：显示缓冲区 + 触发基准 + 像素列（乒乓双缓冲）
    //   每通道 RAM 深度 2x1024：一半正在写、另一半正在显示，互不干扰，
    //   因此跟踪模式下不再出现"新数据覆盖到哪就断在哪"的截断。
    //------------------------------------------------------------------
    wire [DEPTH_LOG2:0] raddr0, raddr1;

    // 水平缩放：像素列 -> 采样地址
    //   0=1:1   1=2x放大   2=4x放大   3=适应全屏(640 像素覆盖 1020 点)
    wire [9:0] pxz = (hzoom == 2'd0) ? px[9:0] :
                     (hzoom == 2'd1) ? {1'b0, px[9:1]} :
                     (hzoom == 2'd2) ? {2'b00, px[9:2]} :
                                       ((px[9:0] * 10'd51) >> 5);

    generate
        if (FEAT_SCROLL != 0) begin : g_scroll
            reg [DEPTH_LOG2-1:0] rd_base_s;
            always @(posedge clk) begin
                if (rst)        rd_base_s <= {DEPTH_LOG2{1'b0}};
                else if (frame) rd_base_s <= wa0;
            end
            wire [9:0] ra0 = scroll_en ? (rd_base_s - 10'd640 + pxz) : (rd_base0 + pxz);
            wire [9:0] ra1 = scroll_en ? (rd_base_s - 10'd640 + pxz) : (rd_base1 + pxz);
            // 滚动模式是"纸带式实时"，必须显示正在写入的那半；
            // 触发刷新模式显示已采完的那半（乒乓双缓冲，不截断）
            assign raddr0 = {scroll_en ? buf_wr0 : buf_disp0, ra0};
            assign raddr1 = {scroll_en ? buf_wr1 : buf_disp1, ra1};
        end
        else begin : g_noscroll
            assign raddr0 = {buf_disp0, (rd_base0 + pxz)};
            assign raddr1 = {buf_disp1, (rd_base1 + pxz)};
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
             .vshift(vsc0), .voff(voff0), .hit(t0_hit), .color(t0_col));

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL_CH1)
    ) u_tr1 (.px(px_d), .py(py_d), .de(de_d), .en(ch1_en),
             .s_now(s1), .s_prev(s1_prev),
             .vshift(vsc1), .voff(voff1), .hit(t1_hit), .color(t1_col));

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
        .on(menu_on), .sel(menu_sel), .page(menu_page), .ena_sig(GEN_ENA != 0),
        .v0({3'd0, ch0_en}), .v1({3'd0, ch1_en}),
        .v2({1'b0, vsc0}),   .v3({1'b0, vsc1}),
        .v4(pos0),           .v5(pos1),
        .v6({2'd0, hzoom}),  .v7({1'b0, tb_idx}),
        .v8({3'd0, roll}),
        .w0({2'd0, gen_wave}), .w1({1'b0, gen_freq}),
        .w2({2'd0, gen_amp}),  .w3(phase_idx),
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