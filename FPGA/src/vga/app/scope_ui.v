//==============================================================================
// 层: 应用(人机)  文件: app/scope_ui.v
// 功能: 单按键的短按/长按识别(带去抖)
//   - 按下并稳定 DB_MS 毫秒后才认为有效
//   - 按住超过 LONG_MS 毫秒 -> ev_long 单周期脉冲(只发一次)
//   - 未达长按即松开 -> ev_short 单周期脉冲
//==============================================================================
`timescale 1ns / 1ps

module scope_ui #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer DB_MS   = 20,
    parameter integer LONG_MS = 800
)(
    input  wire clk,
    input  wire rst,
    input  wire key_in,
    output reg  ev_short,
    output reg  ev_long
);

    localparam integer DB_CNT   = (CLK_HZ / 1000) * DB_MS;
    localparam integer LONG_CNT = (CLK_HZ / 1000) * LONG_MS;

    reg [2:0]  key_sync;
    reg [23:0] db_cnt;
    reg [27:0] hold_cnt;
    reg        pressed;
    reg        long_fired;

    always @(posedge clk) begin
        if (rst) begin
            key_sync   <= 3'b111;
            db_cnt     <= 24'd0;
            hold_cnt   <= 28'd0;
            pressed    <= 1'b0;
            long_fired <= 1'b0;
            ev_short   <= 1'b0;
            ev_long    <= 1'b0;
        end
        else begin
            key_sync <= {key_sync[1:0], key_in};
            ev_short <= 1'b0;
            ev_long  <= 1'b0;

            if (key_sync[2] == 1'b1) begin          // 松开
                if (pressed && !long_fired)
                    ev_short <= 1'b1;
                pressed    <= 1'b0;
                long_fired <= 1'b0;
                db_cnt     <= 24'd0;
                hold_cnt   <= 28'd0;
            end
            else begin                              // 按下
                if (!pressed) begin
                    if (db_cnt == DB_CNT)
                        pressed <= 1'b1;
                    else
                        db_cnt <= db_cnt + 24'd1;
                end
                else if (!long_fired) begin
                    if (hold_cnt == LONG_CNT) begin
                        ev_long    <= 1'b1;
                        long_fired <= 1'b1;
                    end
                    else begin
                        hold_cnt <= hold_cnt + 28'd1;
                    end
                end
            end
        end
    end

endmodule
