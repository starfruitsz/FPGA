//==============================================================================
//==============================================================================
// 文件: fifo_top_tmp.v    IP 例化模板(不是设计文件, 不参与综合)
// 用途: 异步 FIFO 的例化模板, 复制到设计后改信号名即可使用。
// 注意: 本文件未加入工程文件列表, 仅供查阅。
//==============================================================================
//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9 (64-bit)
//Part Number: GW5A-LV25UG324C2/I1
//Device: GW5A-25
//Device Version: A
//Created Time: Fri Oct 24 16:45:53 2025

//Change the instance name and port connections to the signal names
//------------------------------------------------------------------------------
// [模板] fifo_top 例化: 10bit 数据, 独立读写时钟, FWFT 输出
//------------------------------------------------------------------------------
//--------Copy here to design--------

	fifo_top your_instance_name(
		.Data(Data_i), //input [9:0] Data
		.WrClk(WrClk_i), //input WrClk
		.RdClk(RdClk_i), //input RdClk
		.WrEn(WrEn_i), //input WrEn
		.RdEn(RdEn_i), //input RdEn
		.Q(Q_o), //output [9:0] Q
		.Empty(Empty_o), //output Empty
		.Full(Full_o) //output Full
	);

//--------Copy end-------------------
