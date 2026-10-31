//==============================================================================
// 层: 应用(输入)  文件: app/sw_edge.v
// 功能: 拨动开关同步 + 消抖 + 上升沿检测
//   机械开关抖动可达几毫秒，这里先两级同步，再要求电平稳定 DB_MS 毫秒才认可；
//   lv   = 消抖后的电平（适合"开关位置=模式"）
//   rise = 电平上升沿的单周期脉冲（适合"拨一下=切换一次"）
//==============================================================================
`timescale 1ns / 1ps

module sw_edge #(
    parameter integer CLK_HZ = 24_000_000,
    parameter integer DB_MS  = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire sw_in,
    output wire lv,
    output wire rise
);

    localparam integer DB = (CLK_HZ / 1000) * DB_MS;

    reg [1:0]  sync;
    reg        state;
    reg        state_d;
    reg        init_done;
    reg [23:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            sync      <= 2'b00;
            state     <= 1'b0;
            state_d   <= 1'b0;
            init_done <= 1'b0;
            cnt       <= 24'd0;
        end
        else begin
            sync <= {sync[0], sw_in};

            // 上电首次采样直接采用当前开关位置（不等待消抖窗口），
            // 只有之后的电平变化才需要 8ms 稳定期
            if (!init_done) begin
                state     <= sync[1];
                init_done <= 1'b1;
                cnt       <= 24'd0;
            end
            else if (sync[1] != state) begin
                if (cnt >= DB - 1) begin
                    state <= sync[1];
                    cnt   <= 24'd0;
                end
                else begin
                    cnt <= cnt + 24'd1;
                end
            end
            else begin
                cnt <= 24'd0;
            end
            state_d <= state;
        end
    end

    assign lv   = state;
    assign rise = state & ~state_d;

endmodule