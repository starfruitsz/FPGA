module seg 
#( 
    parameter CNT_MAX=16'd23999 
)
 
( 
    input wire clk, 
    input wire rst_n, 
    input wire [3:0]point, 
    input wire [9:0]data, //？位宽 
    input wire seg_en, 
    input wire sign, 
    
    output reg [3:0]sel, 
    output reg [7:0]seg  
); 
 
wire [3:0]unit; 
wire [3:0]ten; 
wire [3:0]hun; 
  
bcd bcd_8421( 
    .clk(clk), 
    .rst_n(rst_n), 
    .data(data), 
    
    .unit(unit), 
    .ten(ten), 
    .hun(hun) 
 ); 
 
reg [15:0]data_reg; 
reg [15:0]cnt_1ms; 
reg flag_1ms; 
reg [2:0]cnt_sel; 
reg [5:0]sel_reg; 
reg [3:0]data_disp; 
reg dot_disp; 
 
//控制数码管显示 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_reg<=1'b0; 
    //若显示的十进制数的百位为非零数据或需显示小数点，则值显示 3 个数码管 
    else if(((hun) || (point[2])) && (sign == 1'b1))//显示负号 
        data_reg <= {4'd10,hun,ten,unit};//4'd10 我们定义为显示负号 
    else if(((hun) || (point[2])) && (sign == 1'b0)) 
        data_reg <= {4'd11,hun,ten,unit}; 
    //若显示的十进制数的十位为非零数据或需显示小数点，则值显示 2 个数码管 
    else if(((ten) || (point[1])) && (sign == 1'b1)) 
        data_reg <= {4'd11,4'd10,ten,unit};
    else if(((ten) || (point[1])) && (sign == 1'b0)) 
        data_reg <= {4'd11,4'd11,ten,unit}; 
    //若显示的十进制数的个位且需显示负号 
    else if(((unit) || (point[0])) && (sign == 1'b1)) 
        data_reg <= {4'd11,4'd11,4'd10,unit}; 
    //若上面都不满足都只显示一位数码管 
    else 
        data_reg <= {4'd11,4'd11,4'd11,unit}; 
 
//计数器计数 1ms 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        cnt_1ms<=1'b0; 
    else if(cnt_1ms==CNT_MAX) 
        cnt_1ms<=1'b0; 
    else 
        cnt_1ms<=cnt_1ms+1'b1; 
 
//计数标志位 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        flag_1ms<=1'b0; 
    else if(cnt_1ms==CNT_MAX-1'b1) 
        flag_1ms<=1'b1; 
    else 
        flag_1ms<=1'b0; 
 
//cnt_sel：从 0 到 5 的循环，用于选择当前显示的数码管 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        cnt_sel<=1'b0; 
    else if(cnt_sel==3'b101 && flag_1ms) 
        cnt_sel<=1'b0; 
    else if(flag_1ms) 
        cnt_sel<=cnt_sel+1'b1; 
    else 
        cnt_sel<=cnt_sel; 
 
//数码管位选信号寄存器 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        sel_reg<=4'b000_000; 
    else if(!cnt_sel && flag_1ms)
        sel_reg<=4'b0001; 
    else if(flag_1ms) 
        sel_reg<=sel_reg<<1; 
    else 
        sel_reg<=sel_reg; 
 
//控制数码管的位选信号，使六个数码管轮流显示 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_disp<=1'b0; 
    else if(seg_en && flag_1ms) 
        case(cnt_sel) 
            3'd0:data_disp<=data_reg[3:0]; 
            3'd1:data_disp<=data_reg[7:4]; 
            3'd2:data_disp<=data_reg[11:8]; 
            3'd3:data_disp<=data_reg[15:12]; 
            default:data_disp<=1'b0; 
        endcase 
    else 
        data_disp<=data_disp; 
 
//dot_disp:小数点也高电平点亮 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        dot_disp<=1'b1; 
    else if(flag_1ms) 
        dot_disp<=point[cnt_sel]; 
    else 
        dot_disp<=dot_disp; 
 
//控制数码管段选信号，显示数字 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        seg<=8'b0000_0000; 
    else 
        case(data_disp) 
            4'd0:seg<={dot_disp,7'b0111111}; 
            4'd1:seg<={dot_disp,7'b0000110}; 
            4'd2:seg<={dot_disp,7'b1011011}; 
            4'd3:seg<={dot_disp,7'b1001111}; 
            4'd4:seg<={dot_disp,7'b1100110}; 
            4'd5:seg<={dot_disp,7'b1101101}; 
            4'd6:seg<={dot_disp,7'b1111101}; 
            4'd7:seg<={dot_disp,7'b0000111}; 
            4'd8:seg<={dot_disp,7'b1111111}; 
            4'd9:seg<={dot_disp,7'b1101111}; 
            4'd10:seg<=8'b0100_0000; 
            4'd11:seg<=8'b0000_0000; 
            default:seg<=8'b0011_1111; 
        endcase 
 
//sel：数码管位选信号赋值 
always @(posedge clk or negedge rst_n) 
    if(!rst_n) 
        sel<=4'b0_000; 
    else 
        sel<=~sel_reg;
        
endmodule 