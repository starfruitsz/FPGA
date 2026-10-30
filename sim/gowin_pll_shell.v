`timescale 1ns / 1ps
//=============================================================================
// gowin_pll_shell.v -- Gowin_PLL 的**行为空壳**（仅仿真，不综合）
//
// 为什么需要它：
//   真正的 gowin_pll.v 例化了高云原语 PLLA，Icarus 无法解析（没有该原语的模型）。
//   一旦某个顶层真的例化了 Gowin_PLL，就必须在仿真工程里用本文件替换 gowin_pll.v。
//
// 现状（重要）：
//   本工程**两个总顶层都没有例化 Gowin_PLL**——adda.v 里两处例化都被注释掉了
//   （第 385 行与第 412 行附近），1kHz 时钟改由 divider 提供；fifo_top 同样未例化。
//   所以仿真 adda_scope_top / sparkroad_scope_top **并不需要**本文件。
//   本文件为"以后把 PLL 启用（例如用 25.175MHz 换掉 24MHz 像素时钟）"预留。
//
// 参数来源 gowin_pll.ipc：CLKIN=50MHz, IDIV=1, MDIV=16 -> VCO 800MHz, ODIV=128
//   即 clkout = 50MHz * 16 / 128 = 6.25MHz，两路同频同相。
//
// 用法：
//   编译时用本文件替代 FPGA/src/gowin_pll/gowin_pll.v，例如
//     iverilog -g2005 -o out.vvp tb.v gowin_pll_shell.v adda.v ...
//
// 限制：
//   - 立即起振，不模拟 PLLA 的锁定时间（真实器件约几十 us）；
//   - 不模拟抖动、相位噪声、占空比误差；
//   - 不做时钟域检查，跨域问题仍需人工确认。
//=============================================================================
module Gowin_PLL (
    output reg clkout0,
    output reg clkout1,
    input  wire clkin
);

    // 50MHz / 8 = 6.25MHz：每 4 个输入周期翻转一次
    reg [2:0] div_cnt;

    initial begin
        clkout0 = 1'b0;
        clkout1 = 1'b0;
        div_cnt = 3'd0;
    end

    always @(posedge clkin) begin
        div_cnt <= div_cnt + 3'd1;
        if (div_cnt == 3'd3) begin
            clkout0 <= ~clkout0;
            clkout1 <= ~clkout1;
        end
    end

endmodule
