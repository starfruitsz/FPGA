//==============================================================================
// 文件: adc_backend_if.vh    层: ADC HAL
// 功能: 型号驱动(backend)必须满足的端口契约（模板，不参与综合）
//------------------------------------------------------------------------------
// 每个 backend（adc_par / adc_spi / adc_xxx）必须提供：
//
//   module adc_<model> #(
//       parameter integer RW   = 16,   // 原始位宽
//       parameter integer RES  = 12,   // 有效分辨率
//       parameter integer ALIGN= 1,    // 对齐(仅文档用，归一化在 abs/adc_norm)
//       parameter integer CH   = 1
//   )(
//       input  wire            clk,
//       input  wire            rst,
//       input  wire            enable,      // 来自 adc_cfg
//       input  wire [15:0]     rate,        // 采样率分频(可选使用)
//       // 物理引脚(按型号增删)
//       ...
//       // 原始采样流 -> abs/adc_norm
//       output wire [RW-1:0]   r_data,
//       output wire [1:0]      r_ch,        // 通道号
//       output wire            r_valid,     // 单周期
//       input  wire            r_ready,     // 背压(可忽略)
//       // 状态
//       output wire            locked,
//       output wire            error
//   );
//
// 约束：
//   1) r_valid 只在有真实新样本时为 1，且持续 1 拍；
//   2) r_ch 与 r_data 同拍；CH>1 时按通道轮转；
//   3) 不得在 backend 内做对齐/位宽转换（那是 abs/adc_norm 的职责）；
//   4) 异步时钟域必须在 backend 内用 adc_cdc 处理，输出统一在 clk 域。
//
// 新增型号步骤见 doc/ADC_HAL_plan.md 第 5 节。
//==============================================================================
