//==============================================================================
// 层: ADC ABS(配置)  文件: abs/adc_cfg.v
// 功能: 32bit CSR 寄存器组，集中存放 ADC 配置，新增参数只加地址、不改端口。
//   0x00 ID      {16'h0100, 4'd0, 4'(IMPL), 4'(CH), 4'(RES)}
//   0x04 CTRL    [0]=enable
//   0x08 RATE    [15:0] 采样率分频
//   0x0C GAIN    [7:0]  预留
//   0x10 OFFSET  [15:0] 预留(有符号)
//   0x14 STATUS  [1]=error [0]=locked
//   0x18 CH_EN   [3:0] 通道使能
//   0x1C FORMAT  [1]=signed [0]=align
//   0x100+ 厂商私有(预留)
//==============================================================================
`timescale 1ns / 1ps

module adc_cfg #(
    parameter integer IMPL   = 1,
    parameter integer RES    = 12,
    parameter integer ALIGN  = 1,
    parameter integer CH     = 1,
    parameter integer DW     = 16,
    parameter integer SDIV_DEF  = 4,     // 默认 SCLK 半周期
    parameter integer OS_DEF    = 0,     // 默认过采样
    parameter integer RANGE_DEF = 1      // 默认 1=±10V 0=±5V
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  csr_addr,
    input  wire [31:0] csr_wdata,
    input  wire        csr_we,
    output reg  [31:0] csr_rdata,
    input  wire        status_locked,
    input  wire        status_error,
    output reg         enable,
    output reg  [15:0] rate,
    output reg  [7:0]  gain,
    output reg  [15:0] offset,
    output reg  [3:0]  ch_en,
    output reg         fmt_align,
    output reg         fmt_signed,
    output reg  [15:0] sdiv,
    output reg  [2:0]  os_sel,
    output reg         range_sel
);
    always @(*) begin
        case (csr_addr)
            8'h00: csr_rdata = {16'h0100, 4'd0, IMPL[3:0], CH[3:0], RES[3:0]};
            8'h04: csr_rdata = {31'd0, enable};
            8'h08: csr_rdata = {16'd0, rate};
            8'h0C: csr_rdata = {24'd0, gain};
            8'h10: csr_rdata = {{16{offset[15]}}, offset};
            8'h14: csr_rdata = {30'd0, status_error, status_locked};
            8'h18: csr_rdata = {28'd0, ch_en};
            8'h1C: csr_rdata = {30'd0, fmt_signed, fmt_align};
            8'h20: csr_rdata = {31'd0, range_sel};
            8'h24: csr_rdata = {29'd0, os_sel};
            8'h28: csr_rdata = {16'd0, sdiv};
            default: csr_rdata = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            enable <= 1'b1;
            rate   <= 16'd0;
            gain   <= 8'd0;
            offset <= 16'd0;
            ch_en  <= 4'h1;
            fmt_align  <= ALIGN[0];
            fmt_signed <= 1'b0;
            sdiv       <= SDIV_DEF[15:0];
            os_sel     <= OS_DEF[2:0];
            range_sel  <= RANGE_DEF[0];
        end
        else if (csr_we) begin
            case (csr_addr)
                8'h04: enable <= csr_wdata[0];
                8'h08: rate   <= csr_wdata[15:0];
                8'h0C: gain   <= csr_wdata[7:0];
                8'h10: offset <= csr_wdata[15:0];
                8'h18: ch_en  <= csr_wdata[3:0];
                8'h1C: begin fmt_align <= csr_wdata[0]; fmt_signed <= csr_wdata[1]; end
                8'h20: range_sel <= csr_wdata[0];
                8'h24: os_sel    <= csr_wdata[2:0];
                8'h28: sdiv      <= csr_wdata[15:0];
                default: ;
            endcase
        end
    end
endmodule
