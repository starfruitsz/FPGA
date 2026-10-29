# SparkRoad-V（EG4S20BG256）官方引脚映射

来源：verimake-team/SparkRoad-V 仓库中的官方约束文件与《Spark 开发板使用说明》
（`demo/8_VGA_Demo/source/sdc/VGA_Demo.adc`、`demo/3_Seg_4bit/sources/sdc/seg_pin.adc`、
`demo/2_Buttons&LED/sources/sdc/button_pin.adc`、`demo/6_uart_loopback/source/sdc/mini_EG4S20BG256.adc`、
`Docs/SparkRoad-V开发板简介.pdf`）。

## 1. 时钟与按键

| 信号 | 引脚 | 说明 |
|---|---|---|
| 系统时钟 | **K14** | 板载有源晶振，**24MHz**（不是 50MHz！） |
| BUTTON_L | H14 | 独立按键 |
| BUTTON_R | L12 | 独立按键 |
| BUTTON_U | J13 | 独立按键 |
| BUTTON_D | G12 | 独立按键 |
| BUTTON_C | G11 | 独立按键（常用作复位） |

## 2. VGA（GM7123，24bit）

| 信号 | 引脚 | 信号 | 引脚 | 信号 | 引脚 |
|---|---|---|---|---|---|
| VGA_CLK | H2 | VGA_G0 | L1 | VGA_B0 | G1 |
| VGA_HS | J3 | VGA_G1 | K2 | VGA_B1 | F1 |
| VGA_VS | J4 | VGA_G2 | K1 | VGA_B2 | F2 |
| VGA_R0 | L5 | VGA_G3 | J1 | VGA_B3 | E1 |
| VGA_R1 | L3 | VGA_G4 | H3 | VGA_B4 | G3 |
| VGA_R2 | M2 | VGA_G5 | J6 | VGA_B5 | E2 |
| VGA_R3 | M1 | VGA_G6 | H1 | VGA_B6 | D1 |
| VGA_R4 | L4 | VGA_G7 | H5 | VGA_B7 | C1 |
| VGA_R5 | K5 | | | | |
| VGA_R6 | K3 | | | | |
| VGA_R7 | K6 | | | | |

注意：需要 FPGA 输出一路 **VGA_CLK（H2）** 给 GM7123；本工程当前没有该输出，需要新增。

## 3. 4 位数码管

| 信号 | 引脚 | 信号 | 引脚 |
|---|---|---|---|
| DIG_1（千位/位选0） | B1 | SEG_A | E3 |
| DIG_2 | C3 | SEG_B | B3 |
| DIG_3 | C2 | SEG_C | F4 |
| DIG_4 | F3 | SEG_D | E4 |
| | | SEG_E | F5 |
| | | SEG_F | D3 |
| | | SEG_G | B2 |
| | | SEG_H（小数点） | A2 |

## 4. LED / 拨码 / 串口 / Flash

| 功能 | 引脚 |
|---|---|
| LED0..LED15 | M3, M4, N3, N4, M5, P4, N5, P5, R7, T7, T8, T9, M7, R12, T12, T13 |
| SW0..SW15 | T4, R5, T5, T6, M6, P6, N6, P8, N8, R9, P9, N9, T14, R14, T15, R15 |
| UART（USB2UART） | TX = **F16**，RX = **E16** |
| UART（外接模块） | TX = C11，RX = B15 |
| 用户 Flash | CS P14, MISO K11, MOSI M13, CCLK H4, WP J11, HOLD L13 |

## 5. ADC

手册写明：**1MSPS 12-bit SAR 型 ADC**、7 个 AD 接口；但：

- 官方约束文件（VGA/按键/数码管/串口）里**没有 ADC 引脚**；
- 手册管脚分配表里也**没有 ADC**；
- 原理图文字中只检索到 `ADC_REF = L11` 与 `ADC_CH_0..7`（后者出现在疑似另一页/另一版本的符号上）。

结论：**ADC 的 SPI 引脚（CS/SCLK/DIN/DOUT）需从原理图或板卡丝印确认**，或告诉我们 ADC 芯片型号。

## 6. 与本工程的冲突（重要）

| 本工程假设 | SparkRoad-V 实际 | 影响 |
|---|---|---|
| 50MHz 系统时钟 | 24MHz（K14） | 波特率、VGA 时序、1kHz 分频全部要重算；建议用 PLL 出 25MHz 像素时钟 |
| RGB444（12bit） | RGB888（24bit） | 取高 4 位接 R[7:4]/G[7:4]/B[7:4]，并新增 VGA_CLK 输出 |
| 并行 ADC `ad_date[9:0]` | 板载 SPI ADC（12bit） | 需实现 `adc_spi`，并把 CH0 改为该 ADC |
| 并行 DAC `ad_out/da_clk1` | 板上无 DAC | adda 的 DA 回环无法映射；CH1 需改用其他信号或去掉 |
| 数码管 sel/seg | DIG/SEG 命名，4 位 | 一一对应，但位选有效电平需确认 |
| 按键 key_in | BUTTON_L/R/U/D/C | 任选其一 |


## 7. AD7606 模块引脚（来自模块手册 V1.1）

| 模块引脚 | 芯片引脚 | 说明 |
|---|---|---|
| D15..D8 | DB15..DB8 | 并行数据高 8 位 |
| D7 | DB7 / DOUTA | 并行 D7；串行模式数据输出 A |
| D6..D0 | DB6..DB0 | 并行数据（串行模式不用） |
| FDA | FRSTDATA | 第一通道数据指示 |
| BUSY | BUSY | 转换忙，高有效 |
| CS | CS | 片选，低有效 |
| RD | RD / SCLK | 并行读；串行模式时钟 |
| RST | RESET | 复位，高有效 |
| CB / CA | CONVST B / A | 转换启动（可并联） |
| RANGE | RANGE | 1=±10V，0=±5V（模块默认上拉 ±10V） |
| STBY | STBY | 低=待机，正常接高 |
| SER | PAR/SER | 1=串行模式，0=并行 |
| OS0..OS2 | OS0..OS2 | 过采样倍数，000=不开启 |
| NC | — | 悬空 |

电压换算（REF=2.5V）：±5V 量程 A(mV) = D*5000/32768；±10V 量程 A(mV) = D*10000/32768；
D 是 16bit 补码。

## 8. AD7606 → SparkRoad-V 建议接线（GPIO 排针）

| AD7606 | FPGA 端口 | SparkRoad-V 引脚 |
|---|---|---|
| CA+CB | convst | A7（T1_N） |
| BUSY | busy | A8（T1_P） |
| CS | cs_n | A10（T2_P） |
| RD/SCLK | sclk | A9（T2_N） |
| D7/DOUTA | douta | A5（T3_P） |
| RST | adc_reset | A6（T3_N） |
| SER | ser | A3（T4_P）或直接接 3.3V |
| RANGE | 悬空或 range | 悬空=±10V |
| STBY | 接 3.3V | — |
| OS0..2 | 接 GND | — |
| +5V / GND | 模块电源 | 排针 5V / GND |

注意：以上为建议接线，实际以杜邦线为准；A7/A8/A10/A9/A5/A6/A3 属于 GPIO 扩展口，
使用前确认未被 SDRAM/摄像头占用；模块 5V 供电，禁止把 ±10V 模拟输入接到 FPGA。


## 9. 用户可配置项（引脚 / 量程 / 时序）

### 9.1 引脚：改 CSV 后重新生成约束

    FPGA/src/adc/pins/board_pins.csv      # 信号,位宽,引脚(|分隔),说明
    tools/gen_adc_pins.py                 # -> FPGA_TD/eg4/SparkRoad.adc

- 改引脚只动 CSV，然后重新运行生成脚本；
- 多位宽信号按"低位在前"填写，例如 vga_r,8,L5|L3|...
- 脚本会检查位宽是否匹配、引脚是否重复。

### 9.2 量程 / 过采样 / SCLK：运行时寄存器（CSR）

| 地址 | 名称 | 说明 |
|---|---|---|
| 0x20 | RANGE | bit0：1=±10V，0=±5V |
| 0x24 | OS | [2:0]：0=不过采样，1..6 对应 2x..64x |
| 0x28 | SDIV | [15:0]：SCLK 半周期（clk 数） |

### 9.3 编译期参数（adc_ad7606_top）

| 参数 | 默认 | 说明 |
|---|---|---|
| RES | 10 | 输出位宽（16bit 补码取高 RES 位） |
| SDIV_DEF | 4 | SCLK 半周期默认值 |
| OS_DEF | 0 | 过采样默认值 |
| RANGE_DEF | 1 | 1=±10V 0=±5V |

修改默认值不会影响 CSR 的运行时覆盖：上电用默认值，串口写 CSR 后按新值工作。
