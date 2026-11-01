//==============================================================================
// 层: 应用(控制)  文件: app/decim512.v
// 功能: 512 点累加抽取 —— 把 ADCLK(3.15MHz) 的采样降到 6152Hz 再送带通+ADRC
//       累加 512 个 10bit 采样后右移 9 位得到平均值（等效 512 点平均滤波，
//       同时抑制混叠与量化噪声），输出一个 10bit 码 + 一个 valid 脉冲。
//==============================================================================
`timescale 1ns / 1ps

module decim512 (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 1=来一个 ADC 采样（ad_val_valid）
    input  wire [9:0]  din,
    output reg  [9:0]  dout,
    output reg         dvalid
);

    reg [18:0] acc;      // 512*1023 = 523776 < 2^19
    reg [9:0]  cnt;

    always @(posedge clk) begin
        if (rst) begin
            acc <= 19'd0; cnt <= 10'd0; dout <= 10'd512; dvalid <= 1'b0;
        end
        else begin
            dvalid <= 1'b0;
            if (en) begin
                if (cnt == 10'd511) begin
                    dout   <= (acc + {14'b0, din}) >> 9;   // 512 点平均
                    dvalid <= 1'b1;
                    acc    <= 19'd0;
                    cnt    <= 10'd0;
                end
                else begin
                    acc <= acc + {9'b0, din};
                    cnt <= cnt + 10'd1;
                end
            end
        end
    end

endmodule
