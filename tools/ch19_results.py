# -*- coding: utf-8 -*-
import io
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()

ins = r'''\subsection{综合与布局布线结果（TD 5.6.5）}

在 TD 5.6.5 SP5 + EG4S20BG256 上完成综合、布局布线与比特流生成：

\begin{center}
\small
\begin{tabular}{lrl}
\toprule
项目 & 结果 & 说明\\
\midrule
LUT & 1657 / 19600 & 8.45\%\\
寄存器 & 848 / 19600 & 4.33\%\\
DSP & 6 / 29 & 20.69\%\\
BRAM & 4 / 64 & 6.25\%（两路采样缓存 + 字模）\\
PAD & 51 / 188 & 27.13\%\\
时钟约束 & 41.667\,ns（24\,MHz） & \file{SparkRoad.sdc}\\
时序 & 0 setup / 0 hold 错误 & 最小周期 20.79\,ns（约 48\,MHz）\\
比特流 & 634\,296 字节 & \file{scope\_eg4\_59.bit}\\
\bottomrule
\end{tabular}
\end{center}

\noindent 说明：Tcl 流程必须在\textbf{同一个会话}里完成建工程、加文件、综合与布局布线，
否则生成脚本中的 \sig{import\_device} 参数为空：

\begin{lstlisting}[style=vsnip]
create_project -family eg4 -device EG4S20BG256 scope_eg4_59 .
add_files ...（35 个源文件 + SparkRoad.adc + SparkRoad.sdc）
top_module sparkroad_scope_top
launch_runs syn_1
wait_run syn_1
launch_runs phy_1
wait_run phy_1
\end{lstlisting}

\subsection{首次上板步骤}
'''
anchor = r'\subsection{上板步骤详解}'
assert anchor in s
s = s.replace(anchor, ins, 1)

s = s.replace('本机 TD 6.0.3 缺 EG4 器件库，尚未实际综合/上板。',
              '已在 TD 5.6.5 + EG4S20BG256 上完成综合/布局布线并生成比特流；尚未上板验证。')
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('ch19 results inserted')
