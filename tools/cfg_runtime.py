# -*- coding: utf-8 -*-
import io

# ---------- 1) adc_cfg: 增加 RANGE/OS/SDIV 运行时寄存器 ----------
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/abs/adc_cfg.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""module adc_cfg #(
    parameter integer IMPL  = 1,
    parameter integer RES   = 12,
    parameter integer ALIGN = 1,
    parameter integer CH    = 1,
    parameter integer DW    = 16
)(""", """module adc_cfg #(
    parameter integer IMPL   = 1,
    parameter integer RES    = 12,
    parameter integer ALIGN  = 1,
    parameter integer CH     = 1,
    parameter integer DW     = 16,
    parameter integer SDIV_DEF  = 4,     // 默认 SCLK 半周期
    parameter integer OS_DEF    = 0,     // 默认过采样
    parameter integer RANGE_DEF = 1      // 默认 1=±10V 0=±5V
)(""")
s = s.replace("""    output reg  [3:0]  ch_en,
    output reg         fmt_align,
    output reg         fmt_signed
);""", """    output reg  [3:0]  ch_en,
    output reg         fmt_align,
    output reg         fmt_signed,
    output reg  [15:0] sdiv,
    output reg  [2:0]  os_sel,
    output reg         range_sel
);""")
s = s.replace("""            8'h1C: csr_rdata = {30'd0, fmt_signed, fmt_align};""",
"""            8'h1C: csr_rdata = {30'd0, fmt_signed, fmt_align};
            8'h20: csr_rdata = {31'd0, range_sel};
            8'h24: csr_rdata = {29'd0, os_sel};
            8'h28: csr_rdata = {16'd0, sdiv};""")
s = s.replace("""            fmt_align  <= ALIGN[0];
            fmt_signed <= 1'b0;""",
"""            fmt_align  <= ALIGN[0];
            fmt_signed <= 1'b0;
            sdiv       <= SDIV_DEF[15:0];
            os_sel     <= OS_DEF[2:0];
            range_sel  <= RANGE_DEF[0];""")
s = s.replace("""                8'h1C: begin fmt_align <= csr_wdata[0]; fmt_signed <= csr_wdata[1]; end""",
"""                8'h1C: begin fmt_align <= csr_wdata[0]; fmt_signed <= csr_wdata[1]; end
                8'h20: range_sel <= csr_wdata[0];
                8'h24: os_sel    <= csr_wdata[2:0];
                8'h28: sdiv      <= csr_wdata[15:0];""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('adc_cfg extended')

# ---------- 2) 驱动: SPI_DIV 改为运行时 sdiv ----------
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/hal/adc_ad7606_spi.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""    parameter integer SPI_DIV   = 4,     // SCLK 半周期(clk 数)
    parameter integer CONV_CYC  = 8,     // CONVST 高电平宽度(clk 数)""",
"""    parameter integer CONV_CYC  = 8,     // CONVST 高电平宽度(clk 数)""")
s = s.replace("""    input  wire [15:0]   rate,        // 两次转换之间的 clk 数(0=连续)""",
"""    input  wire [15:0]   rate,        // 两次转换之间的 clk 数(0=连续)
    input  wire [15:0]   sdiv,        // SCLK 半周期(clk 数)，运行时可配
    input  wire [2:0]    os_sel,      // 过采样配置
    input  wire          range_sel,   // 1=±10V 0=±5V""")
s = s.replace("""            ser       <= 1'b1;     // 串行模式
            os        <= 3'd0;     // 不过采样
            range     <= 1'b1;     // ±10V(悬空默认)""",
"""            ser       <= 1'b1;     // 串行模式
            os        <= 3'd0;     // 由 os_sel 运行时覆盖
            range     <= 1'b1;     // 由 range_sel 运行时覆盖""")
s = s.replace("""        else begin
            r_valid <= 1'b0;
""", """        else begin
            r_valid   <= 1'b0;
            os        <= os_sel;
            range     <= range_sel;
""")
s = s.replace("""                    if (sclk_cnt == SPI_DIV - 1) begin""",
"""                    if (sclk_cnt == ((sdiv == 16'd0) ? 16'd1 : sdiv) - 1) begin""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('driver parameterized')

# ---------- 3) adc_top: cfg 新输出悬空 ----------
p = r'C:/Users/Administrator/Desktop/task/FPGA/src/adc/adc_top.v'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace("""        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed)
    );""", """        .enable(enable), .rate(rate), .gain(gain), .offset(offset),
        .ch_en(ch_en), .fmt_align(fmt_align), .fmt_signed(fmt_signed),
        .sdiv(), .os_sel(), .range_sel()
    );""")
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('adc_top cfg updated')
