//==============================================================================
//==============================================================================
// 文件: gowin_pll_tmp.v   IP 例化模板(不是设计文件, 不参与综合)
// 用途: Gowin IP Generator 生成的'照抄即用'模板, 把下面 7 行复制到设计里
//       并改成自己的信号名即可例化 Gowin_PLL。
// 注意: 本文件未加入工程文件列表, 仅供查阅。
//==============================================================================
//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9 (64-bit)
//Part Number: GW5A-LV25UG324C2/I1
//Device: GW5A-25
//Device Version: A
//Created Time: Wed Oct 22 16:48:35 2025

//Change the instance name and port connections to the signal names
//------------------------------------------------------------------------------
// [模板] Gowin_PLL 例化: clkout0/clkout1 为 6.25MHz 输出, clkin 接 50MHz
//------------------------------------------------------------------------------
//--------Copy here to design--------

    Gowin_PLL your_instance_name(
        .clkout0(clkout0_o), //output clkout0
        .clkout1(clkout1_o), //output clkout1
        .clkin(clkin_i) //input clkin
    );

//--------Copy end-------------------
