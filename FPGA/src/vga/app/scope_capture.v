//==============================================================================
// 层: 应用(采集)  文件: app/scope_capture.v   [v2: 触发状态机 + 预触发]
// 功能: 单通道采样引擎
//   - 采样率 = CLK / (rate_div+1)，运行时可配
//   - 循环写入 BSRAM；写指针 arm 时归零
//   - 触发状态机: IDLE -> ARMED -> FILL -> DONE
//   - trig_mode: 0=自动(自由滚动，仅对齐)
//                1=正常(捕获一屏后停在 DONE，由上层重触发)
//                2=单次(停在 DONE，必须显式 arm 才继续)
//   - pre_trig: 预触发点数。触发时锁存 rd_base = 写指针 - pre_trig，
//     显示从 rd_base 开始读，于是屏幕上能看到触发点之前的波形。
//==============================================================================
`timescale 1ns / 1ps

module scope_capture #(
    parameter integer DEPTH_LOG2 = 10
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
    output wire                    we,
    output reg  [DEPTH_LOG2-1:0]   waddr,
    output reg                     trig_det,     // 触发命中(单周期)
    output reg                     done,         // 本次捕获完成(单周期)
    output reg  [DEPTH_LOG2-1:0]   rd_base,      // 显示起始地址(触发点-pre_trig)
    output reg  [1:0]              state         // 0=IDLE 1=ARMED 2=FILL 3=DONE
);

    localparam [1:0] ST_IDLE  = 2'd0,
                     ST_ARMED = 2'd1,
                     ST_FILL  = 2'd2,
                     ST_DONE  = 2'd3;

    reg [15:0] rate_cnt;
    reg [9:0]  din_d;          // 上一拍触发源采样
    reg [DEPTH_LOG2:0] post_cnt;
    reg [15:0] hold_cnt;       // 触发保持计数(>0 时忽略新触发)

    wire tick = sample_valid && (rate_cnt == rate_div);

    // 完成且非自动模式时停止写入
    wire stopped = (state == ST_DONE) && (trig_mode != 2'd0);
    assign we = run && (!arm) && tick && (!stopped);

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
        end
        else begin
            trig_det <= 1'b0;
            done     <= 1'b0;

            case (state)
                // 等待 arm：上电/单次捕获完成后停在这里
                ST_IDLE: begin
                    if (arm) begin
                        rate_cnt <= 16'd0;
                        waddr    <= {DEPTH_LOG2{1'b0}};
                        rd_base  <= {DEPTH_LOG2{1'b0}};
                        post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                        state    <= ST_ARMED;
                    end
                end

                // 已武装：自由写入并等待触发
                ST_ARMED: begin
                    if (arm) begin
                        waddr    <= {DEPTH_LOG2{1'b0}};
                        rd_base  <= {DEPTH_LOG2{1'b0}};
                        post_cnt <= {(DEPTH_LOG2+1){1'b0}};
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
                            // 自动模式不改变状态，只更新对齐基准
                            state    <= (trig_mode == 2'd0) ? ST_ARMED : ST_FILL;
                        end
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
                            done  <= 1'b1;
                            state <= ST_DONE;
                        end
                    end
                end

                // 完成：正常模式等上层重触发，单次模式等 arm
                ST_DONE: begin
                    if (arm) begin
                        rate_cnt <= 16'd0;
                        waddr    <= {DEPTH_LOG2{1'b0}};
                        rd_base  <= {DEPTH_LOG2{1'b0}};
                        post_cnt <= {(DEPTH_LOG2+1){1'b0}};
                        state    <= ST_ARMED;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
