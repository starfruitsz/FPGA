//==============================================================================
// 层: 顶层(屏幕自检)  文件: vga_test_top.v
// 功能: 独立的屏幕自检顶层 —— 只调用 HAL 的 vga_timing 与 APP 的
//       scope_ui(按键去抖)、vga_test_app(图案)，不修改任何下层封装。
//
// 用法:
//   A) 独立顶层: 在 Gowin 里把 Top 设为 vga_test_top(引脚同上);
//   B) 复用主工程: 在 adda_scope_top.v 里把 TEST_MODE 置 1，
//      VGA 口即输出自检图案，拔掉外部 AD/DA 也不影响(仅用 sys_clk/按键)。
//
// 输出时序与 vga_scope_top 完全一致: 像素节拍 25MHz(50MHz/2)、
// 同步信号延迟 2 拍(1 像素) 与像素数据对齐。
//==============================================================================
`timescale 1ns / 1ps

module vga_test_top #(
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
    parameter integer AUTO_FRAMES = 120,
    parameter [11:0]  COL_BG   = 12'h012
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        key_in,
    output wire [11:0] vga_rgb,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_de
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
        .clk   (clk),
        .rst   (rst),
        .pix_ce(pix_ce),
        .hs    (hs),
        .vs    (vs),
        .de    (de),
        .px    (px),
        .py    (py)
    );

    // 帧起始脉冲
    reg vs_d;
    always @(posedge clk) vs_d <= vs;
    wire frame = vs & (~vs_d);

    //------------------------------------------------------------------
    // APP: 按键去抖(复用现有模块) + 自检图案
    //------------------------------------------------------------------
    wire ev_next;
    wire ev_long_unused;

    scope_ui #(
        .CLK_HZ (50_000_000),
        .DB_MS  (20),
        .LONG_MS(800)
    ) u_key (
        .clk     (clk),
        .rst     (rst),
        .key_in  (key_in),
        .ev_short(ev_next),
        .ev_long (ev_long_unused)
    );

    wire [11:0] rgb_comb;

    vga_test_app #(
        .H_VIS      (H_VIS),
        .V_VIS      (V_VIS),
        .AUTO_FRAMES(AUTO_FRAMES),
        .COL_BG     (COL_BG)
    ) u_app (
        .clk    (clk),
        .rst    (rst),
        .ev_next(ev_next),
        .frame  (frame),
        .px     (px),
        .py     (py),
        .de     (de),
        .rgb    (rgb_comb),
        .mode_o ()
    );

    //------------------------------------------------------------------
    // 输出寄存: 与 vga_scope_top 相同的 2 拍(1 像素)对齐
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

            if (pix_ce)
                rgb_r <= rgb_comb;
        end
    end

    assign vga_rgb = rgb_r;
    assign vga_hs  = hs2;
    assign vga_vs  = vs2;
    assign vga_de  = de2;

endmodule
