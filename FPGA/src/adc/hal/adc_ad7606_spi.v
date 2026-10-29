//==============================================================================
// 层: ADC HAL(型号驱动)  文件: hal/adc_ad7606_spi.v
// 功能: AD7606 模块【串行模式】驱动（8 通道 16bit 同步采样，±5V/±10V）
//   本模块只负责产生 AD7606 的时序并把 DOUTA 上的 ch1..ch4 串行数据还原：
//     CONVST 上升沿启动转换 -> BUSY 高 -> BUSY 下降 -> CS 低 + 64 个 SCLK
//     -> DOUTA 依次输出 ch1..ch4 的 16bit(MSB first) -> CS 高
//   输出: 每 16bit 产生一个 r_valid 脉冲，r_ch=0..3，r_data=16bit 补码。
//   对齐/位宽/有符号转换交给 abs/adc_norm（SIGNED=1）。
// 引脚: CONVST(A/B 并联)、BUSY、CS、SCLK、DOUTA、RESET、SER(=1)、OS[2:0]、RANGE、STBY
// 时序: SCLK 半周期 = SPI_DIV 个 clk；一次转换约 64*2*SPI_DIV 个 clk。
//==============================================================================
`timescale 1ns / 1ps

module adc_ad7606_spi #(
    parameter integer RW        = 16,
    parameter integer SPI_DIV   = 4,     // SCLK 半周期(clk 数)
    parameter integer CONV_CYC  = 8,     // CONVST 高电平宽度(clk 数)
    parameter integer RST_CYC   = 200    // RESET 高电平宽度(clk 数)
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          enable,
    input  wire [15:0]   rate,        // 两次转换之间的 clk 数(0=连续)
    // AD7606 物理引脚
    output reg           convst,      // CONVST A + B
    output reg           cs_n,
    output reg           sclk,
    input  wire          douta,
    output reg           adc_reset,   // RESET 高有效
    output reg           ser,         // 1=串行模式
    output reg  [2:0]    os,          // 过采样 000=不开启
    output reg           range,       // 1=±10V 0=±5V
    output reg           stby,        // 1=正常工作
    input  wire          busy,
    // 采样流
    output reg  [RW-1:0] r_data,
    output reg  [1:0]    r_ch,
    output reg           r_valid,
    input  wire          r_ready,
    output reg           locked,
    output reg           error
);

    localparam [2:0] S_RST  = 3'd0,
                     S_IDLE = 3'd1,
                     S_CONV = 3'd2,
                     S_BUSY = 3'd3,
                     S_READ = 3'd4,
                     S_END  = 3'd5;

    reg [2:0]  state;
    reg [15:0] rst_cnt;
    reg [15:0] rate_cnt;
    reg [7:0]  conv_cnt;
    reg [19:0] busy_to;
    reg [6:0]  bit_idx;       // 0..63
    reg [3:0]  bit_in_ch;     // 0..15
    reg [15:0] shreg;
    reg [15:0] sclk_cnt;

    wire [15:0] shreg_nxt = {shreg[14:0], douta};

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_RST;
            rst_cnt   <= 16'd0;
            rate_cnt  <= 16'd0;
            conv_cnt  <= 8'd0;
            busy_to   <= 20'd0;
            bit_idx   <= 7'd0;
            bit_in_ch <= 4'd0;
            shreg     <= 16'd0;
            sclk_cnt  <= 16'd0;
            convst    <= 1'b0;
            cs_n      <= 1'b1;
            sclk      <= 1'b1;
            adc_reset <= 1'b1;
            ser       <= 1'b1;     // 串行模式
            os        <= 3'd0;     // 不过采样
            range     <= 1'b1;     // ±10V(悬空默认)
            stby      <= 1'b1;     // 正常
            r_data    <= {RW{1'b0}};
            r_ch      <= 2'd0;
            r_valid   <= 1'b0;
            locked    <= 1'b0;
            error     <= 1'b0;
        end
        else begin
            r_valid <= 1'b0;

            case (state)
                // 上电复位：RESET 保持 RST_CYC 个 clk
                S_RST: begin
                    adc_reset <= 1'b1;
                    if (rst_cnt == RST_CYC - 1) begin
                        rst_cnt   <= 16'd0;
                        adc_reset <= 1'b0;
                        locked    <= 1'b1;
                        state     <= S_IDLE;
                    end
                    else begin
                        rst_cnt <= rst_cnt + 16'd1;
                    end
                end

                // 等待采样节拍
                S_IDLE: begin
                    cs_n     <= 1'b1;
                    convst   <= 1'b0;
                    error    <= 1'b0;
                    if (!enable) begin
                        rate_cnt <= 16'd0;
                    end
                    else if (rate_cnt >= rate) begin
                        rate_cnt <= 16'd0;
                        conv_cnt <= CONV_CYC[7:0];
                        convst   <= 1'b1;
                        state    <= S_CONV;
                    end
                    else begin
                        rate_cnt <= rate_cnt + 16'd1;
                    end
                end

                // CONVST 高脉冲
                S_CONV: begin
                    if (conv_cnt == 8'd0) begin
                        convst <= 1'b0;
                        busy_to <= 20'd0;
                        state  <= S_BUSY;
                    end
                    else begin
                        conv_cnt <= conv_cnt - 8'd1;
                    end
                end

                // 等 BUSY 变低（带超时）
                S_BUSY: begin
                    if (busy_to > 20'd200_000) begin
                        error <= 1'b1;
                        state <= S_IDLE;
                    end
                    else if (busy == 1'b0) begin
                        cs_n      <= 1'b0;
                        sclk      <= 1'b1;   // 先拉高，等第一个下降沿输出 D15
                        sclk_cnt  <= 16'd0;
                        bit_idx   <= 7'd0;
                        bit_in_ch <= 4'd0;
                        shreg     <= 16'd0;
                        state     <= S_READ;
                    end
                    else begin
                        busy_to <= busy_to + 20'd1;
                    end
                end

                // 64 个 SCLK：下降沿输出，上升沿采样
                S_READ: begin
                    if (sclk_cnt == SPI_DIV - 1) begin
                        sclk_cnt <= 16'd0;
                        sclk     <= ~sclk;
                        if (sclk == 1'b0) begin
                            // 上升沿：采样当前位
                            shreg <= shreg_nxt;
                            if (bit_in_ch == 4'd15) begin
                                r_data    <= shreg_nxt;
                                r_ch      <= bit_idx[5:4];
                                r_valid   <= 1'b1;
                                bit_in_ch <= 4'd0;
                                shreg     <= 16'd0;
                                if (bit_idx == 7'd63)
                                    state <= S_END;
                                else
                                    bit_idx <= bit_idx + 7'd1;
                            end
                            else begin
                                bit_in_ch <= bit_in_ch + 4'd1;
                                bit_idx   <= bit_idx + 7'd1;
                            end
                        end
                    end
                    else begin
                        sclk_cnt <= sclk_cnt + 16'd1;
                    end
                end

                // 一帧结束
                S_END: begin
                    cs_n  <= 1'b1;
                    sclk  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_RST;
            endcase
        end
    end

endmodule
