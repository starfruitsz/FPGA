//==============================================================================
// 文件: adc_defs.vh        层: ADC HAL
// 功能: ADC 抽象层的参数默认值与型号编号（只作文档/可选 include 使用）
// 说明: 为避免综合器 include 路径问题，各模块默认不 include 本文件，
//       而是用自己的 parameter 默认值（与本文件保持一致）。
//       新增参数时：这里加宏 → 对应模块加 parameter → CSR 加地址。
//==============================================================================
`ifndef ADC_DEFS_VH
`define ADC_DEFS_VH


`define ADC_IF_VERSION   16'h0100   // 接口版本 v1.0
`define ADC_DEF_RES      12        // 有效分辨率
`define ADC_DEF_ALIGN    1'b1      // 0=右对齐 1=左对齐
`define ADC_DEF_CH       1         // 通道数
`define ADC_DEF_DW       16        // 归一化位宽
`define ADC_DEF_RW       16        // 原始流位宽
`define ADC_DEF_SIGNED   1'b0      // 原始数据是否有符号

// 型号(工厂)编号
`define ADC_IMPL_STUB    0         // 内部锯齿波，无硬件自测
`define ADC_IMPL_PAR     1         // 并行接口(基线)
`define ADC_IMPL_SPI     2         // SPI 接口(待型号参数)

`endif
