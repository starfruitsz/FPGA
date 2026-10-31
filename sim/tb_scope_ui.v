`timescale 1ns / 1ps
//=============================================================================
// tb_scope_ui.v -- 按键短按 / 长按首拍 / 长按快速重复
//
// 为了仿真快，CLK_HZ 参数取 50_000（1ms = 50 个时钟）：
//   DB_CNT=1000(20ms)  LONG_CNT=25000(500ms)  FAST_CNT=1500(30ms)
//
// 判据:
//   1) 短按(按住 30ms 松手) -> 只有 1 个 ev_short，没有 ev_long/ev_repeat
//   2) 长按到 500ms        -> 1 个 ev_long（且只发一次）
//   3) 长按之后每 30ms     -> 一个 ev_repeat（脉宽 1 拍），间隔 ≈ FAST_CNT+1 拍
//                             （30ms 快速重复 = 上层"按住连续变化"够丝滑）
//   4) 松开后               -> 不再有 ev_repeat，也不补发 ev_short
//   5) 松开后再次短按       -> 短按识别恢复正常
//=============================================================================
module tb_scope_ui;

    localparam integer CLK_HZ    = 50_000;
    localparam integer DB_MS     = 20;
    localparam integer LONG_MS   = 500;
    localparam integer FAST_MS   = 30;

    localparam integer DB_CNT     = (CLK_HZ/1000)*DB_MS;
    localparam integer LONG_CNT   = (CLK_HZ/1000)*LONG_MS;
    localparam integer FAST_CNT   = (CLK_HZ/1000)*FAST_MS;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  key = 1'b1;

    wire ev_short, ev_long, ev_repeat;

    scope_ui #(
        .CLK_HZ(CLK_HZ), .DB_MS(DB_MS), .LONG_MS(LONG_MS), .FAST_MS(FAST_MS)
    ) dut (
        .clk(clk), .rst(rst), .key_in(key),
        .ev_short(ev_short), .ev_long(ev_long), .ev_repeat(ev_repeat)
    );

    always #5 clk = ~clk;      // 10ns 一个时钟，与 CLK_HZ 参数无关（参数只用于计数换算）

    integer errors = 0;
    integer cyc = 0;
    integer n_short = 0, n_long = 0, n_rep = 0;
    integer t_long = -1;
    integer t_rep [0:15];
    integer interval;
    integer i;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (ev_short) n_short = n_short + 1;
        if (ev_long) begin
            n_long = n_long + 1;
            t_long = cyc;
        end
        if (ev_repeat) begin
            if (n_rep < 16) t_rep[n_rep] = cyc;
            n_rep = n_rep + 1;
        end
    end

    initial begin
        $display("[tb_scope_ui] 去抖 / 短按 / 长按 / 30ms 快速重复");
        $display("  DB=%0d LONG=%0d FAST=%0d 拍", DB_CNT, LONG_CNT, FAST_CNT);
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // ---------- 1) 短按 ----------
        key = 1'b0;
        repeat (1500) @(posedge clk);      // 30ms，超过 20ms 去抖
        key = 1'b1;
        repeat (200) @(posedge clk);
        $display("  1) 短按: ev_short=%0d ev_long=%0d ev_repeat=%0d (expect 1/0/0)",
                 n_short, n_long, n_rep);
        if (n_short != 1) begin errors=errors+1; $display("  FAIL 短按事件个数"); end
        if (n_long  != 0) begin errors=errors+1; $display("  FAIL 短按不该有长按事件"); end
        if (n_rep   != 0) begin errors=errors+1; $display("  FAIL 短按不该有重复事件"); end

        // ---------- 2) 长按：确认 500ms 处只有一个 ev_long ----------
        n_long = 0; t_long = -1;
        key = 1'b0;
        repeat (LONG_CNT + 1500) @(posedge clk);   // 20ms 去抖 + 500ms 长按
        $display("  2) 长按 %0d 拍: ev_long=%0d ev_repeat=%0d (expect 1/0)",
                 LONG_CNT + 1500, n_long, n_rep);
        if (n_long != 1) begin errors=errors+1; $display("  FAIL 长按事件个数"); end
        if (n_rep  != 0) begin errors=errors+1; $display("  FAIL 还没到 30ms 就重复了"); end
        if (n_short != 1) begin errors=errors+1; $display("  FAIL 长按期间不该有短按"); end

        // ---------- 3) 继续按住：每 30ms 一个 ev_repeat ----------
        repeat (3 * FAST_CNT + 400) @(posedge clk);
        $display("  3) 继续按住: ev_repeat=%0d (expect 3) 间隔=%0d/%0d/%0d 拍 (expect %0d)",
                 n_rep, t_rep[0]-t_long, t_rep[1]-t_rep[0], t_rep[2]-t_rep[1], FAST_CNT+1);
        if (n_rep != 3) begin errors=errors+1; $display("  FAIL 快速重复事件个数"); end
        if (n_long != 1) begin errors=errors+1; $display("  FAIL ev_long 发了不止一次"); end
        interval = t_rep[0] - t_long;
        if ((interval < FAST_CNT-2) || (interval > FAST_CNT+3)) begin
            errors=errors+1; $display("  FAIL 长按首拍 -> 第一次重复的间隔"); end
        for (i = 0; i < 2; i = i + 1) begin
            interval = t_rep[i+1] - t_rep[i];
            if ((interval < FAST_CNT-2) || (interval > FAST_CNT+3)) begin
                errors=errors+1; $display("  FAIL 第 %0d 个重复间隔 = %0d", i+1, interval); end
        end

        // ---------- 4) 松开：重复停止，且不补发短按 ----------
        key = 1'b1;
        repeat (200) @(posedge clk);
        if (n_short != 1) begin errors=errors+1; $display("  FAIL 长按松开补发了短按"); end
        repeat (3 * FAST_CNT) @(posedge clk);
        $display("  4) 松开后: ev_repeat 总数=%0d (expect 3)，ev_short=%0d (expect 1)", n_rep, n_short);
        if (n_rep != 3)   begin errors=errors+1; $display("  FAIL 松开后还在重复"); end
        if (n_short != 1) begin errors=errors+1; $display("  FAIL 松开后又出现短按"); end

        // ---------- 5) 再短按一次：识别恢复正常 ----------
        key = 1'b0;
        repeat (1500) @(posedge clk);
        key = 1'b1;
        repeat (200) @(posedge clk);
        $display("  5) 再短按: ev_short=%0d (expect 2)", n_short);
        if (n_short != 2) begin errors=errors+1; $display("  FAIL 重复使用后短按不恢复"); end

        if (errors == 0) $display("[tb_scope_ui] PASS");
        else             $display("[tb_scope_ui] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
