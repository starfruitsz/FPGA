`timescale 1ns / 1ps
//=============================================================================
// tb_cmd_chain.v -- 串口命令端到端验证（uart_rx -> scope_cmd / adc_cmd）
//   这是上板调参的唯一入口，此前完全没有验证过。
//   验证点:
//     1) uart_rx 把 ASCII 字节交给两个解析器
//     2) scope_cmd 正确解析 T/R/A/L/E/S/M/C/P/H 十条命令
//     3) adc_cmd   正确解析 R/O/S/K/N 五条命令，并写对 CSR 地址
//     4) 两个解析器互不干扰: 示波器命令不产生 CSR 写，ADC 命令不产生 scope 写
//     5) 同一字母在两边的不同含义(R/S)会各写各的
//     6) 未知命令字母/小写 不产生任何写
//=============================================================================
module tb_cmd_chain;

    localparam integer UART_BPS = 115200;
    localparam integer CLK_FREQ = 50_000_000;
    localparam integer BIT_NS   = (CLK_FREQ/UART_BPS) * 20;   // 8680

    reg clk   = 1'b0;
    reg rst   = 1'b1;
    reg rx    = 1'b1;

    wire [7:0] po_data;
    wire       po_flag;

    // scope_cmd 输出
    wire        tb_we,   run_we,  ten_we,  lvl_we,  edg_we,  scr_we,  tmode_we, tsrc_we, pre_we, hold_we;
    wire [15:0] tb_val;
    wire        run_val, ten_val, edg_val, scr_val, tsrc_val;
    wire [9:0]  lvl_val, pre_val;
    wire [1:0]  tmode_val;
    wire [15:0] hold_val;

    // adc_cmd 输出
    wire [7:0]  csr_addr;
    wire [31:0] csr_wdata;
    wire        csr_we;

    uart_rx #(.UART_BPS(UART_BPS), .CLK_FREQ(CLK_FREQ)) u_rx (
        .sys_clk(clk), .sys_rst_n(~rst), .rx(rx),
        .po_data(po_data), .po_flag(po_flag)
    );

    scope_cmd u_scope_cmd (
        .clk(clk), .rst(rst), .rx_data(po_data), .rx_valid(po_flag),
        .tb_we(tb_we), .tb_val(tb_val),
        .run_we(run_we), .run_val(run_val),
        .ten_we(ten_we), .ten_val(ten_val),
        .lvl_we(lvl_we), .lvl_val(lvl_val),
        .edg_we(edg_we), .edg_val(edg_val),
        .scr_we(scr_we), .scr_val(scr_val),
        .tmode_we(tmode_we), .tmode_val(tmode_val),
        .tsrc_we(tsrc_we), .tsrc_val(tsrc_val),
        .pre_we(pre_we), .pre_val(pre_val),
        .hold_we(hold_we), .hold_val(hold_val)
    );

    adc_cmd u_adc_cmd (
        .clk(clk), .rst(rst), .rx_data(po_data), .rx_valid(po_flag),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_we(csr_we)
    );

    always #10 clk = ~clk;

    // ---- 写脉冲记录 ----
    integer n_tb=0, n_run=0, n_ten=0, n_lvl=0, n_edg=0, n_scr=0, n_tmode=0, n_tsrc=0, n_pre=0, n_hold=0;
    integer n_csr=0;
    reg [15:0] v_tb, v_hold;
    reg        v_run, v_ten, v_edg, v_scr, v_tsrc;
    reg [1:0]  v_tmode;
    reg [9:0]  v_lvl, v_pre;
    reg [7:0]  v_addr;
    reg [31:0] v_wdata;

    always @(posedge clk) begin
        if (tb_we)    begin n_tb=n_tb+1;       v_tb=tb_val;       end
        if (run_we)   begin n_run=n_run+1;     v_run=run_val;     end
        if (ten_we)   begin n_ten=n_ten+1;     v_ten=ten_val;     end
        if (lvl_we)   begin n_lvl=n_lvl+1;     v_lvl=lvl_val;     end
        if (edg_we)   begin n_edg=n_edg+1;     v_edg=edg_val;     end
        if (scr_we)   begin n_scr=n_scr+1;     v_scr=scr_val;     end
        if (tmode_we) begin n_tmode=n_tmode+1; v_tmode=tmode_val[1:0]; end
        if (tsrc_we)  begin n_tsrc=n_tsrc+1;   v_tsrc=tsrc_val;   end
        if (pre_we)   begin n_pre=n_pre+1;     v_pre=pre_val;     end
        if (hold_we)  begin n_hold=n_hold+1;   v_hold=hold_val;   end
        if (csr_we)   begin n_csr=n_csr+1;     v_addr=csr_addr;   v_wdata=csr_wdata; end
    end

    task send_byte(input [7:0] b);
        integer k;
        begin
            rx = 1'b0;
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                rx = b[k];
                #(BIT_NS);
            end
            rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    task send_cmd(input [7:0] c0, c1, c2, c3, c4);
        begin
            if (c0 != 8'h00) send_byte(c0);
            if (c1 != 8'h00) send_byte(c1);
            if (c2 != 8'h00) send_byte(c2);
            if (c3 != 8'h00) send_byte(c3);
            if (c4 != 8'h00) send_byte(c4);
            send_byte(8'h0D);            // 回车提交
            repeat (20) @(posedge clk);
        end
    endtask

    integer errors = 0;

    initial begin
        $dumpfile("tb_cmd_chain.vcd");
        $dumpvars(0, tb_cmd_chain);
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        $display("[tb_cmd_chain] 串口命令端到端");

        // ---------- 示波器命令 ----------
        send_cmd("T", "0", "0", "6", "3");
        $display("  T0063 -> tb_we=%0d val=0x%04X", n_tb, v_tb);
        if (n_tb != 1 || v_tb !== 16'h0063) begin errors=errors+1; $display("  FAIL T"); end

        // R 同时被两个解析器解释: scope=运行/冻结, adc=RANGE
        send_cmd("R", "0", 0, 0, 0);
        $display("  R0    -> run_we=%0d val=%0d (scope), csr_we=%0d addr=0x%02X data=%0d (adc)",
                 n_run, v_run, n_csr, v_addr, v_wdata);
        if (n_run != 1 || v_run !== 1'b0) begin errors=errors+1; $display("  FAIL R(scope)"); end
        if (n_csr != 1 || v_addr !== 8'h20 || v_wdata !== 32'd0)
                                          begin errors=errors+1; $display("  FAIL R(adc 应写 0x20)"); end

        send_cmd("A", "1", 0, 0, 0);
        if (n_ten != 1 || v_ten !== 1'b1) begin errors=errors+1; $display("  FAIL A"); end

        send_cmd("L", "2", "0", "0", 0);
        $display("  L200  -> lvl_we=%0d val=0x%03X", n_lvl, v_lvl);
        if (n_lvl != 1 || v_lvl !== 10'h200) begin errors=errors+1; $display("  FAIL L"); end

        send_cmd("E", "1", 0, 0, 0);
        if (n_edg != 1 || v_edg !== 1'b1) begin errors=errors+1; $display("  FAIL E"); end

        send_cmd("S", "1", 0, 0, 0);
        $display("  S1    -> scr_we=%0d val=%0d (scope), csr_we=%0d addr=0x%02X data=%0d (adc)",
                 n_scr, v_scr, n_csr, v_addr, v_wdata);
        if (n_scr != 1 || v_scr !== 1'b1) begin errors=errors+1; $display("  FAIL S(scope)"); end
        if (n_csr != 2 || v_addr !== 8'h28 || v_wdata !== 32'd1)
                                          begin errors=errors+1; $display("  FAIL S(adc 应写 0x28)"); end

        send_cmd("M", "2", 0, 0, 0);
        if (n_tmode != 1 || v_tmode !== 2'd2) begin errors=errors+1; $display("  FAIL M"); end

        send_cmd("C", "1", 0, 0, 0);
        if (n_tsrc != 1 || v_tsrc !== 1'b1) begin errors=errors+1; $display("  FAIL C"); end

        send_cmd("P", "1", "0", "0", 0);
        if (n_pre != 1 || v_pre !== 10'h100) begin errors=errors+1; $display("  FAIL P"); end

        send_cmd("H", "F", "F", "F", "F");
        $display("  HFFFF -> hold_we=%0d val=0x%04X", n_hold, v_hold);
        if (n_hold != 1 || v_hold !== 16'hFFFF) begin errors=errors+1; $display("  FAIL H"); end

        // ---------- ADC 命令 ----------
        send_cmd("O", "3", 0, 0, 0);
        $display("  O3    -> csr_we=%0d addr=0x%02X data=%0d", n_csr, v_addr, v_wdata);
        if (n_csr != 3 || v_addr !== 8'h24 || v_wdata !== 32'd3)
                                          begin errors=errors+1; $display("  FAIL O"); end

        send_cmd("K", "9", "5", "F", 0);
        $display("  K95F  -> addr=0x%02X data=0x%03X", v_addr, v_wdata);
        if (n_csr != 4 || v_addr !== 8'h08 || v_wdata !== 32'h95F)
                                          begin errors=errors+1; $display("  FAIL K"); end
        if (n_tb != 1) begin errors=errors+1; $display("  FAIL K 不应触发 scope 写"); end

        send_cmd("N", "1", 0, 0, 0);
        if (n_csr != 5 || v_addr !== 8'h04 || v_wdata !== 32'd1)
                                          begin errors=errors+1; $display("  FAIL N"); end

        // ---------- 负向: 未知命令 / 小写 ----------
        send_cmd("Z", "1", "2", 0, 0);
        send_cmd("t", "0", "0", "1", "0");   // 小写 t: 大小写敏感，不应写
        $display("  Z12/t0010(小写) -> 各类写次数不变 (tb=%0d csr=%0d)", n_tb, n_csr);
        if (n_tb != 1 || n_csr != 5) begin errors=errors+1; $display("  FAIL 未知命令产生写"); end

        if (errors == 0) $display("[tb_cmd_chain] PASS");
        else             $display("[tb_cmd_chain] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
