//==============================================================================
// 层: 应用(采集)  文件: app/scope_capture.v   [v4: 触发状态机 + 预触发 + 滚动 + 无触发换页]
// 功能: 单通道采样引擎
//   - 采样率 = CLK / (rate_div+1)，运行时可配
//   - 循环写入 BSRAM；写指针 arm 时归零
//   - 触发状态机: IDLE -> ARMED -> FILL -> DONE
//   - trig_mode: 0=自动(自由滚动，仅对齐)
//                1=正常(捕获一屏后停在 DONE，由上层重触发)
//                2=单次(停在 DONE，必须显式 arm 才继续)
//   - pre_trig: 预触发点数。触发时锁存 rd_base = 写指针 - pre_trig，
//     显示从 rd_base 开始读，于是屏幕上能看到触发点之前的波形。
//   - roll = 1: 滚动模式。采集进入"自由循环写"：
//       不响应触发(trig_det 恒 0)、不被 arm 复位写指针、不翻乒乓半区；
//       显示端直接读正在写的那半，按"纸带"方式滚过去。
//     roll = 0: 回到原来的触发 + 乒乓流程（采满一屏才换显示半区）。
//   - [v4] 无触发超时换页(AUTO 模式)：
//       非滚动模式下若 ARMED 连续 AUTO_TIMEOUT(默认 1024)个采样 tick 都没等到
//       触发(典型场景: AD/DA 模式 ch0 是 ADC 数据且输入为直流/无信号)，就当作
//       "没触发"强制进 FILL 采满一屏并翻乒乓半区，光标基准 rd_base 锁在当前写
//       指针(缓冲里最老的那个样本)。这样屏幕整屏换成新采的一屏，不会出现
//       "函数发生器旧波形 + AD/DA 新波形"叠在一起的现象，状态也不会永久卡在
//       ARMED。真正的 AUTO 模式(trig_mode=0)本来就是自由滚动、显示正在写的那
//       半，没有乒乓换页的概念，行为保持不变；single 仍然是"一次 arm 最多采一
//       屏，采完停在 DONE 等下一次 arm"。
//==============================================================================
`timescale 1ns / 1ps

module scope_capture #(
    parameter integer DEPTH_LOG2    = 10,
    // 无触发超时(采样 tick 数)：ARMED 下连续这么多个采样点都没等到触发，
    // 就自动采满一屏并换页(AUTO 换页)。1024 = 一屏的采样点数。
    parameter integer AUTO_TIMEOUT  = 1024
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [9:0]              din,          // 采样数据
    input  wire [9:0]              trig_din,     // 触发源数据(顶层选择 CH0/CH1)
    input  wire [15:0]             rate_div,
    input  wire                    sample_valid,   // ADC 采样有效(来自 HAL)
    input  wire                    run,
    input  wire                    arm,
    input  wire                    trig_en,
    input  wire [1:0]              trig_mode,    // 0=auto 1=normal 2=single
    input  wire [9:0]              trig_level,
    input  wire                    trig_edge,    // 0=上升 1=下降
    input  wire [9:0]              pre_trig,     // 预触发点数
    input  wire [15:0]             holdoff,     // 触发保持时间(采样点数)
    input  wire                    roll,        // 1=滚动: 自由循环写(忽略触发/arm, 不翻乒乓)
    output wire                    we,
    output reg  [DEPTH_LOG2-1:0]   waddr,
    output reg                     trig_det,     // 触发命中(单周期)
    output reg                     done,         // 本次捕获完成(单周期)
    output reg  [DEPTH_LOG2-1:0]   rd_base,      // 显示起始地址(触发点-pre_trig)
    output reg  [1:0]              state,        // 0=IDLE 1=ARMED 2=FILL 3=DONE
    // ---- 乒乓双缓冲 ----
    output reg                     buf_wr,       // 当前正在写入的缓冲区(0/1)
    output reg                     buf_disp      // 当前显示用的缓冲区(已采完的那半)
);

    localparam [1:0] ST_IDLE  = 2'd0,
                     ST_ARMED = 2'd1,
                     ST_FILL  = 2'd2,
                     ST_DONE  = 2'd3;

    reg [15:0] rate_cnt;
    reg [9:0]  din_d;          // 上一拍触发源采样
    reg [DEPTH_LOG2:0] post_cnt;
    reg [15:0] hold_cnt;       // 触发保持计数(>0 时忽略新触发)
    reg [15:0] tmo_cnt;        // 无触发超时计数(ARMED 下按采样 tick 累加)

    wire tick = sample_valid && (rate_cnt == rate_div);

    //------------------------------------------------------------------
    // 无触发超时判据(AUTO 换页)
    //   - 只对 normal(1)/single(2) 生效：这两个模式是"触发 + 乒乓换页"流程，
    //     等不到触发就会永久停在 ARMED，屏幕一直混着新旧数据；
    //   - auto(0) 是自由滚动 + 只更新对齐基准，本来就没有换页概念，保持不动；
    //   - roll(滚动纸带)走的是另一条分支，同样不受影响。
    //   计满 AUTO_TIMEOUT 个采样 tick 即命中（第 AUTO_TIMEOUT 个 tick 触发）。
    //------------------------------------------------------------------
    wire auto_tmo_ena = (!roll) && (trig_mode != 2'd0) && (AUTO_TIMEOUT > 0);
    wire auto_tmo_hit = auto_tmo_ena && (tmo_cnt >= (AUTO_TIMEOUT - 1));

    // 完成且非自动模式时停止写入
    wire stopped = (state == ST_DONE) && (trig_mode != 2'd0);
    // 滚动模式例外：只要 run 且采样节拍到就写，不受 arm / 触发 / DONE 影响
    assign we = run && tick && (roll || ((!arm) && (!stopped)));

    // 触发判据：用 trig_din（触发源），不是 din（采样数据）
    wire cross = trig_edge
               ? ((din_d > trig_level) && (trig_din <= trig_level))
               : ((din_d < trig_level) && (trig_din >= trig_level));

    wire [DEPTH_LOG2-1:0] waddr_nxt = waddr + 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            rate_cnt <= 16'd0;
            din_d    <= 10'd0;
            waddr    <= {DEPTH_LOG2{1'b0}};
            rd_base  <= {DEPTH_LOG2{1'b0}};
            trig_det <= 1'b0;
            done     <= 1'b0;
            post_cnt <= {(DEPTH_LOG2+1){1'b0}};
            state    <= ST_IDLE;
            hold_cnt <= 16'd0;
            tmo_cnt  <= 16'd0;
            buf_wr   <= 1'b0;
            buf_disp <= 1'b0;
        end
        else begin
            trig_det <= 1'b0;
            done     <= 1'b0;

            if (roll) begin
                // ---------- 滚动模式：自由循环写 ----------
                //   1) 不响应触发：不做电平比较，trig_det 恒 0
                //   2) 不被 arm 复位：写指针/rd_base 保持原样（arm 被忽略）
                //   3) 不翻乒乓半区：buf_wr/buf_disp 都不动，显示始终读正在写的那半
                //   状态固定报 ARMED(运行)，供上层状态显示使用
                state    <= ST_ARMED;
                post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                tmo_cnt  <= 16'd0;      // 滚动模式不做无触发超时
                if (!run) begin
                    rate_cnt <= 16'd0;
                end
                else if (tick) begin
                    rate_cnt <= 16'd0;
                    din_d    <= trig_din;
                    waddr    <= waddr_nxt;
                end
                else if (rate_cnt < rate_div) begin
                    rate_cnt <= rate_cnt + 16'd1;
                end
                else if (rate_cnt > rate_div) begin
                    rate_cnt <= rate_div;
                end
            end
            else begin
                case (state)
                    // 等待 arm：上电/单次捕获完成后停在这里
                    ST_IDLE: begin
                        if (arm) begin
                            rate_cnt <= 16'd0;
                            waddr    <= {DEPTH_LOG2{1'b0}};
                            rd_base  <= {DEPTH_LOG2{1'b0}};
                            post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                            tmo_cnt  <= 16'd0;      // 新的一次布防，超时重新计时
                            state    <= ST_ARMED;
                        end
                    end

                    // 已武装：自由写入并等待触发
                    ST_ARMED: begin
                        if (arm) begin
                            waddr    <= {DEPTH_LOG2{1'b0}};
                            rd_base  <= {DEPTH_LOG2{1'b0}};
                            post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                            tmo_cnt  <= 16'd0;      // 重新布防，超时重新计时
                        end
                        else if (!run) begin
                            rate_cnt <= 16'd0;
                        end
                        else if (tick) begin
                            rate_cnt <= 16'd0;
                            din_d    <= trig_din;
                            if (hold_cnt != 16'd0) hold_cnt <= hold_cnt - 1'b1;
                            waddr    <= waddr_nxt;
                            if (trig_en && cross && (hold_cnt == 16'd0)) begin
                                trig_det <= 1'b1;
                                // 预触发：显示基准往前挪 pre_trig 个点
                                rd_base  <= waddr - pre_trig[DEPTH_LOG2-1:0];
                                hold_cnt <= holdoff;
                                post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                                tmo_cnt  <= 16'd0;      // 等到触发了，超时重新计时
                                // 自动模式不改变状态，只更新对齐基准
                                state    <= (trig_mode == 2'd0) ? ST_ARMED : ST_FILL;
                            end
                            else if (auto_tmo_hit) begin
                                // ---------------- 无触发超时：AUTO 换页 ----------------
                                // 等不到触发也要出图：直接进 FILL 采满一屏并翻半区。
                                // rd_base 锁到下一拍的写指针 waddr_nxt —— 那个格子
                                // 正是循环缓冲里最老的样本(马上被本次 FILL 的第一个
                                // 点覆盖)，显示从它开始读，采满后整屏都是新数据，
                                // 不会和上一屏叠在一起。
                                rd_base  <= waddr_nxt;
                                post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                                tmo_cnt  <= 16'd0;
                                state    <= ST_FILL;
                            end
                            else begin
                                // 还没等到触发：累加无触发计数，计满即超时
                                tmo_cnt <= tmo_cnt + 16'd1;
                            end
                        end
                        // 采样分频计数：计到 rate_div 后保持，等下一个有效采样点再清零。
                        // 修复前这里没有任何自增，导致 rate_div>0 时永远采不到样。
                        // 若运行中把 rate_div 改小（例如 T0），计数器必须回落，否则会卡死。
                        else if (rate_cnt < rate_div) begin
                            rate_cnt <= rate_cnt + 16'd1;
                        end
                        else if (rate_cnt > rate_div) begin
                            rate_cnt <= rate_div;
                        end
                    end

                    // 填充：从触发点开始再采一屏
                    ST_FILL: begin
                        if (!run) begin
                            rate_cnt <= 16'd0;
                        end
                        else if (tick) begin
                            rate_cnt <= 16'd0;
                            waddr    <= waddr_nxt;
                            post_cnt <= post_cnt + 1'b1;
                            if (post_cnt >= (1 << DEPTH_LOG2) - 1) begin
                                done     <= 1'b1;
                                state    <= ST_DONE;
                                buf_disp <= buf_wr;      // 这一半采完了，交给显示
                                buf_wr   <= ~buf_wr;     // 下一屏写到另一半
                            end
                        end
                        else if (rate_cnt < rate_div) begin
                            rate_cnt <= rate_cnt + 16'd1;
                        end
                        else if (rate_cnt > rate_div) begin
                            rate_cnt <= rate_div;
                        end
                    end

                    // 完成：正常模式等上层重触发，单次模式等 arm
                    ST_DONE: begin
                        if (arm) begin
                            rate_cnt <= 16'd0;
                            waddr    <= {DEPTH_LOG2{1'b0}};
                            rd_base  <= {DEPTH_LOG2{1'b0}};
                            post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                            tmo_cnt  <= 16'd0;      // 新的一次布防，超时重新计时
                            state    <= ST_ARMED;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
