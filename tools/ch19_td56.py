# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
old = """\\subsubsection{环境要求}

TD 必须安装 \\textbf{Eagle（EG4）器件库}。若打开工程提示
\\sig{Unknown device name EG4S20BG256}，说明当前 TD 只有 PH1/PH2 器件库
（本机 TD 6.0.3 即如此），需安装 TD 5.x 或向 Anlogic 索取 EG4 支持包。"""
new = """\\subsubsection{环境要求（TD 5.6.5 SP5）}

EG4/Eagle 器件库只随 \\textbf{TD 5.6.x} 提供，TD 6.0.3 只有 PH1/PH2。
本机已安装：

\\begin{center}
\\small
\\begin{tabular}{ll}
\\toprule
项目 & 内容\\\\
\\midrule
安装路径 & \\file{C:\\\\Anlogic\\\\TD\\_5.6.5\\_SP5\\_170.155}\\\\
器件库 & \\file{arch/eagle\\_20.db}（EG4S20），封装 \\sig{BGA256X}\\\\
工程文件 & \\file{FPGA\\_TD/scope\\_eg4.al}（35 文件 + 约束，顶层 \\sig{sparkroad\\_scope\\_top}）\\\\
License & \\file{license/Anlogic.lic}（必需，见下）\\\\
\\bottomrule
\\end{tabular}
\\end{center}

\\subsubsection{License}

TD 5.6 综合需要 \\file{license/Anlogic.lic}，缺失时 \\sig{optimize\\_rtl} 会报
\\sig{Cannot find license file}。申请方式：安路官网账号 $\\rightarrow$ 工具与资料下载
$\\rightarrow$ License（或联系 FAE），提供本机 MAC 地址
\\sig{40-A5-EF-5E-1D-40}；拿到后放入
\\file{C:\\\\Anlogic\\\\TD\\_5.6.5\\_SP5\\_170.155\\\\license\\\\Anlogic.lic}。"""
assert old in s, 'anchor not found'
s = s.replace(old, new, 1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('ch19 updated')
