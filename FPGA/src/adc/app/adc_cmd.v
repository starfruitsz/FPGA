//==============================================================================
// 层: ADC APP(命令)  文件: app/adc_cmd.v
// 功能: ADC 专用串口命令解析器（与示波器 scope_cmd 解耦，各解析各的）
// 协议: <字母><十六进制数字><CR/LF>，最多 4 位
//   R = RANGE   0x20  (1=±10V 0=±5V)
//   O = OS      0x24  (0..6 过采样)
//   S = SDIV    0x28  (SCLK 半周期)
//   K = RATE    0x08  (采样间隔 clk)
//   N = ENABLE  0x04  (bit0 使能)
// 说明: 非本模块命令的字母会被忽略(不产生写)，不影响 scope_cmd。
//==============================================================================
`timescale 1ns / 1ps

module adc_cmd (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [7:0]  csr_addr,
    output reg  [31:0] csr_wdata,
    output reg         csr_we
);
    reg [7:0]  cmd;
    reg [15:0] acc;
    reg [3:0]  ndig;
    reg [3:0]  nib;
    reg        is_hex;
    reg        have_cmd;

    // 十六进制字符解码
    always @(*) begin
        is_hex = 1'b1;
        if ((rx_data >= 8'h30) && (rx_data <= 8'h39))
            nib = rx_data - 8'h30;
        else if ((rx_data >= 8'h41) && (rx_data <= 8'h46))
            nib = rx_data - 8'h37;
        else if ((rx_data >= 8'h61) && (rx_data <= 8'h66))
            nib = rx_data - 8'h57;
        else begin
            nib = 4'd0;
            is_hex = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            csr_we    <= 1'b0;
            csr_addr  <= 8'd0;
            csr_wdata <= 32'd0;
            cmd       <= 8'd0;
            acc       <= 16'd0;
            ndig      <= 4'd0;
            have_cmd  <= 1'b0;
        end
        else begin
            csr_we <= 1'b0;

            if (rx_valid) begin
                // 回车/换行：提交
                if ((rx_data == 8'h0D) || (rx_data == 8'h0A)) begin
                    if (have_cmd) begin
                        case (cmd)
                            8'h52: begin csr_addr <= 8'h20; csr_wdata <= {31'd0, acc[0]};   csr_we <= 1'b1; end // R
                            8'h4F: begin csr_addr <= 8'h24; csr_wdata <= {29'd0, acc[2:0]}; csr_we <= 1'b1; end // O
                            8'h53: begin csr_addr <= 8'h28; csr_wdata <= {16'd0, acc};      csr_we <= 1'b1; end // S
                            8'h4B: begin csr_addr <= 8'h08; csr_wdata <= {16'd0, acc};      csr_we <= 1'b1; end // K
                            8'h4E: begin csr_addr <= 8'h04; csr_wdata <= {31'd0, acc[0]};   csr_we <= 1'b1; end // N
                            default: ;
                        endcase
                    end
                    cmd      <= 8'd0;
                    acc      <= 16'd0;
                    ndig     <= 4'd0;
                    have_cmd <= 1'b0;
                end
                // 已有命令字母：十六进制数字累加
                else if (have_cmd && is_hex && (ndig != 4'd4)) begin
                    acc  <= {acc[11:0], nib};
                    ndig <= ndig + 4'd1;
                end
                // 第一个非回车字符：作为命令字母
                else if (!have_cmd) begin
                    cmd      <= rx_data;
                    acc      <= 16'd0;
                    ndig     <= 4'd0;
                    have_cmd <= 1'b1;
                end
                else begin
                    // 命令后出现非十六进制字符：忽略
                end
            end
        end
    end
endmodule
