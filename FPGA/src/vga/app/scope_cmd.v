//==============================================================================
// 层: 应用(串口命令)  文件: app/scope_cmd.v
// 功能: 【特性4 串口在线配置】ASCII 命令解析(与二进制 A/B 帧共存)
//
//   命令格式:  <字母><十六进制数><CR/LF>
//     T<4位>  设置采样分频 tb_div   (如 T0063 -> 100kS/s)
//     R<0|1>  运行/冻结
//     A<0|1>  触发使能
//     L<3位>  触发电平(0..3FF)
//     E<0|1>  触发边沿(0=上升 1=下降)
//     S<0|1>  滚动显示使能
//   例: "T1F40\r"  "R1\r"  "A1\r"  "L200\r"  "E1\r"  "S1\r"
//
//   非十六进制字节会被当作命令字母，二进制帧(0xA?/0xB?)不会触发提交(除非出现 0x0D)。
//==============================================================================
`timescale 1ns / 1ps

//
// ============================ 怎么读这个文件 ============================
// 串口命令解析器：把“T0063”这样的文本变成“写 tb_div=0x63”的一拍脉冲。
// 解析过程只有三个状态量：
//   cmd  —— 当前命令字母('T'/'R'/'A'/'L'/'E'/'S')
//   acc  —— 命令后面跟着的十六进制数字累加值
//   ndig —— 已经收到几个十六进制数字(最多 4 个)
// 收到回车(CR)或换行(LF)时才真正“提交”，这样半截数据不会生效。
// ======================================================================
module scope_cmd (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         tb_we,
    output reg  [15:0] tb_val,
    output reg         run_we,
    output reg         run_val,
    output reg         ten_we,
    output reg         ten_val,
    output reg         lvl_we,
    output reg  [9:0]  lvl_val,
    output reg         edg_we,
    output reg         edg_val,
    output reg         scr_we,
    output reg         scr_val
);

    reg [7:0]  cmd;
    reg [15:0] acc;
    reg [3:0]  ndig;

    // 十六进制字符 -> nibble
    reg [3:0] nib;
    reg       is_hex;
//------------------------------------------------------------------
// [字符解码] 把 ASCII 字符变成 4bit 数值：
//   '0'-'9' → 0-9，'A'-'F'/'a'-'f' → 10-15。
// 都用“减法”实现：字符码减去 '0' 或 'A'-10 即可，不需要查表。
// is_hex=0 表示这不是十六进制字符，上层会把它当成新的命令字母。
//------------------------------------------------------------------
    always @(*) begin
        is_hex = 1'b1;
        if      ((rx_data >= 8'h30) && (rx_data <= 8'h39)) nib = rx_data - 8'h30;
        else if ((rx_data >= 8'h41) && (rx_data <= 8'h46)) nib = rx_data - 8'h37;  // 'A'-'F'
        else if ((rx_data >= 8'h61) && (rx_data <= 8'h66)) nib = rx_data - 8'h57;  // 'a'-'f'
        else begin
            nib = 4'd0;
            is_hex = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            cmd     <= 8'd0;
            acc     <= 16'd0;
            ndig    <= 4'd0;
            tb_we   <= 1'b0;
            run_we  <= 1'b0;
            ten_we  <= 1'b0;
            lvl_we  <= 1'b0;
            edg_we  <= 1'b0;
            scr_we  <= 1'b0;
            tb_val  <= 16'd0;
            run_val <= 1'b0;
            ten_val <= 1'b0;
            lvl_val <= 10'd0;
            edg_val <= 1'b0;
            scr_val <= 1'b0;
        end
        else begin
            tb_we  <= 1'b0;
            run_we <= 1'b0;
            ten_we <= 1'b0;
            lvl_we <= 1'b0;
            edg_we <= 1'b0;
            scr_we <= 1'b0;

//------------------------------------------------------------------
// 每收到一个字节处理一次，三种情况：
//   1) 回车/换行 → 提交当前命令(发出对应的 we 脉冲)
//   2) 十六进制字符 → 累加进 acc
//   3) 其它字符 → 当作新的命令字母
// 提交时用 case(cmd) 分发，每个分支只更新一个寄存器和它的 we。
// 所有 we 在每拍开头先清 0，因此写使能天然是单拍脉冲。
//------------------------------------------------------------------
            if (rx_valid) begin
                if ((rx_data == 8'h0D) || (rx_data == 8'h0A)) begin   // 提交
                    case (cmd)
                        8'h54: begin tb_val  <= acc;          tb_we  <= 1'b1; end  // 'T'
                        8'h52: begin run_val <= acc[0];       run_we <= 1'b1; end  // 'R'
                        8'h41: begin ten_val <= acc[0];       ten_we <= 1'b1; end  // 'A'
                        8'h4C: begin lvl_val <= acc[9:0];     lvl_we <= 1'b1; end  // 'L'
                        8'h45: begin edg_val <= acc[0];       edg_we <= 1'b1; end  // 'E'
                        8'h53: begin scr_val <= acc[0];       scr_we <= 1'b1; end  // 'S'
                        default: ;
                    endcase
                    cmd  <= 8'd0;
                    acc  <= 16'd0;
                    ndig <= 4'd0;
                end
//------------------------------------------------------------------
// [累加] 左移 4 位再拼上新 nibble，等价于“十六进制左移一位”。
// 限制最多 4 位，避免超长输入把数值溢出成不可预期的结果。
//------------------------------------------------------------------
                else if (is_hex && (ndig != 4'd4)) begin
                    acc  <= {acc[11:0], nib};
                    ndig <= ndig + 4'd1;
                end
                else begin
                    cmd  <= rx_data;
                    acc  <= 16'd0;
                    ndig <= 4'd0;
                end
            end
        end
    end

endmodule
