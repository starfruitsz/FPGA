//==============================================================================
// 层: HAL(底层)  文件: hal/vram_sdp.v
// 功能: 简单双端口 RAM 封装(1 写 1 读, 同步读)
//   按 Gowin/Anlogic/Xilinx 通用写法编码，综合器会自动推断为 BSRAM/BRAM。
//   写优先: 同一时钟域、不同地址，读写互不干扰。
// 参数: DW 数据位宽, AW 地址位宽(深度=2^AW)
//==============================================================================
`timescale 1ns / 1ps

module vram_sdp #(
    parameter integer DW = 10,
    parameter integer AW = 10
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [DW-1:0] wdata,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0] rdata
);

    reg [DW-1:0] mem [0:(1<<AW)-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    always @(posedge clk) begin
        rdata <= mem[raddr];
    end

endmodule
