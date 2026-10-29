# EG4S20BG256 工程说明

本目录的 EG4S20BG256_scope.al 是按 Anlogic Eagle EG4S20BG256 预制的 TD 工程：

- Family: EG4 / Device: EG4S20BG256 / Speed: -5（按常见默认，若板卡为 -6 请改 XML）
- 源码：33 个 Verilog（原 27 + ADC HAL 6）
- 顶层：adda_scope_top

## 重要限制

本机 TD 6.0.3 只有 PH1/PH2 器件库（D:/FPGA/arch 下无 eg4_*.db），因此：

1. 打开本工程会报 Unknown device name EG4S20BG256；
2. 需要安装带 Eagle(EG4) 器件库的 TD（TD 5.x 或向安路索取 EG4 支持包），
   再执行 eg4/make_eg4.tcl 重建；
3. 本机语法/连线回归继续用 project_2025_11_07_TD.al（PH1 占位器件）。

## 重建步骤（在支持 EG4 的 TD 中）

    cd <repo>/FPGA_TD/eg4
    create_project -family eg4 -device EG4S20BG256 EG4S20BG256_scope .
    import_device eg4_20.db -package BG256 -speed 5
    add_files -list ./files.list
    top_module adda_scope_top

## 引脚约束

EG4 板卡引脚未知，未生成 .cst；请按原理图补 VGA/ADC/按键/数码管/串口。

## 速度等级

若板卡手册给出 -6，请把 XML 中 <Speed>-5</Speed> 改成 -6。
