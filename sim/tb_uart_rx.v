`timescale 1ns / 1ps
//=============================================================================
// tb_uart_rx.v -- 验证 uart_rx.v（8N1 接收，位中点采样）
//   50MHz / 115200 => 每位 434 个时钟 = 8680ns
//   激励由 TB 按位翻转 rx 引脚产生，检查 po_data / po_flag
//=============================================================================
module tb_uart_rx;

    localparam integer UART_BPS = 115200;
    localparam integer CLK_FREQ = 50_000_000;
    localparam integer BIT_NS   = (CLK_FREQ/UART_BPS) * 20;   // 8680

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        rx    = 1'b1;
    wire [7:0] po_data;
    wire       po_flag;

    uart_rx #(.UART_BPS(UART_BPS), .CLK_FREQ(CLK_FREQ)) dut (
        .sys_clk(clk), .sys_rst_n(rst_n), .rx(rx),
        .po_data(po_data), .po_flag(po_flag)
    );

    always #10 clk = ~clk;

    integer n_byte = 0;
    reg [7:0] got [0:15];

    always @(posedge clk) if (po_flag) begin
        if (n_byte < 16) got[n_byte] = po_data;
        n_byte = n_byte + 1;
    end

    task send_byte(input [7:0] b);
        integer k;
        begin
            rx = 1'b0;                    // 起始位
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                rx = b[k];                // LSB 先发
                #(BIT_NS);
            end
            rx = 1'b1;                    // 停止位
            #(BIT_NS);
        end
    endtask

    integer errors = 0;
    integer i;

    initial begin
        $dumpfile("tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h5A);

        repeat (200) @(posedge clk);

        $display("[tb_uart_rx] 位周期 = %0d ns", BIT_NS);
        $display("  收到 %0d 字节", n_byte);
        for (i = 0; i < 5; i = i + 1)
            $display("    byte%0d = 0x%02X", i, got[i]);

        if (n_byte != 5) begin errors=errors+1; $display("  FAIL 字节数"); end
        if (got[0] !== 8'h55) begin errors=errors+1; $display("  FAIL 0x55"); end
        if (got[1] !== 8'hAA) begin errors=errors+1; $display("  FAIL 0xAA"); end
        if (got[2] !== 8'h00) begin errors=errors+1; $display("  FAIL 0x00"); end
        if (got[3] !== 8'hFF) begin errors=errors+1; $display("  FAIL 0xFF"); end
        if (got[4] !== 8'h5A) begin errors=errors+1; $display("  FAIL 0x5A"); end

        if (errors == 0) $display("[tb_uart_rx] PASS");
        else             $display("[tb_uart_rx] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
