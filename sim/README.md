# sim/ —— RTL 仿真

本目录是后加的仿真环境：**原工程（以及全部 19 章文档）此前没有做过任何 RTL 仿真**，
这里用 Icarus Verilog 补上回归用例。

## 0. 为什么不是 TD 仿真

两套 TD（6.0.3 / 5.6.5）都只带综合与布局布线，**没有仿真器**；本机也没有
ModelSim / Questa / Vivado / Verilator。因此采用开源 **Icarus Verilog 14**（Windows x64），
装在 `C:\iverilog`。

## 1. 怎么跑

```powershell
# 全量
powershell -ExecutionPolicy Bypass -File .\sim\run_all.ps1

# 只跑一个用例（示例：AD7606 串行驱动）
C:\iverilog\bin\iverilog.exe -g2005 -o sim\_build\adc.vvp ^
    sim\tb_adc_ad7606_spi.v sim\ad7606_model.v FPGA\src\adc\hal\adc_ad7606_spi.v
C:\iverilog\bin\vvp.exe -n sim\_build\adc.vvp
```

波形在 `_build\*.vcd`，可用 GTKWave 或 VS Code 的 WaveTrace 插件打开。
`tb_vga_timing` 要跑满一整场（16.8 ms@50 MHz），全量 dump 会到 100 MB+，默认关闭，
需要时加 plusarg：`vvp -n xxx.vvp +vcd`。

## 2. 当前用例（13/13 PASS）

| 用例 | 被测模块 | 验证内容 | 结果 |
|---|---|---|---|
| `tb_bcd` | `bcd.v` | 4 位 BCD：0/9/99/512/999/**1000**/**1023**（P4 修复点） | PASS |
| `tb_vga_timing` | `vga/hal/vga_timing.v` | de 25600 ns、行周期 32000 ns、行同步 3840 ns、场同步 64000 ns、场周期 16.8 ms | PASS |
| `tb_uart_tx` | `uart_tx.v` | 115200 8N1、21 位时隙、0xA55A 双帧、先低字节 LSB first | PASS |
| `tb_uart_rx` | `uart_rx.v` | 按位注入 8N1 串流：0x55/0xAA/0x00/0xFF/0x5A 逐字节还原，位中点采样 | PASS |
| `tb_cmd_chain` | `uart_rx` + `scope_cmd` + `adc_cmd` | 真串口喂 ASCII：T/R/A/L/E/S/M/C/P/H 与 R/O/S/K/N 全部命中；未知命令和小写不产生写；`R`/`S` 两边各写各的 | PASS |
| `tb_scope_capture` | `vga/app/scope_capture.v` | 触发状态机 IDLE→ARMED→FILL→DONE、normal 只触发一次、`rd_base = 触发地址 − pre_trig`、DONE 停止写入、auto 模式不进 FILL | PASS |
| `tb_adc_ad7606_spi` | `adc/hal/adc_ad7606_spi.v` + `ad7606_model.v` | 复位脉冲、locked/error、CONVST 宽度、64 个 SCLK 下降沿、4 路 16bit 补码逐位还原（含 0x0001 / 0x8000 边界） | PASS |
| `tb_adc_ad7606_top` | `adc/adc_ad7606_top.v`（含 `adc_cfg`/`adc_norm`） | CSR 写 0x28/0x08/0x04、读 ID=0x0100034A、补码→偏移二进制→取高 10 位（0x1234→584、0xEDCC→439、0x0001→512、0x8000→0） | PASS |
| `tb_scope_trigger` | `vga/vga_scope_top.v`（触发/滚动路径） | 周期 90 的方波：normal 模式下 `[rd_base..+639]` 严格符合"以触发点为起点"的相位（两次捕获各 0 个不符点）；关触发后同批地址一帧内变化 48/90（相位自由漂移）；滚动模式下最右列采样(949) > 最左列(311) | PASS |
| `tb_vga_scope_top` | `vga/vga_scope_top.v`（12 个子模块，整屏） | 640×480 `PIX_DIV=1`：每帧 de 像素 307200、行周期 800 clk、CH0=512 平在 y=223、CH1=300 平在 y=316、网格/零轴/文字/背景齐全、y=223/y=224 整行 0 异常列、斜坡输入纵向铺满 0..447 | PASS |
| `tb_vga_scope_top_pix2` | 同上，`-DPIX2` | `PIX_DIV=2` 对照：两个配置的颜色计数必须完全一致（修复后已一致） | PASS |
| `tb_vga_test_top` | `vga/vga_test_top.v` + `vga_test_app.v` | 自检顶层 5 幅画面：连抓 5 帧**按内容分类**（彩条/灰阶/棋盘/边框/文字），要求 5 种全部出现 | PASS |
| `tb_sparkroad_top` | `sparkroad_scope_top.v`（整机） | 24MHz + AD7606 模型 + VGA + 数码管 + 串口：ADC 复位/locked、串口 `T0000` 生效、CONVST 起振、整帧 307200 像素且波形随输入变化、数码管扫描、串口 TX 有起始位 | PASS |

> `tb_scope_capture` 用 `DEPTH_LOG2=4`（16 点缓存）压缩仿真时间，其余参数与真实配置一致。

## 3. AD7606 行为模型（`ad7606_model.v`）

按数据手册串行读时序建模，**只用于仿真，不参与综合**：

| 事件 | 模型行为 |
|---|---|
| CONVST 上升沿 | 锁存 ch1..ch4，BUSY 拉高 |
| BUSY | 维持 `CONV_CLK` 个 clk 后拉低（默认 60，模拟转换时间） |
| CS 下降沿 | 位指针归零，开始一帧 |
| SCLK 下降沿 | 输出下一位；**第 1 个下降沿输出 ch1 的 D15** |
| SCLK 上升沿 | 主机采样（数据在下降沿已稳定） |
| 一帧 64 位 | ch1..ch4 各 16 bit，MSB first |

DOUTA 用 `always @(negedge sclk)` 事件驱动而不是 clk 打拍，否则在 `sdiv=1`
（半周期只有 1 个 clk）时会晚一拍，整帧错位——这是写这个模型最容易踩的坑。

## 4. vga_scope_top 整屏用例要点

整屏用例是最复杂的一个，两个需要注意的地方：

1. **必须按 `pix_ce` 采样像素，不能按 clk**。`PIX_DIV=2` 时一个像素占 2 个时钟，
   按 clk 计数会把一帧算成两帧、坐标全部翻倍（第一版 TB 就踩了这个坑）。
2. **`PIX_DIV` 决定流水线是否对齐**。两条路径：
   - 坐标类图层（网格/文字）：`px → 组合逻辑 → rgb_r` = **1 拍**
   - 数据类路径（波形）：`px → BSRAM 同步读 → 组合 → rgb_r` = **2 拍**
   - `de` 延迟 **2 拍**

   所以 `PIX_DIV=2` 时二者正好对齐；`PIX_DIV=1` 时坐标类图层比 `de` **少打一拍**，
   输出级拿 `px=640` 去算最右一列，所有图层都不命中 → **每行最后一列恒为背景色**，
   且网格/文字整体左移 1 像素。

   **已修复**（2026-10-30，`vga_scope_top.v`）：在图层前插入 `px_d/py_d/de_d`
   打一拍的对齐寄存器，三个图层统一使用延迟后的坐标；`raddr` 仍用未延迟的 `px`
   以配合 BSRAM 的 1 拍读延迟。修复后 `PIX_DIV=1` 与 `PIX_DIV=2` 的整帧颜色计数
   逐项相同（295866/8862/640/639/639/554），说明两种配置产出的图像已经一致。

## 4.1 出图：把仿真帧导成 PNG

`tb_dump.v` 是独立的"出图"用例：跑一次触发捕获，等 `state==DONE`（缓冲冻结）后，
把接下来一整帧的 `vga_rgb`（RGB444）按每像素 2 字节小端写进 `frame.raw`，
再用 Python/Pillow 转成 `scope_sim_frame.png`。

```powershell
# 1) 跑仿真导出一帧
C:\iverilog\bin\iverilog.exe -g2005 -o sim\_build\dump.vvp sim\tb_dump.v <12 个 vga 源文件>
cd sim\_build; C:\iverilog\bin\vvp.exe -n .\dump.vvp
# 2) 转 PNG（需要 Pillow）
python raw2png.py
```

当前 `scope_sim_frame.png` 的内容是"周期 90 采样点的方波 + 触发对齐"：
深蓝背景 + 64px 绿色网格 + 深绿零轴(y=224) + 亮绿 CH0 方波(y=97/360) +
黄色 CH1 直线(y=223) + 底部两行文本。**这张图是仿真输出的像素原样**，
不是 Python 画的示意图（对比工程里 `FPGA/src/vga/preview_640x480.png` 是数学复现）。

## 5. 仿真发现的问题（都已在用例中固化）

1. **AD7606 驱动的位序是对的**：4 路 16bit 逐位还原，含最小正数 0x0001 与最小负数
   0x8000，说明“第 1 个下降沿出 D15、上升沿采样”的约定与手册一致。
2. **CONVST 宽度是 `CONV_CYC+1` 拍**（180 ns 而非 160 ns），**CS 低电平是
   `64*2*sdiv+1` 拍**（5140 ns 而非 5120 ns）——FSM 打拍造成的，功能无害，
   但按参数名义值写时序预算会差一拍。
3. **`vga_timing` 的 `px/py` 实际范围是 0..799 / 0..524**，而源码端口注释写的是
   `0..H_VIS-1`（0..639）。消隐期 `px` 照样在数，**新图层若直接用 px 而不用 de 屏蔽
   就会算错**。
4. **（已修复）`PIX_DIV=1`（SparkRoad 实际配置）下每行最后一列丢失**：修复前
   `x=639` 恒为背景色、网格/文字左移 1 像素；`PIX_DIV=2`（高云老工程）下正常。
   修法与回归见第 4 节。**RTL 已改动，旧比特流 `scope_eg4_60.bit` 作废**，
   已用 TD 5.6.5 重新综合为 `FPGA_TD/scope_eg4_61_Runs/best_result/scope_eg4_61.bit`。

## 5.1 修复后的重综合结果（TD 5.6.5 + EG4S20BG256）

| 项 | 修复前 `scope_eg4_60` | 修复后 `scope_eg4_61` | 变化 |
|---|---|---|---|
| LUT | 1632 / 19600 | 1645 / 19600 | +13 |
| 寄存器 | 832 / 19600 | 857 / 19600 | **+25**（= 12 px_d + 12 py_d + 1 de_d，与预期完全吻合） |
| DSP / BRAM / PAD | 6 / 4 / 51 | 6 / 4 / 51 | 不变 |
| Setup slack @24MHz | +20.485 ns | **+21.964 ns** | 更好（关键路径 21.182 → 19.703 ns，约 50.7 MHz） |
| Hold slack 最小 | — | +0.153 ns | 无违规 |
| 时序错误 | 0 | **0 setup / 0 hold** | — |
| 比特流 | 634296 B | 634296 B | 同尺寸 |

流程脚本：`FPGA_TD/full_flow61.tcl`（与 `full_flow60.tcl` 相同，仅工程名改为 `scope_eg4_61`，
**不覆盖**已归档的 60 版）。日志无 ERROR。

## 5.5 整机仿真与 PLL 空壳

`tb_sparkroad_top.v` 仿真的是**出比特流的那个顶层本身**：24MHz 时钟 + `ad7606_model`
接在 AD7606 引脚上 + 串口喂命令 + 抓一整帧 VGA。它一次跑通「ADC → HAL → 采集/触发/测量
→ 图层合成 → RGB888 → VGA 引脚」整条链路，并同时检查数码管与串口发送。

出图（`+dump`）得到 `scope_top_full.png`：波形呈「阶梯虚线」，是因为模型 4 个通道
同时给同一斜坡、而采样率约为像素时钟的 1/500，属于**激励特性**，不是渲染缺陷。

**关于 PLL 空壳**（`gowin_pll_shell.v`）：

- 真正的 `FPGA/src/gowin_pll/gowin_pll.v` 例化高云原语 `PLLA`，Icarus 无法解析；
- 但全仓检索后确认：**两个总顶层都没有例化 Gowin_PLL** —— `adda.v` 第 385、412 行
  附近两处例化都是注释掉的，1kHz 时钟由 `divider` 提供；`fifo_top` 同样未例化。
  所以**仿真总顶层并不需要 PLL 空壳**；
- 本文件是给「以后启用 PLL（例如 24MHz 换 25.175MHz 像素时钟）」预留的：把 50MHz
  按 6.25MHz 分频输出两路，编译时用本文件替代 `gowin_pll.v` 即可。限制：立即起振
  （不模拟锁定时间）、无抖动/相位噪声模型。

## 6. 还没覆盖的

| 模块 | 障碍 | 补的办法 |
|---|---|---|
| `adda_scope_top`（高云版总顶层） | 例化遗留 `adda` + `vga_scope_top` + `adc_top` 工厂，三者都可仿真 | 照 `tb_sparkroad_top` 再写一个即可 |
| `adc_top` 工厂（stub/并行分支） | `adc_stub` 自带锯齿源，可直接跑 | 加一个用例即可 |
| `gowin_pll/gowin_pll.v` | 例化高云 `PLLA` 原语 | 用 `sim/gowin_pll_shell.v` 替代（当前无人例化） |
| `fifo_top/fifo_top.v` | IEEE 1735 加密，源码不可读 | 只能用行为模型替代 |

## 7. 约定

- 每个用例输出一行 `[tb_xxx] PASS` 或 `[tb_xxx] FAIL`，脚本按这两个关键字判定；
- 新增用例：写 `tb_*.v`，再在 `run_all.ps1` 的 `$cases` 里加一行
  （`srcs` 相对 `FPGA/src`，`local` 相对 `sim/`）；
- 只读工程源码，仿真产物全部落在 `sim/_build/`。