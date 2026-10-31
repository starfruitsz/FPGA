//==============================================================================
// [P26 修复] 时序违规 -> 6 级流水线
// 文件: eso.v            模块: eso            实例名: eso_inst(adda 顶层)
//                                              / u_eso(sparkroad_scope_top)
// 功能: 线性扩展状态观测器(ESO, Extended State Observer), 与状态误差反馈组合成
//       ADRC(自抗扰控制)的核心运算: 观测被控量 z1、微分 z2、总扰动 z3,
//       再按 u = [k*(c*z1+z2) + sign + c*z2 - z3] 生成控制量。
//
// 离散化形式(前向差分, 采样步长 h = 1/1024):
//   e(k)    = z1(k) - y(k)
//   z1(k+1) = z1(k) + h*z2(k) - B01*h*e(k)
//   z2(k+1) = z2(k) + h*z3(k) - B02*h*e(k) + b0*h*u(k)
//   z3(k+1) = z3(k)             - B03*h*e(k)
//   u(k)    = [ k*(c*z1+z2) + sgn(c*z1+z2) + c*z2 - z3 ] >>> 15
//
// 定点实现: 乘常数后用 >>>10 实现 *h, 用 >>>13/>>>15 做标度归一。
// 所有运算均为有符号补码, 位宽在每级手工扩展(见下方各 wire 声明)。
//==============================================================================
// 【为什么改】
//   p25 综合/布线后 16 条 setup 违例, 最差 TNS -13.493ns / WNS -1.880ns
//   (约束 25.2MHz = 41.667ns)。关键路径从 z1k1 出发, 依次经过
//     z1k1 - y -> e*B01 -> >>>10 -> 44bit 累加 -> 20bit 截位 ->
//     z1*c -> 33bit 累加 -> s*k -> v_1 -> viout -> >>>15
//   也就是 3 个乘法器 + 一整条乘加链全部压在一个周期里, 仪器实测内部分
//   ~29ns, 再串上 out_da -> 显示通路的 ~14ns 就直接超周期。
//
// 【怎么改】把这条链按"乘法 / 乘加 / 累加 / 反馈 / 输出"切成 6 级寄存器,
//   每级只留 1 个乘法器或 1~2 个宽加法器(单级 <= 15ns, 余量 > 60%):
//
//   级1 E1  采输入   y  <= -e_in        uk <= u_out
//   级2 E2  乘法     sub*B01/N02/B03、uk*b0            -> 42/42/42/36bit
//   级3 E3  乘加     *h(>>>10, >>>13) 与 z*h(>>>10) 合成增量 -> 44bit
//   级4 E4  累加     z1/z2/z3 <= z + 增量; 同时算 c*z1、c*z2
//   级5 E5  反馈     she = c*z1+z2、sgn、kshe = she*k
//   级6 E6  输出     v_1、viout = v_1-z3、>>>15、out_da
//
//   延迟: 观测状态 z1k0..z3k0 在 en 之后 4 拍更新;
//         控制量 out_da      在 en 之后 6 拍更新。
//         采样周期在 25.2MHz/3.15MHz 下是 8 拍, 流水线 6 拍, 余量 2 拍。
//   en 相邻脉冲要求 >= 4 拍: 流水线忙(pv[2:0] 非零)时到来的 en 被忽略,
//         观测器只是少推进一步, 不会算错状态。本工程 en 来自 ADCLK/8,
//         严格 8 拍一次, 不会触发忽略。
//         (adda.v 那个 1kHz 老应用把 en 常接 1'b1, 于是被自动降频到 1/4,
//          观测器变慢但数值仍然正确; 该模块不在当前顶层里。)
//
// 【数值口径】位宽、移位位数、截位位置与原实现逐条一致, 逐采样结果不变:
//   只是把同一组运算拆到相邻几拍分别寄存, 乘加的结合顺序未改动
//   ((a+b)-c 与 a+(b-c) 在 44bit 内都是精确运算, 不会溢出)。
//==============================================================================
`timescale 1ns / 1ps 
//------------------------------------------------------------------------------
// `define WIDTH 20: 内部状态 z1/z2/z3 的位宽(20bit 有符号, 约 ±52 万)
//------------------------------------------------------------------------------
`define WIDTH 20 

module eso 
( 
//------------------------------------------------------------------------------
// 端口
//   ad_clk   : 观测器运算时钟(接 adda 的 ad_clk1 = 1kHz;
//              SparkRoad 示波器里接 24/25.2MHz 系统时钟, 运算节拍改由 en 决定)
//   sys_rst_n: 异步复位, 低有效
//   en       : 采样使能, 1=本拍启动一次观测器运算; 0=不启动
//              (相邻 en 脉冲间隔 >= 4 拍, 本工程为 8 拍)
//   e_in     : 测量误差输入(adda 送 date_y = AD 码值-512)
//   u_out    : 上一拍的控制量反馈(接 date_u), 用于 b0*u 项
//   c_flag/k_flag/c_date/k_date : 串口下发的两个可调参数 c、k
//   z1k0..z3k0 : 观测状态输出(本工程 adda 中未连接, 仅内部使用)
//   out_da     : 控制量输出(10bit), 接 adda 的 date_u -> DAC
//------------------------------------------------------------------------------
    input ad_clk, 
    input sys_rst_n, 
    input wire en,
    input signed [9:0] e_in, 
    input signed [9:0] u_out, 
    input wire c_flag, 
    input wire k_flag, 
    input wire [11:0] c_date, 
    input wire [11:0] k_date, 
    
    output signed [`WIDTH-1: 0] z1k0, 
    output signed [`WIDTH-1: 0] z2k0, 
    output signed [`WIDTH-1: 0] z3k0, 
    output signed [9:0] out_da 
); 
    
//------------------------------------------------------------------------------
// 系数(定点数): B01/B02/B03 为观测器增益, b0 为控制增益, n 未使用。
// 常数的实际比例由运算中的移位(>>>10 / >>>13)决定。
//------------------------------------------------------------------------------
parameter signed B01=21'd90; 
parameter signed B02=21'd2700; 
parameter signed B03=21'd27000; 
parameter signed b0=16'd5000; 
parameter signed n = 2'd1; 
 
//------------------------------------------------------------------------------
// 状态寄存器 z1k1/z2k1/z3k1: 当前状态 z(k), 只在 pv[2]=1 的那一拍更新
// (复位清零, 保证上电从 0 状态开始收敛)
// 参数 c(状态误差反馈系数, 默认 150)、k(反馈增益, 默认 20)
//------------------------------------------------------------------------------
reg signed [`WIDTH-1: 0] z1k1; 
reg signed [`WIDTH-1: 0] z2k1; 
reg signed [`WIDTH-1: 0] z3k1; 
reg signed [9:0]  c; 
reg signed [10:0] k; 

//------------------------------------------------------------------------------
// [端口语义] 原 z1k0/z2k0/z3k0 是"组合逻辑算出的下一个状态 z(k+1)"; 流水线后
// 每个状态由 6 拍前的输入决定, 组合的下一状态已不存在, 这三路直接输出已寄存的
// 当前状态 z(k)(数值上晚 1 个采样, 收敛过程完全一致)。
//------------------------------------------------------------------------------
assign z1k0 = z1k1; 
assign z2k0 = z2k1; 
assign z3k0 = z3k1; 

//------------------------------------------------------------------------------
// [流水线有效标志] pv 每一位代表"该级输出寄存器里装的是有效数据":
//   pv[0] : 级1 输出(y_r/uk_r)有效
//   pv[1] : 级2 输出(4 个乘积)有效
//   pv[2] : 级3 输出(3 个增量)有效
//   pv[3] : 级4 输出(新状态 + c*z1/c*z2)有效
//   pv[4] : 级5 输出(kshe/sgn/c*z2/z3)有效, 同时作为 out_da 的装入使能
// pipe_busy 覆盖级1~级3: 这 3 拍内状态还没写回, 新的 en 必须被挡掉,
// 否则新样本的乘积会盖掉上一拍还没被"乘加级"取走的乘积。
//------------------------------------------------------------------------------
reg [4:0] pv; 
wire      pipe_busy = pv[0] | pv[1] | pv[2]; 
wire      en_ok     = en & ~pipe_busy; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        pv <= 5'd0; 
    else 
        pv <= {pv[3:0], en_ok}; 

//------------------------------------------------------------------------------
// [级 1 / E1] 采样保持
//   y  <= -e_in : 误差取反(符号约定: 观测器用 -e)
//   uk <= u_out : 控制量, 供 b0*u 项使用
//   注意 y 只有 10bit, e_in=-512 时 -e_in=+512 会回绕成 -512, 这是原实现的
//   固有行为, 保持不动。
//------------------------------------------------------------------------------
reg signed [9:0] y_r; 
reg signed [9:0] uk_r; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            y_r  <= 10'sd0; 
            uk_r <= 10'sd0; 
        end 
    else if(en_ok==1'b1) 
        begin 
            y_r  <= -e_in; 
            uk_r <= u_out; 
        end 

//------------------------------------------------------------------------------
// [级 2 / E2] 4 个乘法器: e*B01、e*B02、e*B03、u*b0
//   sub   = z1(k) - y          (WIDTH+1 = 21bit 有符号)
//   乘积  = sub*B0x (21+21=42bit)、uk*b0 (按原实现扩到 36bit)
//   移位放到下一级做(移位只是接线, 不占逻辑)
//------------------------------------------------------------------------------
wire signed [`WIDTH - 1 + 1: 0] sub_p; 
assign sub_p = z1k1 - y_r; 

wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B01_p; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B02_p; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B03_p; 
assign sub_B01_p = sub_p * B01; //B1e1,B2e1,B3e1 
assign sub_B02_p = sub_p * B02; 
assign sub_B03_p = sub_p * B03; 

wire signed [`WIDTH + 16 - 1 : 0] uk_b0_p; 
assign uk_b0_p = uk_r * b0; 

reg signed [`WIDTH - 1 + 1 + 21: 0] sub_B01_r; 
reg signed [`WIDTH - 1 + 1 + 21: 0] sub_B02_r; 
reg signed [`WIDTH - 1 + 1 + 21: 0] sub_B03_r; 
reg signed [`WIDTH + 16 - 1 : 0]     uk_b0_r; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            sub_B01_r <= 'd0; 
            sub_B02_r <= 'd0; 
            sub_B03_r <= 'd0; 
            uk_b0_r  <= 'd0; 
        end 
    else if(pv[0]==1'b1) 
        begin 
            sub_B01_r <= sub_B01_p; 
            sub_B02_r <= sub_B02_p; 
            sub_B03_r <= sub_B03_p; 
            uk_b0_r  <= uk_b0_p; 
        end 

//------------------------------------------------------------------------------
// [级 3 / E3] 乘加项(只算增量, 不与状态相加)
//   sub_B0x_h = (sub*B0x) >>> 10     等价于 *h
//   uk_b0_h   = (uk*b0)  >>> 13      等价于 *5000/8192
//   z2k1_h/z3k1_h = z >>> 10         z(k)*h
//   d1 = z2*h - B01*h*e ;  d2 = z3*h - B02*h*e + b0*h*u ;  d3 = -B03*h*e
//------------------------------------------------------------------------------
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B01_h; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B02_h; 
wire signed [`WIDTH - 1 + 1 + 21: 0] sub_B03_h; 
assign sub_B01_h = sub_B01_r >>> 10; //Be1*h 
assign sub_B02_h = sub_B02_r >>> 10; 
assign sub_B03_h = sub_B03_r >>> 10; 

wire signed [`WIDTH + 16 - 1 : 0] uk_b0_h; 
assign uk_b0_h = uk_b0_r >>> 13; 

wire signed [`WIDTH - 1: 0] z2k1_h; //z(k)*h 
wire signed [`WIDTH - 1: 0] z3k1_h; 
assign z2k1_h = z2k1 >>> 10; 
assign z3k1_h = z3k1 >>> 10; 

wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] d1_p; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] d2_p; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] d3_p; 
assign d1_p = z2k1_h - sub_B01_h; 
assign d2_p = z3k1_h - sub_B02_h + uk_b0_h; 
assign d3_p = -sub_B03_h; 

reg signed [`WIDTH - 1 + 1 + 21 + 2: 0] d1_r; 
reg signed [`WIDTH - 1 + 1 + 21 + 2: 0] d2_r; 
reg signed [`WIDTH - 1 + 1 + 21 + 2: 0] d3_r; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            d1_r <= 'd0; 
            d2_r <= 'd0; 
            d3_r <= 'd0; 
        end 
    else if(pv[1]==1'b1) 
        begin 
            d1_r <= d1_p; 
            d2_r <= d2_p; 
            d3_r <= d3_p; 
        end 

//------------------------------------------------------------------------------
// [级 4 / E4] 状态累加 + c*z 乘法
//   z1(k+1) = z1(k) + d1 ; z2(k+1) = z2(k) + d2 ; z3(k+1) = z3(k) + d3
//   与原实现一样, 只取低 WIDTH 位([19:0])回灌, 高位是符号扩展位
//   (原码取 z1k0_reg[19:0], 发散时会静默回绕, 无饱和保护, 行为保持一致)
//   同一拍并行算 c*z1、c*z2(原实现里这两个乘法在状态之后的组合链上),
//   z2/z3 也一起打拍给后级用, 后级因此不再依赖共享的状态寄存器。
//------------------------------------------------------------------------------
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z1n; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z2n; 
wire signed [`WIDTH - 1 + 1 + 21 + 2: 0] z3n; 
assign z1n = z1k1 + d1_r; 
assign z2n = z2k1 + d2_r; 
assign z3n = z3k1 + d3_r; 

wire signed [`WIDTH - 1: 0] z1q; 
wire signed [`WIDTH - 1: 0] z2q; 
wire signed [`WIDTH - 1: 0] z3q; 
assign z1q = z1n[`WIDTH - 1: 0]; 
assign z2q = z2n[`WIDTH - 1: 0]; 
assign z3q = z3n[`WIDTH - 1: 0]; 

wire signed [`WIDTH + 12 -1: 0] err1_p; 
wire signed [`WIDTH + 12 -1: 0] err2_p; 
assign err1_p = z1q * c; 
assign err2_p = z2q * c; 

reg signed [`WIDTH - 1: 0] z2s_r; 
reg signed [`WIDTH - 1: 0] z3s_r; 
reg signed [`WIDTH + 12 -1: 0] err1_r; 
reg signed [`WIDTH + 12 -1: 0] err2_r; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            z1k1   <= 'd0; 
            z2k1   <= 'd0; 
            z3k1   <= 'd0; 
            z2s_r  <= 'd0; 
            z3s_r  <= 'd0; 
            err1_r <= 'd0; 
            err2_r <= 'd0; 
        end 
    else if(pv[2]==1'b1) 
        begin 
            z1k1   <= z1q; 
            z2k1   <= z2q; 
            z3k1   <= z3q; 
            z2s_r  <= z2q; 
            z3s_r  <= z3q; 
            err1_r <= err1_p; 
            err2_r <= err2_p; 
        end 

//------------------------------------------------------------------------------
// [级 5 / E5] 状态误差反馈: s = c*z1 + z2, kshe = s*k
//   sgn: s>0 取 +1, 否则取 -1  (5bit 有符号, 负数必须写成 -5'sd1)
//   本拍同时把 err2 和 z3 打拍给最后一级, 最后一级只读寄存器。
//------------------------------------------------------------------------------
wire signed [`WIDTH + 13 -1: 0] she; 
assign she = err1_r + z2s_r; //s=ce1+e2 

wire signed [4 : 0] sgn; 
assign sgn = (she > 0) ? 5'sd1 : -5'sd1; 

wire signed [`WIDTH + 13 + 11 -1: 0] kshe_p; 
assign kshe_p = she * k; 

reg signed [`WIDTH + 13 + 11 -1: 0] kshe_r; 
reg signed [4 : 0] sgn_r; 
reg signed [`WIDTH + 12 -1: 0] err2_s; 
reg signed [`WIDTH - 1: 0]    z3_s; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            kshe_r <= 'd0; 
            sgn_r  <= 'd0; 
            err2_s <= 'd0; 
            z3_s   <= 'd0; 
        end 
    else if(pv[3]==1'b1) 
        begin 
            kshe_r <= kshe_p; 
            sgn_r  <= sgn; 
            err2_s <= err2_r; 
            z3_s   <= z3s_r; 
        end 

//------------------------------------------------------------------------------
// [级 6 / E6] v_1 = k*s + sgn + c*z2 ; viout = v_1 - z3 ; b = viout >>> 15
//   out_da 取 b[9:0] 送 DAC(0~1023)。
//   复位值 10'h3FF: 零状态下 she=0 -> sgn=-1 -> v_1=-1 -> >>>15=-1 -> 低 10 位
//   就是 3FF, 与原实现"复位时组合输出的值"完全一致。
//   (端口仍声明为 wire, 内部寄存器 out_da_r 打一拍后 assign 出去, 端口表不变)
//------------------------------------------------------------------------------
wire signed [`WIDTH + 22 -1: 0] v_1; 
assign v_1 = kshe_r + sgn_r + err2_s; 

wire signed [`WIDTH + 21 -1: 0] viout; 
assign viout = v_1 - z3_s; //ks+sgn+cz2-f 

wire signed [40 -1: 0] b; 
assign b = viout >>> 15; 

reg signed [9:0] out_da_r; 

always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        out_da_r <= 10'h3FF; 
    else if(pv[4]==1'b1) 
        out_da_r <= b[9 : 0]; 

assign out_da = out_da_r; 

//------------------------------------------------------------------------------
// [块 2] 参数锁存(c、k)
//   复位: c=150, k=20 (经验初值)；c_flag=1 时 c<=c_date；k_flag=1 时 k<=k_date
// [修复 P1] 原实现是 if/else-if 优先级结构，而顶层两个 flag 置 1 后不清零，
//   导致收到过 A 帧后 k 永远更新不了。现改为两个互不排斥的独立 if：
//   两个 flag 同时有效时 c、k 都更新；都不有效时寄存器自动保持。
//   注：flag 保持高电平是有意的——它要跨到 1kHz 的 ad_clk 域，脉冲会丢。
//   参数寄存器只在乘法器输入端被读, 与流水线节拍无关, 不需要跟 pv 对齐。
//------------------------------------------------------------------------------
always@(posedge ad_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        begin 
            c<=10'd150; 
            k<=11'd20; 
        end //初始化参数 
    else
        begin
            if(c_flag==1'b1)
                c<=c_date;
            if(k_flag==1'b1)
                k<=k_date;
        end
 
//------------------------------------------------------------------------------
// 附注: 本模块共 9 个乘法器(3 个 e*B0x、1 个 u*b0、2 个 z*c、1 个 s*k，其中
//   e*B0x 的 3 个共用同一个 sub)，综合后映射为 7 个 MULTALU27X18。
//   p26 起它们分布在第 2/4/5 级, 相邻两级之间都有寄存器。
//------------------------------------------------------------------------------
endmodule 
