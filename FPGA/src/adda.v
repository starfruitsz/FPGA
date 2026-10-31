//==============================================================================
// 文件: adda.v            模块: adda            工程: project_2025_11_07
// 功能: AD/DA 采集与 ADRC(自抗扰控制)演示的顶层模块(Top Module)。
// 时钟: sys_clk = 50MHz(系统时钟), sys_rst_n = 低电平有效异步复位。
//
// 模块层级(TD/Gowin 综合后实际编译到的 7 个子模块):
//   adda
//    +-- key_inst      : key      按键消抖(20ms), 切换 ad_out 输出内容
//    +-- seg_inst      : seg      数码管 6 位动态扫描, 显示 AD 原始码值
//    |    +-- bcd_8421 : bcd      二进制 -> 3 位 BCD(移位加 3 法)
//    +-- adc_inst      : rtl      AD 中值滤波 + 正/负向电压分辨率换算
//    +-- eso_inst      : eso      扩展状态观测器(ESO), 由误差产生控制量
//    +-- uart_rx_inst  : uart_rx  串口接收 16bit 指令帧(Axxx/Bxxx)
//    +-- uart_tx_inst  : uart_tx  串口发送 16bit AD 码值(两帧 8N1)
//    +-- divider_inst  : divider  分频, 产生 1kHz 的 AD/DA 转换时钟
//
// 另有 Gowin_PLL、fifo_top 两个 IP 文件被加入工程, 但在本模块中被注释掉,
// 未参与综合(综合报告 PLL 0/6、BSRAM 0% 可佐证), 详见文件末尾。
//==============================================================================
module adda 
#( 
//------------------------------------------------------------------------------
// 参数区:
//   CNT_DATA_MAX : rtl 中值累加样本数(1024 次), 本模块仅作占位, 未使用
//   UART_MODE    : [P5 开关] 0 = 连续发送(pi_flag 恒 1)
//                            1 = 按定时标志位发送(默认)
//   CLK_FREQ     : 系统时钟频率, 用于把 REPORT_MS 换算成计数值
//   REPORT_MS    : [P5 可配置] 标志位模式下的上报周期(毫秒)
//   CNT_MAX      : 由 REPORT_MS 推导: 50MHz 下 26ms -> 1,299,999
//                  例: 10ms -> 499,999; 100ms -> 4,999,999
//                  计数器已加宽到 32bit, 支持更长周期
//------------------------------------------------------------------------------
    parameter CNT_DATA_MAX = 11'd1024, 
    parameter integer UART_MODE = 0,          // 默认连续发送 0=连续 1=标志位
    parameter integer CLK_FREQ  = 50_000_000, 
    parameter integer REPORT_MS = 26,         // 上报周期(ms)
    parameter integer CNT_MAX   = (CLK_FREQ/1000)*REPORT_MS - 1
) 

(
//------------------------------------------------------------------------------
// 端口区
//   时钟/复位 : sys_clk(50MHz)、sys_rst_n(低有效)
//   AD 数据   : ad_date[9:0]  外部 ADC 并行输出, 无符号 0~1023
//   按键      : key_in        接板载按键, 1=松开, 0=按下
//   AD/DA 外部时钟: ad_clk、da_clk 为输入端口(本设计未使用, 综合会裁剪, 端口保留)
//------------------------------------------------------------------------------
    input wire sys_clk, 
    input wire sys_rst_n, 
    input wire [9:0] ad_date, 
    input wire key_in, 
    input ad_clk, 
    input da_clk, 
    input wire rx, 
    
//   输出时钟  : ad_clk1/da_clk1  由 divider 分频产生, 送给 AD/DA 芯片做转换时钟
//   DA 数据   : ad_out[9:0]     送 DAC 的偏移二进制码
//   数码管    : sel[3:0] 位选(低有效), seg[7:0] 段选(含小数点位)
//   串口      : tx 发送, rx 接收
//   LED       : led0 按键状态; led6/led7 分别指示 B 帧/A 帧参数接收
//------------------------------------------------------------------------------
    output wire ad_clk1, 
    output wire da_clk1, 
    output reg [9:0] ad_out, 
    output wire[3:0] sel, 
    output wire[7:0] seg, 
    output wire tx, 
    output reg led0, 
    output reg led6, 
    output reg led7 
); 
    
//------------------------------------------------------------------------------
// 内部信号声明
//   key_out     : 消抖后的按键电平(1=未按, 0=按下)
//   volt        : rtl 计算出的电压值, 本模块未使用
//   sign        : rtl 输出的符号位(1=低于中值), 送数码管显示负号
//   date_y      : ad_date-512 的有符号值, 把 ADC 中点 512 移到零点
//   date_u      : ESO 输出的有符号控制量, 同时作为 ESO 的 u_out 反馈输入
//   po_data/po_flag : 串口接收字节与单周期有效脉冲
//   seg_date    : 预留, 未使用
//   ad_pingj0/1 : 把 ad_date 拆成低 8bit + 高 2bit, 供 16bit 串口帧填写
//   po_flag2    : 16bit 组帧的奇偶标志(0=待收高字节, 1=待收低字节)
//   po_flag3    : 16bit 完整接收的单周期脉冲
//   c_date/k_date : 串口下发的 12bit 参数(Axxx=c, Bxxx=k)
//   c_flag/k_flag : 参数接收标志, 置 1 后**不再清零**(见下方附注)
//------------------------------------------------------------------------------
wire key_out; 
wire [9:0] volt; 
wire sign; 
reg signed [9:0] date_y; 
wire signed [9:0] date_u; 
wire [7:0] po_data; 
wire po_flag; 
reg [7:0] seg_date; 
wire [7:0] ad_pingj0; 
wire [7:0] ad_pingj1; 
reg po_flag2; 
reg po_flag3; //16位信号完整接收标志位 

reg pi_flag; 
reg [31:0] cnt;          // [P5] 加宽到 32bit，支持更长上报周期
reg [15:0] rx_date; 

reg [11:0] c_date; 
reg [11:0] k_date; 
reg c_flag; 
reg k_flag; 

//------------------------------------------------------------------------------
// 上电初值: po_flag2 用 initial 赋初值(TD/Gowin 支持 FF 上电初值),
// 保证第一帧数据先写入高 8bit。综合后该寄存器带 INIT=0 属性。
// [修复 P10] 原来用 initial 给 po_flag2 赋初值，可综合性依赖器件特性；
// 现已移到块 5 的复位分支里(po_flag2<=1'b0)，不再使用 initial。
//------------------------------------------------------------------------------
// 拆包: ad_date[7:0] -> ad_pingj0, ad_date[9:8] -> ad_pingj1(高位补 0)。
// 串口帧格式 = {高 8bit(有效 2bit), 低 8bit}, 见 uart_tx 例化处的拼接。
//------------------------------------------------------------------------------
assign ad_pingj0={ad_date[7:0]}; 
assign ad_pingj1={6'b000000,ad_date[9:8]}; 
//assign ad_pingj2={8'b1010_1010}; 
 
//------------------------------------------------------------------------------
// [块 1] ADC 码值去偏置: 0~1023 的二进制偏移码 -> -512~+511 的补码(有符号)。
// 10bit 减法自然回绕实现符号扩展, date_y 为 signed 声明。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        date_y<=10'd0; 
    else 
        date_y<=ad_date-10'd512; //0-1024 变 -512-512 
 
//------------------------------------------------------------------------------
// [块 2] DA 输出数据选择 + 工作指示灯
//   key_out=0(按键按下) : 输出 ~ad_date, 即把 ADC 原始码取反回环到 DAC
//   key_out=1(松开)     : 输出 ~date_u+512, 即 ESO 控制量整形成偏移二进制码
// 注意: ~x+512 在 10bit 无符号运算下等价于 511-x, 即对 ESO 输出做了反相,
//       其方向构成 DAC->ADC 环路的负反馈, 方向正确性需结合被控对象确认。
// led0 与 ad_out 同步赋值, 高电平表示处于'直通显示'状态。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n==1'b0) 
        ad_out<=10'd0; 
    else if(key_out==1'b0) 
        begin 
            ad_out<=~ad_date; //按下输出 ad 读数 
            led0<=1'b1; 
        end 
    else 
        begin 
            ad_out<=~date_u+10'd512; //按下输出控制量，0 灯亮 
            led0<=1'b0; 
        end 
 
//------------------------------------------------------------------------------
// (以下为已废弃的 seg_date 计算代码, 保留作历史记录, 不参与综合)
//------------------------------------------------------------------------------
//always@(posedge sys_clk or negedge sys_rst_n) 
// if(sys_rst_n==1'b0) 
// seg_date<=8'd0; 
// else 
// seg_date<=po_data/256*100+po_data%256/16*10+po_data%16; 
// //八位最大 255，因转换 10 进制最大 99 
 
//------------------------------------------------------------------------------
// [块 3] 上报定时计数器: 0 ~ CNT_MAX 循环，CNT_MAX 由 REPORT_MS 推导。
// [修复 P5] 该计数器为块 4 提供定时标志；UART_MODE=0 时会被综合优化掉。
//   默认 REPORT_MS=26 → 约 38 帧/秒；改参数即可调上报速率。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        cnt <= 32'd0; 
    else if(cnt == CNT_MAX) 
        cnt <= 32'd0; 
    else 
        cnt <= cnt + 1'b1; 
 
//------------------------------------------------------------------------------
// [块 4] 上报脉冲: 计数到 CNT_MAX-1 时产生单周期 pi_flag，送块 4b 的 tx_req。
//   UART_MODE=1 时每 REPORT_MS 触发一帧；UART_MODE=0 时该脉冲不使用。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        pi_flag <= 1'b0; 
    else if(cnt == CNT_MAX-1'b0) //tx 发送过快后分配 
        pi_flag <= 1'b1; 
    else 
        pi_flag <= 1'b0; 
 
//------------------------------------------------------------------------------
// [块 4b] 发送请求选择（P5 开关）
//   UART_MODE=0: 连续发送，pi_flag 恒为 1（原来的行为）
//   UART_MODE=1: 每 REPORT_MS 毫秒发一帧（由块 3/4 定时，默认 26ms）
//   UART_MODE 是常数参数，综合时未被选中的一路会被常量折叠。
//------------------------------------------------------------------------------
wire tx_req = (UART_MODE != 0) ? pi_flag : 1'b1;

//------------------------------------------------------------------------------
// [块 5] 16bit 串口指令组帧
//   po_flag 是 uart_rx 收到 1 个字节的脉冲; 用 po_flag2 区分奇偶次:
//   第 1 次: rx_date[15:8] <= po_data(高字节), po_flag2<=1
//   第 2 次: rx_date[7:0]  <= po_data(低字节), po_flag2<=0
// 因此上位机必须按 {高字节, 低字节} 顺序连续发 2 字节, 中间不能丢字节。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        begin 
            rx_date<=16'd0; 
            po_flag2<=1'b0;   // [修复 P10] 复位时清组帧标志（原靠 initial）
        end 
    else if((po_flag == 1'b1)&&(po_flag2==1'b0)) 
        begin 
            rx_date<={po_data,8'd0}; //先赋高八位 
            po_flag2<=1'b1; 
        end 
    else if((po_flag == 1'b1)&&(po_flag2==1'b1)) 
        begin 
            rx_date<={rx_date[15:8],po_data}; //再赋低八位拼接十六位 
            po_flag2<=1'b0; 
        end 
    else 
        begin 
            rx_date<=rx_date; 
            po_flag2<=po_flag2; 
        end 
 
//------------------------------------------------------------------------------
// [块 6] 组帧完成标志: 第 2 个字节到达的同一拍置 1, 仅保持 1 个周期,
// 作为块 7/块 8 解析 16bit 内容的使能。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        po_flag3 <= 1'b0; 
    else if((po_flag==1'b1)&&(po_flag2==1'b1)) 
        po_flag3 <= 1'b1; 
    else 
        po_flag3 <= 1'b0; //16 位拼接标志 
 
//------------------------------------------------------------------------------
// [块 7] 解析 'Bxxx' 帧(高 4bit=4'hB): 后 12bit 为 ESO 的 k 参数
//   led6 每收到一帧 B 参数翻转一次, 作为接收指示;
//   k_flag 置 1 后**没有清零分支**, k_date 亦无复位, 属'锁存式'标志;
//   该标志在 eso.v 中与 c_flag 构成优先级(见 eso.v 块 3 的说明)。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        led6<=1'b1; 
    else if((rx_date[15:12]==4'HB)&&(po_flag3==1'B1)) //前四位为参数标志位，后12位为数据位
        begin 
            led6<=~led6; //K 接收标志位有效后 led6 跳变 
            k_flag<=1'b1; 
            k_date<=rx_date[11:0]; //Bxxx，xxx 为 adrc 的 k 
        end 
    else 
        begin 
            led6<=led6; 
            //k_flag<=1'b0; 
            k_date<=k_date; 
        end 
 
//------------------------------------------------------------------------------
// [块 8] 解析 'Axxx' 帧(高 4bit=4'hA): 后 12bit 为 ESO 的 c 参数
//   同样 led7 翻转指示, c_flag 置 1 后不清零。
// 附注(设计隐患): c_flag 与 k_flag 一旦置 1 永不清除, 而 eso.v 中
//   'if(c_flag) c<=c_date; else if(k_flag) k<=k_date;' 为优先级结构,
//   所以一旦收到过 A 帧, 之后的 B 帧将**永远无法更新 k**。
//   若要两个参数都能反复在线修改, 应在解析块中把两个 flag 都做成单周期脉冲。
//------------------------------------------------------------------------------
always@(posedge sys_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) 
        led7<=1'b1; 
    else if((rx_date[15:12]==4'HA)&&(po_flag3==1'B1)) //前四位为参数标志位，后12位为数据位
        begin 
            led7<=~led7; //C 接收标志位有效后 led7 跳变 
            c_flag<=1'b1; 
            c_date<=rx_date[11:0]; //Axxx，xxx 为 adrc 的 c 
        end 
    else 
        begin 
            led7<=led7; 
            //c_flag<=1'b0; 
            c_date<=c_date; 
        end 
 
 
//------------------------------------------------------------------------------
// [例化 1] 按键消抖
//------------------------------------------------------------------------------
key key_inst 
( 
    .key_in(key_in), 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .key_out(key_out) 
); 
 
//------------------------------------------------------------------------------
// [例化 2] 数码管显示: 显示 ad_date 的十进制值, 小数点位置 4'b0100(第 3 位),
// seg_en 恒为 1(常开), sign 来自 rtl 的符号判断, 用于显示负号。
//------------------------------------------------------------------------------
seg seg_inst 
( 
    .clk(sys_clk), 
    .rst_n(sys_rst_n), 
    .point(4'b0100), 
    .data(ad_date), //gai 
    .seg_en(1'b1), 
    .sign(sign), 
    .sel(sel), 
    .seg(seg) 
); 
//------------------------------------------------------------------------------
// [例化 3] AD 中值滤波与电压换算(模块名 rtl, 实例名 adc_inst)
// 输出 sign 用于显示负号, volt 电压值本模块未使用(仅作为内部计算)。
//------------------------------------------------------------------------------
rtl adc_inst 
( 
    .clk(sys_clk), 
    .rst_n(sys_rst_n), 
    .ad_data(ad_date), 
    .sign(sign), 
    .volt(volt) 
); 
//------------------------------------------------------------------------------
// [例化 4] ESO 扩展状态观测器
//   ad_clk   : 用 ad_clk1(1kHz)作为观测器采样节拍;
//   e_in     : date_y(去偏置的 ADC 误差), 注意 eso 内部会再取负号 -e_in;
//   u_out    : date_u 回送, 构成 u(k) 的一拍延迟;
//   out_da   : date_u 的另一驱动源, 即控制量输出(与 u_out 共用一个 wire)。
//------------------------------------------------------------------------------
eso eso_inst 
( 
    .ad_clk(ad_clk1), 
    .sys_rst_n(sys_rst_n), 
    // 原工程用 ad_clk1(1kHz) 电平当时钟, 每拍都算 -> 常开使能即可
    .en(1'b1), 
    .e_in(date_y), 
    .u_out(date_u), 
    .out_da(date_u), 
    .c_flag(c_flag), 
    .k_flag(k_flag), 
    .c_date(c_date), 
    .k_date(k_date) 
); 
 
//------------------------------------------------------------------------------
// [例化 5] 串口接收(115200, 8N1): 50MHz 时钟下分频计数值 = 434
//------------------------------------------------------------------------------
uart_rx
#(
    .UART_BPS(115200),
    .CLK_FREQ(50_000_000)
)
uart_rx_inst 
( 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .rx(rx), 
    .po_data(po_data), 
    .po_flag(po_flag) 
); 
 
//------------------------------------------------------------------------------
// [例化 6] 串口发送(115200, 8N1)
//   pi_data = {ad_pingj0, ad_pingj1} = {ad_date[7:0], 6'b0, ad_date[9:8]},
//   即一帧 16bit: 先低字节后高字节(uart_tx 内部先发 bit[7:0] 再发 bit[15:8]);
//   pi_flag = 1'b1 常高 => 发送器自由连续发送, 每 20 个位时隙(约 174us)发一帧,
//   由内部 work_en/bit_cnt 自行握手机制保证一帧一帧连续输出。
//------------------------------------------------------------------------------
uart_tx
#(
    .UART_BPS(115200),
    .CLK_FREQ(50_000_000)
)
uart_tx_inst 
( 
    .sys_clk(sys_clk), 
    .sys_rst_n(sys_rst_n), 
    //.pi_data(rx_date),//tx 先发低八位，所以 tx 值跟实际 rx_date 顺序颠倒，不影响 rx_date数值 
    .pi_data({ad_pingj0,ad_pingj1}), 
    .pi_flag(tx_req),   // [P5] UART_MODE=1 按 REPORT_MS 定时；=0 连续发送 
    
    .tx(tx) 
); 
 
//------------------------------------------------------------------------------
// [已注释] PLL 例化: 原设计用 Gowin_PLL 产生 ad_clk1/da_clk1(6.25MHz),
// 后被 divider(1kHz)替代, 因此 gowin_pll.v 虽在工程中但未例化。
//------------------------------------------------------------------------------
/*Gowin_PLL pll_inst(
    .clkout0(ad_clk1), //output clkout0
    .clkout1(da_clk1), //output clkout1
    .clkin(sys_clk) //input clkin
); */

//------------------------------------------------------------------------------
// [例化 7] 分频器: cnt_max=24999, 50MHz/(2*25000) = 1kHz,
// 同时输出 clk0->ad_clk1、clk1->da_clk1, 两路同频同相。
//------------------------------------------------------------------------------
divider 
#(
    .cnt_max(24999)
)
divider_inst(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .clk0(ad_clk1),
    .clk1(da_clk1)
);



//------------------------------------------------------------------------------
// [已注释] fifo_top 例化: 原计划用 10bit x 128 深度的异步 FIFO 缓存 AD 数据,
// 因未使用(且相关信号 WrEn/RdEn/Q/Empty/Full 未声明), 故 fifo_top.v 只是被
// 包含在工程中, 并没有进入网表。
//------------------------------------------------------------------------------
/*fifo_top fifo_top_inst1(
		.Data(ad_date), //input [9:0] Data
		.WrClk(ad_clk1), //input WrClk
		.RdClk(ad_clk1), //input RdClk
		.WrEn(WrEn), //input WrEn
		.RdEn(RdEn), //input RdEn
		.Q(Q), //output [9:0] Q
		.Empty(Empty), //output Empty
		.Full(Full) //output Full
	);*/

//------------------------------------------------------------------------------
// 附注: 本模块共 42 个 I/O(B 参数 44 个引脚约束中含 2 个未使用端口),
// 综合后逻辑占用 575 LUT / 375 REG / 7 个乘法器, 资源占用极低。
//------------------------------------------------------------------------------
endmodule 