# 第三方参考与许可说明

本工程为原创实现，**没有复制任何第三方源代码**。下列项目仅作为设计思路参考：

| 项目 | 用途 | 许可 |
|---|---|---|
| [基于FPGA的数字示波器（Verilog）](https://atomgit.com/open-source-toolkit/885f1/tree/main) | 等效采样、VGA 波形显示的组织方式 | MIT |
| [UMD Physics 495: Digital Oscilloscope](https://www.physics.umd.edu/hep/drew/495/scope.html) | 触发电平/预触发/控制状态寄存器的设计思路 | 教学材料 |
| [MIT 6.111 数字存储示波器项目](http://web.mit.edu/6.111/www/f2016/projects/jatron_Project_Final_Report.pdf) | 双通道 DSO 的系统划分 | 课程材料 |
| [sigrok / PulseView](https://sigrok.org/wiki/Main_Page) | 采集会话状态机、触发配置模型的参考 | GPLv3+ |
| [ngscopeclient / scopehal](https://www.ngscopeclient.org/) | 测量项定义（Vpp/均值/周期等）的参考 | GPLv3 |
| [ScopeFun](https://www.opensourceimaging.org/project/scopefun/) | 整机寄存器/上位机协议架构的参考 | 硬件 CERN OHL，软件 GPLv3 |

注意：GPLv3 项目的代码不能直接并入本仓库；本工程只借鉴其**功能定义与架构**，实现均为独立编写。
本仓库自身采用 MIT 许可，见 `LICENSE`。
