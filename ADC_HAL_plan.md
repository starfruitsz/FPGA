# ADC HAL 设计草案 v0.3（可扩展）

> 目标：抽象层只暴露“采样流 + 配置总线”；新增 ADC 型号/参数时，
> **不改应用层、不改接口端口**，只加文件、加 CSR 地址、加工厂分支。

## 1. 三个稳定契约

| 契约 | 方向 | 端口（固定） |
|---|---|---|
| `app_stream` | ABS → APP | `s_data[DW-1:0]`、`s_ch`、`s_valid`、`s_ready`、`s_info[SBW-1:0]` |
| `raw_stream` | HAL → ABS | `r_data[RW-1:0]`、`r_ch`、`r_valid`、`r_ready` |
| `csr` | APP/顶层 → HAL/ABS | `csr_addr[7:0]`、`csr_wdata[31:0]`、`csr_we`、`csr_rdata[31:0]` |

`s_info` 预留字段：`{timestamp[15:0], flags[3:0], rsv}`，以后加“采样序号/触发标记/溢出”不用改端口。

## 2. 参数与默认值（adc_defs.vh）

```verilog
`define ADC_IF_VERSION 16'h0100
`define ADC_DEF_RES     12
`define ADC_DEF_ALIGN   1     // 0=右 1=左
`define ADC_DEF_CH      1
`define ADC_DEF_DW      16
`define ADC_DEF_RW      16
`define ADC_DEF_SIGNED  0
`define ADC_IMPL_STUB   0
`define ADC_IMPL_PAR    1
`define ADC_IMPL_SPI    2
```

新增参数（增益、偏置、滤波器、过采样…）加到宏 + CSR，不动端口。

## 3. CSR 地址表（示例）

| 地址 | 名称 | 说明 |
|---|---|---|
| 0x00 | ID | `{version, impl, ch, res}` |
| 0x04 | CTRL | enable/reset/test |
| 0x08 | RATE | 采样率分频 |
| 0x0C | GAIN | 增益（预留） |
| 0x10 | OFFSET | 偏置（预留） |
| 0x14 | STATUS | locked/error/overflow |
| 0x18 | CH_EN | 通道使能 |
| 0x1C | FORMAT | 对齐/有符号（运行时可改） |
| 0x100+ | 厂商 | 型号私有寄存器 |

## 4. 工厂

```verilog
module adc_top #(parameter integer ADC_IMPL = `ADC_IMPL_SPI) (...);
  generate
    if (ADC_IMPL == `ADC_IMPL_STUB) adc_stub ...
    else if (ADC_IMPL == `ADC_IMPL_PAR) adc_par ...
    else adc_spi ...
  endgenerate
endmodule
```

## 5. 新增一款 ADC 的清单

1. 新建 `hal/adc_<model>.v`：实现 raw_stream + csr（按 `adc_backend_if.vh` 模板）；
2. `adc_defs.vh` 加 impl 编号；
3. `adc_top.v` 加一个 generate 分支；
4. 顶层加引脚、`pins/*.csv` 加行、重新生成 `.cst`；
5. 跑 `check_adc_contract.py` + TD + stub 回归。

## 6. 哪些稳定、哪些可换

| 稳定（不要改） | 可换（适配器） |
|---|---|
| app_stream / raw_stream / csr 端口 | `adc_norm.v`（对齐/位宽/通道拆分） |
| CSR 地址 0x00–0x1F | `hal/adc_*.v`（型号驱动） |
| 应用层只认 stream | `adc_cfg.v` 的具体寄存器实现 |

## 7. 验证与回归

- `adc_stub.v`：内部产生锯齿波，无硬件也能跑通显示/触发/测量；
- `check_adc_contract.py`：检查 backend 端口是否满足契约；
- 回归顺序：stub → 并行基线 → SPI（参数到位后）。

## 8. 步骤

S1 目录 + `adc_defs.vh` + `adc_if` 契约 + `adc_stub`（可仿真）
S2 `adc_norm` + `adc_par` 回接现有显示（不回归）
S3 `adc_spi`（等 SPI 参数）
S4 `adc_cfg/monitor` + 顶层 + `.cst`
S5 仿真 + TD + 第 19 章


---

## 9. 实施状态（2026-10-29）

### 已完成 S1

| 文件 | 说明 |
|---|---|
| `src/adc/hal/adc_defs.vh` | 参数默认值与型号编号 |
| `src/adc/hal/adc_backend_if.vh` | backend 端口契约（模板） |
| `src/adc/hal/adc_stub.v` | 内部锯齿源，无硬件自测 |
| `src/adc/hal/adc_par.v` | 并行基线（等价原 ad_date 行为） |
| `src/adc/hal/adc_spi.v` | SPI 模板（占位，接口已定，待参数） |
| `src/adc/abs/adc_norm.v` | 对齐/位宽归一化 |
| `src/adc/abs/adc_cfg.v` | CSR 寄存器组（ID/CTRL/RATE/GAIN/OFFSET/STATUS/CH_EN/FORMAT） |
| `src/adc/adc_top.v` | 工厂：IMPL 选型号，统一输出采样流 |

### 已完成 S2

- `scope_capture` 新增 `sample_valid`，`tick = sample_valid && (rate_cnt==rate_div)`；
- `vga_scope_top` 新增 `adc_valid`，两通道共用；
- `adda_scope_top` 例化 `adc_top`（IMPL=1、RES=10、ALIGN=0），
  `ad_date` → adc_top → s_data/s_valid → ch0_in/adc_valid`；
- 因为并行 backend 每个 clk 给一个 valid，capture 仍按 `tb_div` 抽取，
  **行为与改造前一致**（无回归）。

### 验证

- TD 前端分析：**33 个源文件通过**（27 + ADC 6）；
- 端口检查：**31 个模块、37 处例化、0 错误**；
- EG4S20BG256 工程已生成（`FPGA_TD/EG4S20BG256_scope.al`，33 文件），
  但本机 TD 6.0.3 无 Eagle 器件库，打开报 `Unknown device name`（详见 `FPGA_TD/eg4/README.md`）。

### 待办

- S3：`adc_spi` 具体实现，需 SPI 模式/位宽/CS 极性/时钟频率；
- S4：CSR 接到串口命令，顶层 SPI 引脚 + 约束；
- S5：仿真与第 19 章。


## 10. S3 进展（AD7606）

- 新增 src/adc/hal/adc_ad7606_spi.v：串行模式驱动（CONVST/BUSY/CS/SCLK/DOUTA/RESET），
  每次转换读回 ch1..ch4（DOUTA），16bit MSB-first；
- 新增 src/adc/adc_ad7606_top.v：CSR + 驱动 + 归一化（补码→偏移二进制→取高 10 位）；
- adc_norm 增加 SIGNED 参数（补码转偏移二进制）；
- 引脚建议见 doc/SparkRoad-V_pinmap.md 第 8 节（待确认接线后写约束）。
