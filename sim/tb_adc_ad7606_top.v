`timescale 1ns / 1ps
//=============================================================================
// tb_adc_ad7606_top.v -- 验证 AD7606 完整采集通道（含 CSR 与归一化）
//   adc_ad7606_top = adc_cfg(CSR) + adc_ad7606_spi(时序) + adc_norm(归一化)
//   归一化公式: s_data = ((r_data ^ 16'h8000) >> (16-RES))，即补码 -> 偏移二进制 -> 取高 RES 位
//   同时验证 CSR 写入：0x28 改 SCLK 半周期、0x08 改采样间隔、0x00 读 ID
//=============================================================================
module tb_adc_ad7606_top;

    localparam integer RES = 10;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [7:0]  csr_addr  = 8'h00;
    reg  [31:0] csr_wdata = 32'd0;
    reg         csr_we    = 1'b0;
    wire [31:0] csr_rdata;

    wire        convst, cs_n, sclk, adc_reset, ser, range, stby;
    wire [2:0]  os;
    wire        busy, douta;
    wire [15:0] s_data;
    wire [1:0]  s_ch;
    wire        s_valid, locked, error;

    localparam [15:0] CH1 = 16'h1234;
    localparam [15:0] CH2 = 16'hEDCC;
    localparam [15:0] CH3 = 16'h0001;
    localparam [15:0] CH4 = 16'h8000;

    adc_ad7606_top #(.RES(RES), .DW(16), .SDIV_DEF(2), .OS_DEF(0), .RANGE_DEF(1)) dut (
        .clk(clk), .rst(rst),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_we(csr_we),
        .csr_rdata(csr_rdata),
        .convst(convst), .cs_n(cs_n), .sclk(sclk), .douta(douta), .busy(busy),
        .adc_reset(adc_reset), .ser(ser), .os(os), .range(range), .stby(stby),
        .s_data(s_data), .s_ch(s_ch), .s_valid(s_valid), .s_ready(1'b1),
        .locked(locked), .error(error)
    );

    ad7606_model #(.CONV_CLK(60)) u_adc (
        .clk(clk), .rst(rst), .convst(convst), .cs_n(cs_n), .sclk(sclk),
        .adc_reset(adc_reset), .busy(busy), .douta(douta),
        .ch1(CH1), .ch2(CH2), .ch3(CH3), .ch4(CH4)
    );

    always #10 clk = ~clk;          // 50MHz

    reg [15:0] got_data [0:3];
    reg [1:0]  got_ch   [0:3];
    integer n_valid = 0;
    integer errors  = 0;
    integer i;

    always @(posedge clk) if (s_valid) begin
        if (n_valid < 4) begin
            got_data[n_valid] = s_data;
            got_ch[n_valid]   = s_ch;
        end
        n_valid = n_valid + 1;
    end

    task csr_write(input [7:0] addr, input [31:0] wd);
        begin
            @(posedge clk);
            csr_addr  <= addr;
            csr_wdata <= wd;
            csr_we    <= 1'b1;
            @(posedge clk);
            csr_we    <= 1'b0;
        end
    endtask

    function [15:0] expect_norm(input [15:0] raw);
        expect_norm = (raw ^ 16'h8000) >> (16 - RES);
    endfunction

    initial begin
        $dumpfile("tb_adc_ad7606_top.vcd");
        $dumpvars(0, tb_adc_ad7606_top);

        repeat (5) @(posedge clk);
        rst = 1'b0;

        // CSR: SCLK 半周期 = 2 clk, 采样间隔 = 0(连续), 使能 = 1
        csr_write(8'h28, 32'd2);
        csr_write(8'h08, 32'd0);
        csr_write(8'h04, 32'd1);

        // 读 ID 寄存器
        @(posedge clk); csr_addr <= 8'h00;
        @(posedge clk);
        $display("[tb_adc_ad7606_top] ID = 0x%08X (expect 0x0100034A: ver=0100 impl=3 ch=4 res=10)", csr_rdata);

        i = 0;
        while ((n_valid < 4) && (i < 12000)) begin
            @(posedge clk);
            i = i + 1;
        end

        $display("[tb_adc_ad7606_top] 归一化 (RES=%0d, 16bit 补码 -> 偏移二进制 -> 取高 %0d 位)", RES, RES);
        for (i = 0; i < 4; i = i + 1)
            $display("    ch%0d: raw=0x%04X -> s_data=0x%04X (%0d), expect 0x%04X (%0d)  s_ch=%0d",
                     i, (i==0)?CH1:(i==1)?CH2:(i==2)?CH3:CH4,
                     got_data[i], got_data[i],
                     expect_norm((i==0)?CH1:(i==1)?CH2:(i==2)?CH3:CH4),
                     expect_norm((i==0)?CH1:(i==1)?CH2:(i==2)?CH3:CH4),
                     got_ch[i]);

        if (locked !== 1'b1) begin errors=errors+1; $display("  FAIL locked"); end
        if (error  !== 1'b0) begin errors=errors+1; $display("  FAIL error");  end
        if (n_valid < 4)     begin errors=errors+1; $display("  FAIL 采样流不足"); end

        for (i = 0; i < 4; i = i + 1) begin
            if (got_data[i] !== expect_norm((i==0)?CH1:(i==1)?CH2:(i==2)?CH3:CH4)) begin
                errors = errors + 1;
                $display("  FAIL ch%0d 归一化结果", i);
            end
            if (got_ch[i] !== i[1:0]) begin
                errors = errors + 1;
                $display("  FAIL ch%0d 通道号", i);
            end
        end

        if (errors == 0) $display("[tb_adc_ad7606_top] PASS");
        else             $display("[tb_adc_ad7606_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
