# -*- coding: utf-8 -*-
import io, re
p = r'C:/Users/Administrator/Desktop/task/doc/ch19_sparkroad.tex'
s = io.open(p, encoding='utf-8', newline='').read()
s = s.replace(r'\file{C:\\Anlogic\\TD\_5.6.5\_SP5\_170.155}', r'\file{C:/Anlogic/TD_5.6.5_SP5_170.155}')
s = s.replace(r'\file{C:\\Anlogic\\TD\_5.6.5\_SP5\_170.155\\license\\Anlogic.lic}', r'\file{C:/Anlogic/TD_5.6.5_SP5_170.155/license/Anlogic.lic}')
pat = re.compile(r'\\(sig|file)\{((?:[^{}]|\{[^{}]*\})*)\}')
def rep(m):
    body = m.group(2).replace('\\_','_').replace('\\{','{').replace('\\}','}')
    return '\\' + m.group(1) + '{' + body + '}'
s = pat.sub(rep, s)
io.open(p,'w',encoding='utf-8',newline='').write(s)
print('paths fixed')
