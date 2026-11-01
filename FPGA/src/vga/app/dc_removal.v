//==============================================================================
// 层: 应用(显示)  文件: app/dc_removal.v
// 功能: ADC 直流偏置消除（交流耦合 / 自动校零）
//
//   背景：ADC 采集到的码值往往整体抬着一个直流分量（传感器/模块零点、
//         基准电压偏移等），屏幕上表现为整条波形上下平移，压住刻度。
//
//   做法：用一个很慢的一阶均值跟踪直流分量，再从每个采样里减掉：
//       mean += (x - mean) / 1024      （时间常数 ≈1024 个采样点）
//       y     = x - mean + 512         （减掉直流后重新摆到屏幕中心）
//   时间常数远大于 50Hz 一个周期（20ms），所以对波形本身几乎无影响，
//   只把“整体抬升/下沉”这个缓慢分量去掉 —— 典型示波器的 AC 耦合。
//
//   注意：只作用在**显示通路**上，采集/触发/测量/ADRC 控制回路完全不受影响。
//         上电后第一个采样直接把 mean 置成该值，不会有阶跃冲击。
//==============================================================================
`timescale 1ns / 1ps

module dc_removal (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 步进使能（= 采集写使能 we）
    input  wire        dc_on,     // 1=启用偏置消除（AD/DA 模式）
    input  wire [9:0]  din,
    output wire [9:0]  dout
);

    reg signed [23:0] mean;       // 直流均值 Q8
    reg               primed;

    wire signed [23:0] xq  = {14'b0, din} <<< 8;     // 输入 Q8
    wire signed [23:0] err = xq - mean;
    wire signed [23:0] inc = err >>> 10;             // alpha = 1/1024

    // 去除直流后的偏移量（Q8），限幅到 ±512 码
    wire signed [23:0] yq = err >>> 8;               // Q8 -> 码
    wire signed [23:0] yc = (yq > 24'sd511)  ? 24'sd511  :
                             (yq < -24'sd512) ? -24'sd512 : yq;

    assign dout = dc_on ? (yc[9:0] + 10'd512) : din;

    always @(posedge clk) begin
        if (rst) begin
            mean   <= 24'sd0;
            primed <= 1'b0;
        end
        else if (en) begin
            if (!primed) begin
                mean   <= xq;          // 第一个采样直接当初始直流
                primed <= 1'b1;
            end
            else if (dc_on) begin
                mean <= mean + inc;    // 缓慢跟踪直流
            end
        end
    end

endmodule

