//==============================================================================
// 层: HAL(底层硬件抽象)  文件: hal/vga_timing.v
// 功能: 通用 VGA 时序发生器（与厂商无关，纯 RTL）
//   - 参数化：分辨率/前后肩/同步宽度/同步极性/像素使能分频
//   - 输出 px/py 为"当前像素坐标"，pix_ce 为像素节拍
//   - 不产生时钟：用 pix_ce 在系统时钟域内节拍化，避免派生时钟
// 使用: 640x480@60 取 H_VIS=640,H_FP=16,H_SYNC=96,H_BP=48,
//        V_VIS=480,V_FP=10,V_SYNC=2,V_BP=33, H_POL=0,V_POL=0, PIX_DIV=2
//       (50MHz/2 = 25MHz 像素节拍，59.5Hz)
//==============================================================================
`timescale 1ns / 1ps

module vga_timing #(
    parameter integer H_VIS   = 640,
    parameter integer H_FP    = 16,
    parameter integer H_SYNC  = 96,
    parameter integer H_BP    = 48,
    parameter integer V_VIS   = 480,
    parameter integer V_FP    = 10,
    parameter integer V_SYNC  = 2,
    parameter integer V_BP    = 33,
    parameter integer H_POL   = 0,     // 0=同步负极性(640x480) 1=正极性(800x600)
    parameter integer V_POL   = 0,
    parameter integer PIX_DIV = 2      // 像素节拍分频: 2 => 50MHz/2 = 25MHz
)(
    input  wire        clk,
    input  wire        rst,
    output wire        pix_ce,   // 像素节拍(高有效)
    output wire        hs,
    output wire        vs,
    output wire        de,       // 有效显示区
    output wire [11:0] px,       // 0 .. H_VIS-1
    output wire [11:0] py        // 0 .. V_VIS-1
);

localparam integer H_TOTAL = H_VIS + H_FP + H_SYNC + H_BP;   // 800
localparam integer V_TOTAL = V_VIS + V_FP + V_SYNC + V_BP;   // 525

reg [11:0] hcnt;
reg [11:0] vcnt;
reg [7:0]  div_cnt;

//------------------------------------------------------------------
// 像素节拍: 每 PIX_DIV 个系统时钟产生 1 个像素
// 用"计数器最高值"作为节拍标志，使像素数据在本拍后半段稳定
//------------------------------------------------------------------
always @(posedge clk) begin
    if (rst)
        div_cnt <= 8'd0;
    else if (div_cnt == PIX_DIV-1)
        div_cnt <= 8'd0;
    else
        div_cnt <= div_cnt + 8'd1;
end

assign pix_ce = (div_cnt == PIX_DIV-1);

//------------------------------------------------------------------
// 行列计数: 仅在像素节拍推进一次，保证 px/py 在整个像素周期内稳定
//------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        hcnt <= 12'd0;
        vcnt <= 12'd0;
    end
    else if (pix_ce) begin
        if (hcnt == H_TOTAL-1) begin
            hcnt <= 12'd0;
            if (vcnt == V_TOTAL-1)
                vcnt <= 12'd0;
            else
                vcnt <= vcnt + 12'd1;
        end
        else begin
            hcnt <= hcnt + 12'd1;
        end
    end
end

assign px = hcnt;
assign py = vcnt;

//------------------------------------------------------------------
// 同步信号/有效区
//   hs_act = 处于行同步窗口内(逻辑有效)；H_POL 决定最终电平
//------------------------------------------------------------------
wire hs_act = (hcnt >= (H_VIS+H_FP)) && (hcnt < (H_VIS+H_FP+H_SYNC));
wire vs_act = (vcnt >= (V_VIS+V_FP)) && (vcnt < (V_VIS+V_FP+V_SYNC));

assign hs = H_POL ? hs_act : ~hs_act;
assign vs = V_POL ? vs_act : ~vs_act;
assign de = (hcnt < H_VIS) && (vcnt < V_VIS);

endmodule
