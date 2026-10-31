//==============================================================================
// 文件: bcd.v            模块: bcd            实例名: bcd_8421(seg 内部)
// 功能: 二进制转 BCD 码(双 dabble / 移位加 3 法)，10bit 输入 -> 4 位十进制。
// [修复 P4] 原实现只保留 3 位 BCD(0~999)，AD 满码 1000~1023 会丢千位；
//           现扩展为 4 位(0~1023)，新增 thou 输出。
// 结构: data_shift = {BCD 16bit, 二进制 10bit} 共 26bit;
//       每个二进制位做一次"判断加 3 -> 左移"，共 10 次，最后从高 16 位取结果。
// 时序: 用 shift_flag 把"加 3"和"移位"拆到相邻两个时钟，一次转换 24 拍
//       (50MHz 下 480ns)，连续转换，不做忙闲握手。
//==============================================================================
module bcd
( 
    input wire clk, 
    input wire rst_n, 
    input wire [9:0]data, 
    
    output reg [3:0]unit, 
    output reg [3:0]ten, 
    output reg [3:0]hun,
    output reg [3:0]thou
); 
 
//------------------------------------------------------------------------------
// 内部信号
//   cnt_shift : 转换相位计数 0~11
//   data_shift: {BCD[25:10], 二进制[9:0]} 移位寄存器
//               [13:10]=个位 [17:14]=十位 [21:18]=百位 [25:22]=千位
//   shift_flag: 0=执行"加 3 修正", 1=执行"左移"
//------------------------------------------------------------------------------
reg [4:0]cnt_shift; 
reg [25:0]data_shift; 
reg shift_flag; //移位标志信号 
 
//------------------------------------------------------------------------------
// [块 1] 相位计数: shift_flag=1 时步进, 到 11 后回 0
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) //0-11 循环 
    if(!rst_n) 
        cnt_shift<=1'b0; 
    else if(cnt_shift==5'd11 && shift_flag) 
        cnt_shift<=1'b0; 
    else if(shift_flag) 
        cnt_shift<=cnt_shift+1'b1; 
    else 
        cnt_shift<=cnt_shift; 
 
//------------------------------------------------------------------------------
// [块 2] 移位/修正主过程
//   cnt_shift=0            : 装入 {16'b0, data}
//   cnt_shift<=10 且 flag=0: 四个 BCD 位分别"大于 4 则加 3"
//   cnt_shift<=10 且 flag=1: 整体左移一位
//   cnt_shift=11           : 保持, 等待块 4 输出
// 说明: 0 相位会持续 2 拍(flag 的两种取值)，数据被重复装入一次，无害。
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_shift<=1'b0; 
    else if(!cnt_shift) 
        data_shift<={16'b0,data}; //目标 BCD 16 位 + 10 位待转换数据 
    else if(cnt_shift<=10 && (!shift_flag)) //低判断 
        begin 
            data_shift[13:10]<=(data_shift[13:10]>4)? (data_shift[13:10]+2'd3):(data_shift[13:10]); //大于 4 就加 3，否则不变 
            data_shift[17:14]<=(data_shift[17:14]>4)? (data_shift[17:14]+2'd3):(data_shift[17:14]); 
            data_shift[21:18]<=(data_shift[21:18]>4)? (data_shift[21:18]+2'd3):(data_shift[21:18]);  
            data_shift[25:22]<=(data_shift[25:22]>4)? (data_shift[25:22]+2'd3):(data_shift[25:22]);  
        end
    else if(cnt_shift<=5'd10 && shift_flag) //高移位 
        data_shift<=data_shift<<1; 
    else 
        data_shift<=data_shift; 
 
//------------------------------------------------------------------------------
// [块 3] 相位标志: 每个时钟翻转一次, 与块 1 配合形成 加3/移位 交替节拍
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        shift_flag<=1'b0; 
    else 
        shift_flag<=~shift_flag; //移位标志信号 
 
//------------------------------------------------------------------------------
// [块 4] 结果锁存: 第 11 相位把 16bit BCD 拆成 unit/ten/hun/thou 输出
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        begin 
            unit<=1'b0; 
            ten<=1'b0; 
            hun<=1'b0; 
            thou<=1'b0; 
        end 
    else if(cnt_shift==5'd11) 
        begin 
            unit<=data_shift[13:10]; 
            ten<=data_shift[17:14]; 
            hun<=data_shift[21:18]; 
            thou<=data_shift[25:22]; 
        end 
 
//------------------------------------------------------------------------------
// 附注: 四组 BCD 判断都在同一拍完成, 组合路径较长(约 5 级比较+加法),
// 50MHz 下时序裕量充足; 若提高主频需做流水化处理。
//------------------------------------------------------------------------------
endmodule  
