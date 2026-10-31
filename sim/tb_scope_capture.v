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
//   场景 D: normal 模式无触发 -> 1024 采样 tick 超时自动换页（AUTO 模式）
//           - ARMED 连续 AUTO_TIMEOUT 个 tick 没触发就进 FILL
//           - 换页基准 rd_base = 当前写指针（从最老的样本开始显示）
//           - FILL 采满一屏(DEPTH 点)后 done、翻乒乓半区，整屏都是新数据
//   场景 E: single 模式同样能超时换页，但采完仍停在 DONE 等 arm（语义不变）
//   场景 F: auto(0) 模式保持原样（自由滚动、不换页、done 恒 0）
//=============================================================================
module tb_scope_capture;

    localparam integer DEPTH_LOG2 = 4;
    localparam integer DEPTH      = (1 << DEPTH_LOG2);
    localparam integer AUTO_TMO   = 1024;   // 与 scope_capture 的 AUTO_TIMEOUT 默认值一致
    localparam integer TMO_LIMIT  = AUTO_TMO + 64;  // 超时等待上限（留余量）

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

    // 场景 D/E/F（无触发超时换页）观测变量
    integer armed_ticks, fill_ticks, done_before;
    reg [DEPTH_LOG2-1:0] waddr_at_tmo, rd_base_at_tmo, waddr_at_done;
    reg buf_wr_before, buf_disp_before;

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

        // ---------- 场景 D：normal 模式无触发 -> 超时自动换页 ----------
        //   对应现场缺陷：AD/DA 模式下 ch0 是 ADC 数据，输入直流/无信号时
        //   触发永不命中，采集一直卡在 ARMED 往"正在显示的那半"就地写，
        //   屏幕上是"旧波形 + 新波形"叠在一起。
        //   修复后：ARMED 连续 AUTO_TIMEOUT(1024) 个采样 tick 没触发就自动
        //   进 FILL，rd_base 锁到当前写指针（从最老的样本开始显示），采满
        //   一屏后翻乒乓半区 —— 整屏换成新数据，不残留旧波形。
        rst = 1'b1;
        repeat (2) @(posedge clk);
        trig_mode = 2'd1;       // normal
        trig_en   = 1'b0;       // 没有触发源：触发永不命中
        pre_trig  = 10'd5;      // 故意给非 0：超时路径不能用 pre_trig 偏置
        holdoff   = 16'd0;
        roll      = 1'b0;
        trig_cnt  = 0;
        done_cnt  = 0;
        rst = 1'b0;

        @(posedge clk); arm <= 1'b1;
        @(posedge clk); arm <= 1'b0;
        wait (state == 2'd1);              // 进入 ARMED
        buf_wr_before   = buf_wr;
        buf_disp_before = buf_disp;

        // 数"ARMED 里连续多少个采样 tick 没等到触发"（rate_div=0，每拍都是 tick）
        //   #1 是为了在时钟沿的非阻塞赋值生效之后再采样，否则会多数/少数一拍
        armed_ticks = 0;
        while ((state == 2'd1) && (armed_ticks < TMO_LIMIT)) begin
            @(posedge clk);
            #1;
            armed_ticks = armed_ticks + 1;
        end
        waddr_at_tmo   = waddr;
        rd_base_at_tmo = rd_base;

        $display("[tb_scope_capture] 场景 D: normal 无触发超时换页");
        $display("  ARMED 无触发持续 = %0d tick (expect %0d)", armed_ticks, AUTO_TMO);
        $display("  超时瞬间 state=%0d (expect 2=FILL)", state);
        $display("  rd_base=%0d waddr=%0d (expect 相等：基准锁在写指针上)",
                 rd_base_at_tmo, waddr_at_tmo);
        $display("  trig_det=%0d (expect 0：全程没有触发)", trig_cnt);

        if (armed_ticks != AUTO_TMO)   begin errors=errors+1; $display("  FAIL 超时不是 1024 个采样 tick"); end
        if (state != 2'd2)             begin errors=errors+1; $display("  FAIL 超时后没有进入 FILL"); end
        if (rd_base_at_tmo !== waddr_at_tmo)
                                       begin errors=errors+1; $display("  FAIL 超时没有把 rd_base 锁到写指针"); end
        if (trig_cnt != 0)             begin errors=errors+1; $display("  FAIL 无触发用例里出现了触发"); end

        // FILL 必须再采满一屏(DEPTH 点)才 done，并把显示半区翻到刚写的那半
        fill_ticks = 0;
        while ((done_cnt == 0) && (fill_ticks < (DEPTH + 8))) begin
            @(posedge clk);
            fill_ticks = fill_ticks + 1;
        end
        repeat (2) @(posedge clk);
        waddr_at_done = waddr;
        $display("  FILL 到 done 用时 = %0d 拍 (expect %0d 拍左右)", fill_ticks, DEPTH);
        $display("  采满后 state=%0d waddr=%0d (expect 3 / 回到 rd_base=%0d)",
                 state, waddr_at_done, rd_base_at_tmo);
        $display("  buf_disp %0d -> %0d, buf_wr %0d -> %0d (expect 换页)",
                 buf_disp_before, buf_disp, buf_wr_before, buf_wr);

        if (done_cnt != 1)                     begin errors=errors+1; $display("  FAIL 超时后没有完成一次捕获"); end
        if (state != 2'd3)                     begin errors=errors+1; $display("  FAIL 超时捕获没有停在 DONE"); end
        if ((fill_ticks < DEPTH) || (fill_ticks > DEPTH + 2))
                                               begin errors=errors+1; $display("  FAIL 不是采满一屏才换页"); end
        if (waddr_at_done !== rd_base_at_tmo)  begin errors=errors+1; $display("  FAIL 没有把 [rd_base, rd_base+DEPTH) 整屏重写一遍"); end
        if (buf_disp !== buf_wr_before)        begin errors=errors+1; $display("  FAIL 显示半区不是刚采满的那半"); end
        if (buf_wr !== ~buf_wr_before)         begin errors=errors+1; $display("  FAIL 写半区没有翻到另一半"); end

        // ---------- 场景 E：single 模式同样超时换页，但采完仍停在 DONE ----------
        //   语义不变：single 一次 arm 最多采一屏，采完必须等下一次 arm，
        //   超时只是让"没触发"也能把这一屏采完，不会变成连续刷新。
        rst = 1'b1;
        repeat (2) @(posedge clk);
        trig_mode = 2'd2;       // single
        trig_en   = 1'b0;
        pre_trig  = 10'd0;
        trig_cnt  = 0;
        done_cnt  = 0;
        rst = 1'b0;

        @(posedge clk); arm <= 1'b1;
        @(posedge clk); arm <= 1'b0;
        wait (state == 2'd1);

        armed_ticks = 0;
        while ((state == 2'd1) && (armed_ticks < TMO_LIMIT)) begin
            @(posedge clk);
            #1;
            armed_ticks = armed_ticks + 1;
        end
        fill_ticks = 0;
        while ((done_cnt == 0) && (fill_ticks < (DEPTH + 8))) begin
            @(posedge clk);
            #1;
            fill_ticks = fill_ticks + 1;
        end
        repeat (2) @(posedge clk);
        done_before = done_cnt;
        waddr_hold  = waddr;
        buf_wr_hold = buf_wr;

        // 再等 3000 拍：单次模式必须一直停在 DONE，不许自动再采
        repeat (3000) @(posedge clk);

        $display("[tb_scope_capture] 场景 E: single 无触发超时换页 + 停在 DONE");
        $display("  ARMED 无触发持续 = %0d tick (expect %0d)，state=%0d done=%0d",
                 armed_ticks, AUTO_TMO, state, done_before);
        $display("  3000 拍后 state=%0d done 次数=%0d (expect 3 / %0d)",
                 state, done_cnt, done_before);

        if (armed_ticks != AUTO_TMO) begin errors=errors+1; $display("  FAIL single 模式没有超时换页"); end
        if (done_before != 1)        begin errors=errors+1; $display("  FAIL single 模式超时后没有完成捕获"); end
        if (state != 2'd3)           begin errors=errors+1; $display("  FAIL single 模式没有停在 DONE"); end
        if (done_cnt != done_before) begin errors=errors+1; $display("  FAIL single 模式自动重采了（语义被改坏）"); end
        if (waddr !== waddr_hold)    begin errors=errors+1; $display("  FAIL single 停在 DONE 时还在往缓冲里写"); end
        if (buf_wr !== buf_wr_hold)  begin errors=errors+1; $display("  FAIL single 停在 DONE 后仍翻了半区"); end

        // ---------- 场景 F：auto(0) 模式保持原样（自由滚动，不走乒乓换页）----------
        //   trig_mode=0 是"自由滚动 + 只更新对齐基准"，显示端读的是正在写的那半，
        //   本来就没有换页概念；本次改动不能把它改成会翻半区。
        rst = 1'b1;
        repeat (2) @(posedge clk);
        trig_mode = 2'd0;       // auto
        trig_en   = 1'b0;       // 同样没有触发
        trig_cnt  = 0;
        done_cnt  = 0;
        rst = 1'b0;

        @(posedge clk); arm <= 1'b1;
        @(posedge clk); arm <= 1'b0;
        buf_wr_before   = buf_wr;
        buf_disp_before = buf_disp;
        repeat (3000) @(posedge clk);

        $display("[tb_scope_capture] 场景 F: auto(0) 模式不受超时换页影响");
        $display("  %0d 拍后 state=%0d done=%0d buf_wr=%b buf_disp=%b (expect 1/0/不变 %b/%b)",
                 3000, state, done_cnt, buf_wr, buf_disp, buf_wr_before, buf_disp_before);

        if (state != 2'd1)                    begin errors=errors+1; $display("  FAIL auto 模式离开了 ARMED"); end
        if (done_cnt != 0)                    begin errors=errors+1; $display("  FAIL auto 模式不应产生 done"); end
        if (buf_wr !== buf_wr_before)         begin errors=errors+1; $display("  FAIL auto 模式翻了写半区"); end
        if (buf_disp !== buf_disp_before)     begin errors=errors+1; $display("  FAIL auto 模式翻了显示半区"); end

        if (errors == 0) $display("[tb_scope_capture] PASS");
        else             $display("[tb_scope_capture] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
