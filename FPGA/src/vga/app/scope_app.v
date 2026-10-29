//==============================================================================
// 层: 应用(配置)  文件: app/scope_app.v
// 功能: 运行时可配置项 + 按键交互 + 串口配置入口
//   - 时基: 8 档预设(短按切换)；也可由 ext_tb_we/ext_tb 直接写入
//   - 运行/冻结: 长按切换；也可由 ext_run_we 写入
//   - 触发(特性1): 使能/电平/边沿，可由串口配置
//   - 滚动(特性3): 使能，可由串口配置
//   - arm: 单周期脉冲，重新开始采集
// 优先级: 同一拍内串口写入优先于按键(按键先执行，串口后覆盖)
//==============================================================================
`timescale 1ns / 1ps

module scope_app (
    input  wire        clk,
    input  wire        rst,
    input  wire        key_in,

    // ---- 串口下发(特性4) ----
    input  wire        ext_tb_we,
    input  wire [15:0] ext_tb,
    input  wire        ext_run_we,
    input  wire        ext_run,
    input  wire        ext_ten_we,
    input  wire        ext_ten,
    input  wire        ext_lvl_we,
    input  wire [9:0]  ext_lvl,
    input  wire        ext_edg_we,
    input  wire        ext_edg,
    input  wire        ext_scr_we,
    input  wire        ext_scr,

    output reg  [15:0] tb_div,
    output reg         run,
    output reg         arm,
    output reg         trig_en,
    output reg  [9:0]  trig_level,
    output reg         trig_edge,
    output reg         scroll_en,
    output reg  [2:0]  tb_idx,
    output wire        ev_short_o,
    output wire        ev_long_o
);

    wire ev_short;
    wire ev_long;

    assign ev_short_o = ev_short;
    assign ev_long_o  = ev_long;

    scope_ui #(
        .CLK_HZ (50_000_000),
        .DB_MS  (20),
        .LONG_MS(800)
    ) u_ui (
        .clk     (clk),
        .rst     (rst),
        .key_in  (key_in),
        .ev_short(ev_short),
        .ev_long (ev_long)
    );

    // 时基档位 -> 分频值
    wire [2:0] nidx = (tb_idx == 3'd6) ? 3'd0 : (tb_idx + 3'd1);

    reg [15:0] tb_next;
    always @(*) begin
        case (nidx)
            3'd0: tb_next = 16'd49999;   // 1 kS/s
            3'd1: tb_next = 16'd9999;    // 5 kS/s
            3'd2: tb_next = 16'd1999;    // 25 kS/s
            3'd3: tb_next = 16'd499;     // 100 kS/s
            3'd4: tb_next = 16'd99;      // 500 kS/s
            3'd5: tb_next = 16'd9;       // 5 MS/s
            3'd6: tb_next = 16'd0;       // 50 MS/s
            default: tb_next = 16'd49999;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            tb_idx     <= 3'd0;
            tb_div     <= 16'd49999;
            run        <= 1'b1;
            arm        <= 1'b0;
            trig_en    <= 1'b0;      // 特性1 默认关闭，可用串口 "A1" 打开
            trig_level <= 10'd512;
            trig_edge  <= 1'b0;
            scroll_en  <= 1'b0;      // 特性3 默认关闭，可用串口 "S1" 打开
        end
        else begin
            arm <= 1'b0;

            // ---- 按键 ----
            if (ev_short) begin                 // 短按: 下一档时基
                tb_idx <= nidx;
                tb_div <= tb_next;
                arm    <= 1'b1;
            end
            if (ev_long) begin                  // 长按: 冻结/运行
                run <= ~run;
                arm <= 1'b1;
            end

            // ---- 串口(后写，优先级更高) ----
            if (ext_tb_we)  begin tb_div     <= ext_tb;  arm <= 1'b1; end
            if (ext_run_we) begin run        <= ext_run; arm <= 1'b1; end
            if (ext_ten_we) begin trig_en    <= ext_ten; arm <= 1'b1; end
            if (ext_lvl_we) begin trig_level <= ext_lvl; end
            if (ext_edg_we) begin trig_edge  <= ext_edg; end
            if (ext_scr_we) begin scroll_en  <= ext_scr; end
        end
    end

endmodule
