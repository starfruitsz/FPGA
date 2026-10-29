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

//
// ============================ 怎么读这个文件 ============================
// 这个模块可以理解成“设置面板”：它保存所有可调参数，并决定谁来改。
//   输入：按键事件(短按/长按) + 串口下发的 6 组写使能/数值
//   输出：采样分频 tb_div、运行 run、触发设置、滚动开关、arm(重新采集)
// 规则：同一拍里按键先执行、串口后执行，所以“串口优先”。
// arm 是一个只维持 1 拍的脉冲，用来通知采集引擎“从头开始”。
// ======================================================================
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
//------------------------------------------------------------------
// nidx：短按后要切换到的“下一档”。到第 6 档就回到 0，形成 8 档循环。
// 3 位二进制正好 0..7，所以用 3'd6 判断最大值。
//------------------------------------------------------------------
    wire [2:0] nidx = (tb_idx == 3'd6) ? 3'd0 : (tb_idx + 3'd1);

    reg [15:0] tb_next;
//------------------------------------------------------------------
// [时基表] 把“档位”翻译成“分频值”。分频值 = 采样周期 - 1。
//   50MHz / (49999+1) = 1kHz 采样率；rate_div=0 时每个时钟采一点(50MS/s)。
// 换主频时只需要改这张表，其它逻辑不变。
//------------------------------------------------------------------
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

//------------------------------------------------------------------
// 主寄存器块。注意三个细节：
// 1) arm 每拍默认清 0，再在按键/串口分支里置 1 —— 这样它天然是单拍脉冲；
// 2) 短按换档时也发 arm，让波形从新起点开始画；
// 3) 串口分支放在按键分支后面，同一拍会覆盖按键的结果（后写优先）。
//------------------------------------------------------------------
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
//------------------------------------------------------------------
// [短按] 换下一档时基，并重新开始一次采集(arm)。
// 这样换档后画面不会残留上一档的数据。
//------------------------------------------------------------------
            if (ev_short) begin                 // 短按: 下一档时基
                tb_idx <= nidx;
                tb_div <= tb_next;
                arm    <= 1'b1;
            end
//------------------------------------------------------------------
// [长按] 运行/冻结切换。冻结时采集引擎停止写入，画面停在当前波形。
//------------------------------------------------------------------
            if (ev_long) begin                  // 长按: 冻结/运行
                run <= ~run;
                arm <= 1'b1;
            end

            // ---- 串口(后写，优先级更高) ----
//------------------------------------------------------------------
// [串口写入] 每条命令都对应一个 we 脉冲 + 数值；收到就更新寄存器。
// 改时基/运行/触发使能时也顺手发一个 arm，避免新旧数据混在一屏。
//------------------------------------------------------------------
            if (ext_tb_we)  begin tb_div     <= ext_tb;  arm <= 1'b1; end
            if (ext_run_we) begin run        <= ext_run; arm <= 1'b1; end
            if (ext_ten_we) begin trig_en    <= ext_ten; arm <= 1'b1; end
            if (ext_lvl_we) begin trig_level <= ext_lvl; end
            if (ext_edg_we) begin trig_edge  <= ext_edg; end
            if (ext_scr_we) begin scroll_en  <= ext_scr; end
        end
    end

endmodule
