`timescale 1ns / 1ps
//=============================================================================
// tb_scope_capture.v -- 验证示波器触发状态机（文档标注"未仿真"的部分）
//   为缩短仿真时间，DEPTH_LOG2=4（16 点缓存）。
//   场景 A: trig_mode=1(normal) 上升沿穿越 -> ARMED -> FILL -> DONE
//           trig_det 只出现 1 次；rd_base = 触发写指针 - pre_trig
//   场景 B: trig_mode=0(auto)   触发后仍停在 ARMED，不进入 FILL
//=============================================================================
module tb_scope_capture;

    localparam integer DEPTH_LOG2 = 4;
    localparam integer DEPTH      = (1 << DEPTH_LOG2);

    reg         clk   = 1'b0;
    reg         rst   = 1'b1;
    reg  [9:0]  din   = 10'd0;
    reg  [9:0]  trig_din = 10'd0;
    reg  [15:0] rate_div = 16'd0;      // tick 每拍一次
    reg         sample_valid = 1'b1;
    reg         run   = 1'b1;
    reg         arm   = 1'b0;
    reg         trig_en = 1'b1;
    reg  [1:0]  trig_mode = 2'd1;
    reg  [9:0]  trig_level = 10'd8;
    reg         trig_edge = 1'b0;      // 上升沿
    reg  [9:0]  pre_trig  = 10'd5;
    reg  [15:0] holdoff   = 16'd0;

    wire        we;
    wire [DEPTH_LOG2-1:0] waddr, rd_base;
    wire        trig_det, done;
    wire [1:0]  state;

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) dut (
        .clk(clk), .rst(rst), .din(din), .trig_din(trig_din),
        .rate_div(rate_div), .sample_valid(sample_valid),
        .run(run), .arm(arm), .trig_en(trig_en), .trig_mode(trig_mode),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .we(we), .waddr(waddr), .trig_det(trig_det), .done(done),
        .rd_base(rd_base), .state(state)
    );

    always #5 clk = ~clk;

    // 触发源：0..1023 循环斜坡
    always @(posedge clk) trig_din <= trig_din + 10'd1;
    always @(posedge clk) din      <= trig_din;

    integer errors = 0;
    integer trig_cnt = 0;
    integer done_cnt = 0;
    reg [DEPTH_LOG2-1:0] waddr_at_trig;
    reg [DEPTH_LOG2-1:0] rd_base_seen;
    reg [1:0] state_after_trig;

    // 观测：trig_det 出现的那一拍，waddr 已经 +1，故 waddr-1 即触发写入地址
    always @(posedge clk) begin
        if (trig_det) begin
            trig_cnt       = trig_cnt + 1;
            waddr_at_trig  = waddr - 1'b1;
            rd_base_seen   = rd_base;
            state_after_trig = state;
        end
        if (done) done_cnt = done_cnt + 1;
    end

    initial begin
        $dumpfile("tb_scope_capture.vcd");
        $dumpvars(0, tb_scope_capture);

        // ---------- 场景 A：normal 模式 ----------
        trig_mode = 2'd1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        @(posedge clk); arm <= 1'b1;
        @(posedge clk); arm <= 1'b0;

        // 等待状态机走完一次 normal 捕获（触发 + 填满 16 点）
        wait (state == 2'd3);
        repeat (2) @(posedge clk);     // 让 done 与 rd_base 稳定

        $display("[tb_scope_capture] 场景 A: trig_mode=normal");
        $display("  trig_det 次数 = %0d (expect 1)", trig_cnt);
        $display("  done 次数     = %0d (expect 1)", done_cnt);
        $display("  state         = %0d (expect 3=DONE)", state);
        $display("  触发写地址    = %0d", waddr_at_trig);
        $display("  rd_base       = %0d (expect 触发地址 - pre_trig(%0d) = %0d)",
                 rd_base_seen, pre_trig, (waddr_at_trig - pre_trig[DEPTH_LOG2-1:0]));
        $display("  we(DONE 时)   = %b (expect 0)", we);

        if (trig_cnt != 1)        begin errors=errors+1; $display("  FAIL trig 次数"); end
        if (done_cnt != 1)        begin errors=errors+1; $display("  FAIL done 次数"); end
        if (state != 2'd3)        begin errors=errors+1; $display("  FAIL 未进 DONE"); end
        if (we !== 1'b0)          begin errors=errors+1; $display("  FAIL DONE 仍在写"); end
        if (rd_base_seen !== (waddr_at_trig - pre_trig[DEPTH_LOG2-1:0]))
                                  begin errors=errors+1; $display("  FAIL rd_base 预触发偏移"); end

        // ---------- 场景 B：auto 模式 ----------
        rst = 1'b1;
        repeat (2) @(posedge clk);
        trig_mode = 2'd0;
        pre_trig  = 10'd0;
        trig_cnt  = 0;
        done_cnt  = 0;
        rst = 1'b0;

        @(posedge clk); arm <= 1'b1;
        @(posedge clk); arm <= 1'b0;

        repeat (1500) @(posedge clk);   // 至少跨过一次触发

        $display("[tb_scope_capture] 场景 B: trig_mode=auto");
        $display("  trig_det 次数 = %0d (expect >=1)", trig_cnt);
        $display("  state         = %0d (expect 1=ARMED)", state);
        $display("  done 次数     = %0d (expect 0)", done_cnt);

        if (trig_cnt < 1)   begin errors=errors+1; $display("  FAIL 没触发"); end
        if (state != 2'd1)  begin errors=errors+1; $display("  FAIL auto 模式离开了 ARMED"); end
        if (done_cnt != 0)  begin errors=errors+1; $display("  FAIL auto 模式不应 done"); end

        if (errors == 0) $display("[tb_scope_capture] PASS");
        else             $display("[tb_scope_capture] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
