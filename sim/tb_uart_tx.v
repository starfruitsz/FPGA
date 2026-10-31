`timescale 1ns / 1ps
//=============================================================================
// tb_uart_tx.v -- 验证 uart_tx.v 的 16bit 双帧 8N1 发送
//   50MHz / 115200 => 每位 434 个时钟 = 8680ns，一帧 21 个位时隙
//   发送 0xA55A: 先发低字节 0x5A(LSB 先), 再发高字节 0xA5
//   时隙: 0=起始 1..8=低字节 9,10=停止 11=起始 12..19=高字节 20=停止
//=============================================================================
module tb_uart_tx;

    localparam integer UART_BPS = 115200;
    localparam integer CLK_FREQ = 50_000_000;
    localparam integer BIT_NS   = (CLK_FREQ/UART_BPS) * 20;   // 434*20 = 8680

    reg         clk   = 1'b0;
    reg         rst_n = 1'b0;
    reg  [15:0] pi_data = 16'hA55A;
    reg         pi_flag = 1'b0;
    wire        tx;

    uart_tx #(.UART_BPS(UART_BPS), .CLK_FREQ(CLK_FREQ)) dut (
        .sys_clk(clk), .sys_rst_n(rst_n),
        .pi_data(pi_data), .pi_flag(pi_flag), .tx(tx)
    );

    always #10 clk = ~clk;         // 50MHz

    reg bits [0:20];
    reg [7:0] byte_lo, byte_hi;
    integer i, errors = 0;

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // 给一个单周期 pi_flag 启动一次发送
        @(posedge clk);
        pi_flag <= 1'b1;
        @(posedge clk);
        pi_flag <= 1'b0;

        // 等起始位下降沿
        @(negedge tx);
        // 采样到起始位中点
        #(BIT_NS/2);
        bits[0] = tx;

        // 依次采样 20 个位时隙的中点
        for (i = 1; i <= 20; i = i + 1) begin
            #(BIT_NS);
            bits[i] = tx;
        end

        byte_lo = {bits[8], bits[7], bits[6], bits[5], bits[4], bits[3], bits[2], bits[1]};
        byte_hi = {bits[19],bits[18],bits[17],bits[16],bits[15],bits[14],bits[13],bits[12]};

        $display("[tb_uart_tx] 发送 0x%04X, 位时隙 = %0d ns", pi_data, BIT_NS);
        $display("  slot0(起始)=%b  slot9=%b slot10=%b  slot20=%b",
                 bits[0], bits[9], bits[10], bits[20]);
        $display("  低字节 = 0x%02X (expect 0x5A)", byte_lo);
        $display("  高字节 = 0x%02X (expect 0xA5)", byte_hi);

        if (bits[0]  !== 1'b0) begin errors=errors+1; $display("  FAIL 起始位");   end
        if (bits[9]  !== 1'b1) begin errors=errors+1; $display("  FAIL 停止位1");  end
        if (bits[10] !== 1'b1) begin errors=errors+1; $display("  FAIL 停止位2");  end
        if (bits[20] !== 1'b1) begin errors=errors+1; $display("  FAIL 帧尾停止位"); end
        if (byte_lo  !== 8'h5A) begin errors=errors+1; $display("  FAIL 低字节");  end
        if (byte_hi  !== 8'hA5) begin errors=errors+1; $display("  FAIL 高字节");  end

        if (errors == 0) $display("[tb_uart_tx] PASS");
        else             $display("[tb_uart_tx] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
