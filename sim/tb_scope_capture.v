`timescale 1ns / 1ps
//=============================================================================
// tb_scope_capture.v -- 验证示波器触发状态机 + 滚动(roll)自由写模式
//   为缩短仿真时间，DEPTH_LOG2=4（16 点缓存）。
//   场景 A: trig_mode=1(normal) 上升沿穿越 -> ARMED -> FILL -> DONE
//           trig_det 只出现 1 次；rd_base = 触发写指针 - pre_trig
//   场景 B: trig_mode=0(auto)   触发后仍停在 ARMED，不进入 FILL
//   场景 C: roll=1 滚动模式（缺陷 1 的采集侧）
//           - 每个采样拍都写(we=1)，写指针自由前进
//           - 触发使能打开也不响应触发，trig_det 恒 0
//           - arm 不复位写指针
//           - 不翻乒乓半区(buf_wr/buf_disp 不变)
//           - roll 拉低后回到乒乓流程：采满一屏(DEPTH 点)才切换显示半区
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
    reg         roll      = 1'b0;      // 1=滚动自由循环写

    wire        we;
    wire [DEPTH_LOG2-1:0] waddr, rd_base;
    wire        trig_det, done;
    wire [1:0]  state;
    wire        buf_wr, buf_disp;

    scope_capture #(.DEPTH_LOG2(DEPTH_LOG2)) dut (
        .clk(clk), .rst(rst), .din(din), .trig_din(trig_din),
        .rate_div(rate_div), .sample_valid(sample_valid),
        .run(run), .arm(arm), .trig_en(trig_en), .trig_mode(trig_mode),
        .trig_level(trig_level), .trig_edge(trig_edge),
        .pre_trig(pre_trig), .holdoff(holdoff),
        .roll(roll),
        .we(we), .waddr(waddr), .trig_det(trig_det), .done(done),
        .rd_base(rd_base), .state(state),
        .buf_wr(buf_wr), .buf_disp(buf_disp)
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

    // 场景 C 观测变量
    integer k, we_cnt, fill_cycles, fill_start;
    reg [DEPTH_LOG2-1:0] waddr_start, waddr_end, waddr_hold;
    reg buf_wr_start, buf_disp_start;
    reg buf_wr_hold;

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

        // ---------- 场景 C：roll 滚动自由写 ----------
        rst = 1'b1;
        repeat (2) @(posedge clk);
        trig_mode = 2'd1;      // 故意用 normal：若 roll 没生效就会触发并进 DONE
        trig_en   = 1'b1;
        pre_trig  = 10'd5;
        roll      = 1'b1;
        trig_cnt  = 0;
        done_cnt  = 0;
        rst = 1'b0;
        repeat (4) @(posedge clk);

        waddr_start    = waddr;
        buf_wr_start   = buf_wr;
        buf_disp_start = buf_disp;
        we_cnt = 0;
        for (k = 0; k < 40; k = k + 1) begin
            @(posedge clk);
            if (we) we_cnt = we_cnt + 1;
        end
        waddr_end = waddr;

        $display("[tb_scope_capture] 场景 C: roll=1 滚动自由写");
        $display("  40 拍内 we 次数      = %0d (expect 40)", we_cnt);
        $display("  写指针 %0d -> %0d (expect 前进 40 取模 %0d)",
                 waddr_start, waddr_end, DEPTH);
        $display("  trig_det=%0d done=%0d (expect 0/0)", trig_cnt, done_cnt);
        $display("  buf_wr=%b buf_disp=%b (expect 不变 %b/%b)",
                 buf_wr, buf_disp, buf_wr_start, buf_disp_start);

        if (we_cnt != 40)                      begin errors=errors+1; $display("  FAIL 滚动模式没有每拍写入"); end
        if (waddr_end !== ((waddr_start + 40) & (DEPTH-1)))
                                               begin errors=errors+1; $display("  FAIL 写指针没有自由前进"); end
        if (trig_cnt != 0)                     begin errors=errors+1; $display("  FAIL 滚动模式仍然响应触发"); end
        if (done_cnt != 0)                     begin errors=errors+1; $display("  FAIL 滚动模式不应 done"); end
        if (buf_wr !== buf_wr_start)           begin errors=errors+1; $display("  FAIL 滚动模式翻了 buf_wr"); end
        if (buf_disp !== buf_disp_start)       begin errors=errors+1; $display("  FAIL 滚动模式翻了 buf_disp"); end
        if (state !== 2'd1)                    begin errors=errors+1; $display("  FAIL 滚动模式状态不是 ARMED"); end

        // arm 必须被忽略：先停掉采样节拍(不写)，再打一个 arm，写指针不能回到 0
        while (waddr == {DEPTH_LOG2{1'b0}}) @(posedge clk);   // 保证初值非 0
        sample_valid = 1'b0;
        repeat (2) @(posedge clk);
        waddr_hold  = waddr;
        buf_wr_hold = buf_wr;
        arm <= 1'b1;
        @(posedge clk);
        arm <= 1'b0;
        repeat (2) @(posedge clk);
        $display("  arm 后写指针        = %0d (expect 不变 %0d)", waddr, waddr_hold);
        if (waddr !== waddr_hold) begin errors=errors+1; $display("  FAIL 滚动模式被 arm 复位了写指针"); end
        if (buf_wr !== buf_wr_hold) begin errors=errors+1; $display("  FAIL 滚动模式 arm 翻了半区"); end
        sample_valid = 1'b1;

        // 退出滚动：回到乒乓流程，必须采满一屏(DEPTH 点)才切换显示半区
        roll = 1'b0;
        repeat (2) @(posedge clk);
        arm <= 1'b1;
        @(posedge clk);
        arm <= 1'b0;
        // 斜坡每 1024 拍才穿一次触发电平，所以等待上限给 2000 拍；
        // 真正要看的是"FILL 阶段至少持续了一整屏(DEPTH)拍"。
        fill_cycles = 0;
        fill_start  = -1;
        while ((state != 2'd3) && (fill_cycles < 2000)) begin
            @(posedge clk);
            fill_cycles = fill_cycles + 1;
            if ((state == 2'd2) && (fill_start < 0)) fill_start = fill_cycles;
        end
        repeat (2) @(posedge clk);

        $display("  退出滚动: state=%0d done=%0d 触发等待=%0d 拍 FILL=%0d 拍 (expect>=%0d)",
                 state, done_cnt, fill_start, fill_cycles - fill_start, DEPTH);
        $display("  退出滚动: buf_disp=%b buf_wr=%b (刚采满的半区=%b)",
                 buf_disp, buf_wr, buf_wr_start);
        if (state !== 2'd3)                  begin errors=errors+1; $display("  FAIL 退出滚动后没有完成一次捕获"); end
        if (done_cnt != 1)                   begin errors=errors+1; $display("  FAIL 退出滚动后 done 次数不对"); end
        if ((fill_start < 0) || ((fill_cycles - fill_start) < DEPTH))
                                             begin errors=errors+1; $display("  FAIL 没有采满一屏就换了半区"); end
        if (buf_disp !== buf_wr_start)       begin errors=errors+1; $display("  FAIL 显示的半区不是刚采满的那半"); end
        if (buf_wr !== ~buf_wr_start)        begin errors=errors+1; $display("  FAIL 写半区没有翻到另一半"); end

        if (errors == 0) $display("[tb_scope_capture] PASS");
        else             $display("[tb_scope_capture] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
