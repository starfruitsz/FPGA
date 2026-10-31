`timescale 1ns / 1ps
//=============================================================================
// tb_trace_layer.v -- 波形图层"边缘假线"回归（缺陷 2）
//
// 现象: 采样值超出绘图区时，旧代码先限幅到 0..PLOT_H-1 再照常连线，
//       于是相邻两点都在屏幕上方(或下方)时，屏幕上/下边缘会出现一条假直线。
// 判据:
//   1) 两端都在上方(或都在下方)  -> 整段一个像素都不许亮
//   2) 一端在外、一端在里(跨边界) -> 只画可见部分，边界像素必须亮
//   3) 一端在上、一端在下(纵贯全屏) -> 0..447 全亮
//   4) 正常段、端点恰好落在边界、px=0 / en=0 / de=0 / px>=H_VIS 等边界
//   5) 补充判据：一端算出 y 恰好等于 0/447、另一端已经越界（整段在屏外）
//      -> 也不许亮（否则每列在边界行点一个像素，连成"贴边假线"）
//      但两端都正好等于 0/447（真实数据落在边界行）时必须照常画
// 另外对每个用例把 480 行全部扫一遍，与参考模型逐像素比对。
//=============================================================================
module tb_trace_layer;

    localparam integer H_VIS  = 640;
    localparam integer PLOT_H = 448;
    localparam [11:0]  COL    = 12'h1F1;

    reg  [11:0] px = 12'd100;
    reg  [11:0] py = 12'd0;
    reg         de = 1'b1;
    reg         en = 1'b1;
    reg  [9:0]  s_now = 10'd512;
    reg  [9:0]  s_prev = 10'd512;
    reg  [2:0]  vshift = 3'd4;
    reg  signed [12:0] voff = 13'sd0;

    wire        hit;
    wire [11:0] color;

    trace_layer #(
        .H_VIS(H_VIS), .PLOT_H(PLOT_H), .SCALE_NUM(7), .SCALE_SHIFT(4), .COL(COL)
    ) dut (
        .px(px), .py(py), .de(de), .en(en),
        .s_now(s_now), .s_prev(s_prev),
        .vshift(vshift), .voff(voff),
        .hit(hit), .color(color)
    );

    integer errors = 0;

    // 参考模型：与 RTL 同一套映射，但用 32bit 有符号整数算，避免位宽陷阱
    function integer y_model;
        input integer s;
        input integer vs;
        input integer vo;
        integer d, z, y;
        begin
            d = s - 512;
            z = (d * 7) >>> vs;
            y = 223 - z + vo;
            if (y < 0)        y = 0;
            if (y > PLOT_H-1) y = PLOT_H-1;
            y_model = y;
        end
    endfunction

    task check_seg;
        input [9:0]  sn;
        input [9:0]  sp;
        input [2:0]  vs;
        input integer vo;
        input [11:0] x;
        input         en_i;
        input         de_i;
        input integer want;        // 1=必须有点亮  0=必须全灭
        integer rn, rp, yn, yp, ylo, yhi, off_t, off_b;
        integer n_hit, kk;
        reg     exp_h;
        begin
            s_now = sn; s_prev = sp; vshift = vs; voff = vo;
            px = x; en = en_i; de = de_i;
            #1;

            // 先补一位 0 再 $signed：10bit 直接 $signed 会把 1023 当成 -1。
            // 这样负半周做的是算术右移，与 RTL 的 >>> 一致。
            rn = 223 - ((($signed({1'b0, sn}) - 512) * 7) >>> vs) + vo;
            rp = 223 - ((($signed({1'b0, sp}) - 512) * 7) >>> vs) + vo;
            yn = y_model(sn, vs, vo);
            yp = y_model(sp, vs, vo);
            ylo = (yn < yp) ? yn : yp;
            yhi = (yn < yp) ? yp : yn;
            // 整段不可见：两端都在同一侧之外；
            //   "恰好在 0/447 边界 + 另一端越界"也算（限幅会把它压到边界行上，
            //   一列一个点就连成贴边假线）；但两端都正好在边界上时是真实数据，保留。
            off_t = (rn <= 0)       && (rp <= 0)       && ((rn < 0)       || (rp < 0));
            off_b = (rn >= PLOT_H-1)&& (rp >= PLOT_H-1)&& ((rn > PLOT_H-1)|| (rp > PLOT_H-1));

            n_hit = 0;
            for (kk = 0; kk < 480; kk = kk + 1) begin
                py = kk; #1;
                exp_h = en_i && de_i && (x != 0) && (x < H_VIS) && (kk < PLOT_H)
                        && (!off_t) && (!off_b) && (kk >= ylo) && (kk <= yhi);
                if (hit !== exp_h) begin
                    if (errors < 10)
                        $display("    不匹配 sn=%0d sp=%0d vs=%0d vo=%0d px=%0d py=%0d hit=%b expect=%b",
                                 sn, sp, vs, vo, x, kk, hit, exp_h);
                    errors = errors + 1;
                end
                if (hit) n_hit = n_hit + 1;
            end

            $display("  sn=%4d sp=%4d vs=%0d vo=%5d px=%3d en=%b de=%b | raw=(%5d,%5d) y=(%0d..%0d) 点亮=%0d",
                     sn, sp, vs, vo, x, en_i, de_i, rn, rp, ylo, yhi, n_hit);
            if ((want != 0) && (n_hit == 0)) begin
                errors = errors + 1; $display("    FAIL 该段应当可见却一个像素都没画");
            end
            if ((want == 0) && (n_hit != 0)) begin
                errors = errors + 1; $display("    FAIL 该段不可见却画了 %0d 个像素（边缘假线）", n_hit);
            end
            if (color !== COL) begin
                errors = errors + 1; $display("    FAIL 颜色输出不对");
            end
        end
    endtask

    initial begin
        $display("[tb_trace_layer] 波形边缘限幅 / 假线回归");

        // 1) 两端都在屏幕上方：vshift=3 时 1023 -> y=-224，旧代码会在 y=0 画一条假线
        check_seg(10'd1023, 10'd1023, 3'd3, 0, 12'd100, 1'b1, 1'b1, 0);
        // 2) 两端都在屏幕下方：vshift=3 时 0 -> y=671，旧代码会在 y=447 画一条假线
        check_seg(10'd0,    10'd0,    3'd3, 0, 12'd100, 1'b1, 1'b1, 0);
        // 3) 上方越界 -> 回到 y=223：只画 0..223，边界行必须亮
        check_seg(10'd512,  10'd1023, 3'd3, 0, 12'd101, 1'b1, 1'b1, 1);
        // 4) 下方越界 -> 回到 y=223：只画 223..447
        check_seg(10'd512,  10'd0,    3'd3, 0, 12'd101, 1'b1, 1'b1, 1);
        // 5) 一端在上、一端在下：纵贯全屏，0..447 都要亮
        check_seg(10'd1023, 10'd0,    3'd3, 0, 12'd102, 1'b1, 1'b1, 1);
        // 6) 普通短段：520/500 -> y=220/229
        check_seg(10'd520,  10'd500,  3'd4, 0, 12'd103, 1'b1, 1'b1, 1);
        // 7) 恰好落在 y=0 的边界（vshift=4 时 1023 -> 0）：这是可见点，必须画
        check_seg(10'd1023, 10'd1023, 3'd4, 0, 12'd104, 1'b1, 1'b1, 1);
        // 8) 恰好落在 y=447 的边界（vshift=4 时 0 -> 447）：必须画
        check_seg(10'd0,    10'd0,    3'd4, 0, 12'd104, 1'b1, 1'b1, 1);
        // 9) 垂直偏移 +96 后两端都还在上方：仍然不许画
        check_seg(10'd1023, 10'd1023, 3'd3, 96, 12'd105, 1'b1, 1'b1, 0);
        // 10) 垂直偏移 -96 后两端都在下方：仍然不许画
        check_seg(10'd0,    10'd0,    3'd3, -96, 12'd105, 1'b1, 1'b1, 0);
        // 11) 垂直偏移把一段推到屏幕上方之外（一端进屏）：画可见部分
        check_seg(10'd700,  10'd1023, 3'd3, 96, 12'd106, 1'b1, 1'b1, 1);
        // 12) px=0 仍然要屏蔽（左边缘竖线）
        check_seg(10'd520,  10'd500,  3'd4, 0, 12'd0,   1'b1, 1'b1, 0);
        // 13) 通道关闭 / 非显示区
        check_seg(10'd520,  10'd500,  3'd4, 0, 12'd100, 1'b0, 1'b1, 0);
        check_seg(10'd520,  10'd500,  3'd4, 0, 12'd100, 1'b1, 1'b0, 0);
        // 14) px 越过可见区（消隐期 px 会数到 640 以上）
        check_seg(10'd520,  10'd500,  3'd4, 0, 12'd640, 1'b1, 1'b1, 0);
        // 15) 边界贴边（上方）：一端算出 y=0、另一端 y=-3 -> 整段在屏外，不许画
        //     （vshift=4、voff=-3 时：1016 -> 0，1023 -> -3）
        check_seg(10'd1016, 10'd1023, 3'd4, -3, 12'd107, 1'b1, 1'b1, 0);
        // 16) 两端都正好在 y=0：真实数据落在边界行上，必须画（只点亮第 0 行）
        check_seg(10'd1016, 10'd1016, 3'd4, -3, 12'd107, 1'b1, 1'b1, 1);
        // 17) 边界贴边（下方）：一端 y=447、另一端 y=450 -> 整段在屏外，不许画
        check_seg(10'd8,    10'd0,    3'd4,  3, 12'd108, 1'b1, 1'b1, 0);
        // 18) 两端都正好在 y=447：真实数据落在边界行上，必须画
        check_seg(10'd8,    10'd8,    3'd4,  3, 12'd108, 1'b1, 1'b1, 1);
        // 19) 一端正好在边界、另一端在屏内 -> 可见段照常画（226..447）
        check_seg(10'd8,    10'd512,  3'd4,  3, 12'd109, 1'b1, 1'b1, 1);

        if (errors == 0) $display("[tb_trace_layer] PASS");
        else             $display("[tb_trace_layer] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
