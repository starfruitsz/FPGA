//==============================================================================
// 层: 应用(串口命令)  文件: app/scope_cmd.v   [v2: 新增 M/C/P/H 命令]
// 功能: 解析 ASCII 命令，输出"写使能 + 数值"单周期脉冲
// 协议: <字母><十六进制数字><CR/LF>，数字最多 4 位
//   T=时基分频  R=运行/冻结  A=触发使能  L=触发电平  E=边沿
//   S=滚动        M=触发模式(0自动/1正常/2单次)
//   C=触发源(0=CH0/1=CH1)  P=预触发点数  H=保持时间(采样点数)
//==============================================================================
`timescale 1ns / 1ps

module scope_cmd (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         tb_we,    output reg [15:0] tb_val,
    output reg         run_we,   output reg        run_val,
    output reg         ten_we,   output reg        ten_val,
    output reg         lvl_we,   output reg [9:0]  lvl_val,
    output reg         edg_we,   output reg        edg_val,
    output reg         scr_we,   output reg        scr_val,
    output reg         tmode_we, output reg [1:0]  tmode_val,
    output reg         tsrc_we,  output reg        tsrc_val,
    output reg         pre_we,   output reg [9:0]  pre_val,
    output reg         hold_we,  output reg [15:0] hold_val
);

    reg [7:0]  cmd;
    reg [15:0] acc;
    reg [3:0]  ndig;
    reg [3:0]  nib;
    reg        is_hex;
    reg        have_cmd;   // [修复] 第一个字符一律当命令字母，避免 A/C/E 被当十六进制数字

    // 字符解码
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
            tb_we<=0; tb_val<=0; run_we<=0; run_val<=0;
            ten_we<=0; ten_val<=0; lvl_we<=0; lvl_val<=0;
            edg_we<=0; edg_val<=0; scr_we<=0; scr_val<=0;
            tmode_we<=0; tmode_val<=0; tsrc_we<=0; tsrc_val<=0;
            pre_we<=0; pre_val<=0; hold_we<=0; hold_val<=0;
            cmd<=0; acc<=0; ndig<=0; have_cmd<=1'b0;
        end
        else begin
            tb_we<=1'b0; run_we<=1'b0; ten_we<=1'b0; lvl_we<=1'b0;
            edg_we<=1'b0; scr_we<=1'b0; tmode_we<=1'b0; tsrc_we<=1'b0;
            pre_we<=1'b0; hold_we<=1'b0;

            if (rx_valid) begin
                if ((rx_data == 8'h0D) || (rx_data == 8'h0A)) begin
                    case (cmd)
                        8'h54: begin tb_val    <= acc;        tb_we    <= 1'b1; end  // T
                        8'h52: begin run_val   <= acc[0];     run_we   <= 1'b1; end  // R
                        8'h41: begin ten_val   <= acc[0];     ten_we   <= 1'b1; end  // A
                        8'h4C: begin lvl_val   <= acc[9:0];   lvl_we   <= 1'b1; end  // L
                        8'h45: begin edg_val   <= acc[0];     edg_we   <= 1'b1; end  // E
                        8'h53: begin scr_val   <= acc[0];     scr_we   <= 1'b1; end  // S
                        8'h4D: begin tmode_val <= acc[1:0];   tmode_we <= 1'b1; end  // M
                        8'h43: begin tsrc_val  <= acc[0];     tsrc_we  <= 1'b1; end  // C
                        8'h50: begin pre_val   <= acc[9:0];   pre_we   <= 1'b1; end  // P
                        8'h48: begin hold_val  <= acc;        hold_we  <= 1'b1; end  // H
                        default: ;
                    endcase
                    cmd      <= 8'd0;
                    acc      <= 16'd0;
                    ndig     <= 4'd0;
                    have_cmd <= 1'b0;
                end
                else if (have_cmd && is_hex && (ndig != 4'd4)) begin
                    acc  <= {acc[11:0], nib};
                    ndig <= ndig + 4'd1;
                end
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
