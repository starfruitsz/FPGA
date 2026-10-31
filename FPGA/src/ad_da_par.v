//==============================================================================
// 层: HAL(并口 AD/DA)  文件: ad_da_par.v
// 功能: 驱动外接 24 脚并口 AD/DA 模块
//       模块引脚: VCC GND AD0..AD9 ADCLK DA0..DA9 DACLK（两个时钟由 FPGA 产生）
//   1) ADCLK / DACLK : 系统时钟 8 分频、占空比严格 50%
//        24MHz   -> 3.0MHz
//        25.2MHz -> 3.15MHz
//   2) AD 通路: 在 ad_clk 的反相沿（下降沿）锁存 ad_data[9:0]，
//      再打两拍同步后输出 s_data/s_valid（s_valid 与 s_data 同拍的单拍脉冲）
//   3) DA 通路: 在 da_clk 的反相沿（下降沿）更新 da_out[9:0]（顶层送 ADRC 的
//      clamp(u+512)），数据保持整整一个 DACLK 周期；外部 DAC 在 DACLK 的正相沿
//      （上升沿）锁存，于是数据相对锁存沿有半个周期的建立时间
// 说明:
//   - ad_clk/da_clk 是同一个计数器的寄存器输出，相位相同，引脚上没有组合毛刺
//   - AD 采样点放在 ADCLK 的下降沿: 外部 ADC 在 ADCLK 上升沿之后才更新数据，
//     半个周期后再采，正好落在数据眼图中间
//   - DA 更新点放在 DACLK 的下降沿: 外部 DAC 在上升沿取数，反相沿更新可保证
//     半个周期的建立时间（若同沿更新，DAC 的 setup 时间会被吃掉）
//   - 时钟只有 3MHz，跨回 clk 域只是"外部器件 -> FPGA"的亚稳态问题，
//     一级捕获 + 两级同步即可；这条路径在约束里按 false_path / max_delay 处理
//==============================================================================
`timescale 1ns / 1ps

module ad_da_par #(
    parameter integer DIV_LOG2 = 3          // 分频比 = 2^DIV_LOG2 = 8
)(
    input  wire        clk,                 // 系统时钟
    input  wire        rst,                 // 复位，高有效（与工程内部约定一致）

    // ---- 并口 AD ----
    input  wire [9:0]  ad_data,             // AD0..AD9: 外部 ADC 并行数据
    output wire        ad_clk,              // ADCLK: clk/8，50% 占空比
    output wire [9:0]  s_data,              // 同步后的 AD 数据（已在 clk 域）
    output wire        s_valid,             // s_data 有效，单拍脉冲

    // ---- 并口 DA ----
    input  wire [9:0]  da_data,             // 待输出码（顶层接 ch1_val）
    output wire        da_clk,              // DACLK: clk/8，50% 占空比
    output reg  [9:0]  da_out               // DA0..DA9: 锁存后的输出码
);

    localparam integer DIV = (1 << DIV_LOG2);              // 8
    localparam [DIV_LOG2-1:0] CNT_LO = DIV/2 - 1;          // 3: 低半周最后一拍
    localparam [DIV_LOG2-1:0] CNT_HI = DIV - 1;            // 7: 高半周最后一拍

    reg [DIV_LOG2-1:0] div_cnt;
    reg                clk_div;

    //------------------------------------------------------------------
    // 8 分频方波: 低 4 拍 + 高 4 拍，占空比严格 50%
    //   CNT_LO 处翻高 -> ad_clk/da_clk 的上升沿
    //   CNT_HI 处翻低 -> ad_clk/da_clk 的下降沿（AD 的采样点）
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= {DIV_LOG2{1'b0}};
            clk_div <= 1'b0;
        end
        else begin
            div_cnt <= div_cnt + 1'b1;
            if (div_cnt == CNT_LO)      clk_div <= 1'b1;
            else if (div_cnt == CNT_HI) clk_div <= 1'b0;
        end
    end

    assign ad_clk = clk_div;
    assign da_clk = clk_div;

    //------------------------------------------------------------------
    // AD 通路: ad_clk 反相沿捕获 + 两级同步
    //   ad_fall 与 ad_clk 变低是同一个时钟沿，此刻 ad_data 已经稳定了半个周期
    //------------------------------------------------------------------
    wire ad_fall = (div_cnt == CNT_HI);        // 本拍末 clk_div 由 1 变 0

    reg [9:0] ad_cap;                          // 捕获拍: 源同步采样
    reg [9:0] ad_sync1, ad_sync2;              // 两级同步器
    reg       vld1, vld2, vld3;                // 有效标志与数据走同一条流水线

    always @(posedge clk) begin
        if (rst) begin
            ad_cap   <= 10'd0;
            ad_sync1 <= 10'd0;
            ad_sync2 <= 10'd0;
            vld1     <= 1'b0;
            vld2     <= 1'b0;
            vld3     <= 1'b0;
        end
        else begin
            if (ad_fall) ad_cap <= ad_data;    // ad_clk 反相沿: 锁存 AD0..AD9
            ad_sync1 <= ad_cap;                // 同步器第一级
            ad_sync2 <= ad_sync1;              // 同步器第二级
            vld1     <= ad_fall;
            vld2     <= vld1;
            vld3     <= vld2;
        end
    end

    assign s_data  = ad_sync2;                 // 两拍同步后的数据
    assign s_valid = vld3;                     // 与 s_data 同拍的单拍脉冲

    //------------------------------------------------------------------
    // DA 通路: da_clk 反相沿（下降沿）更新
    //   本拍末 clk_div 由高变低，同拍把 da_data 打进 da_out，之后保持整整
    //   一个 DACLK 周期；外部 DAC 在 DACLK 正相沿（上升沿）锁存，正好落在
    //   数据稳定区中间，建立时间为半个 DACLK 周期。
    //------------------------------------------------------------------
    wire da_fall = (div_cnt == CNT_HI);        // 本拍末 clk_div 由 1 变 0

    always @(posedge clk) begin
        if (rst)          da_out <= 10'd0;
        else if (da_fall) da_out <= da_data;   // da_clk 反相沿: 更新 DA0..DA9
    end

endmodule
