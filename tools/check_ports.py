# -*- coding: utf-8 -*-
"""Verilog 端口连接静态检查: 实例化里的 .port 必须存在于被例化模块的端口表"""
import io, os, re, sys

ROOT = r'C:/Users/Administrator/Desktop/task/FPGA/src'
DIRS = [ROOT, os.path.join(ROOT,'adc'), os.path.join(ROOT,'adc','hal'),
        os.path.join(ROOT,'adc','abs'), os.path.join(ROOT,'vga'), os.path.join(ROOT,'vga','hal'),
        os.path.join(ROOT,'vga','abs'), os.path.join(ROOT,'vga','app')]

files = {}
for d in DIRS:
    if not os.path.isdir(d): continue
    for f in os.listdir(d):
        if f.endswith('.v'):
            p = os.path.join(d, f)
            files[p] = io.open(p, encoding='utf-8').read()

def find_match(s, i):
    """s[i]=='(' 返回匹配的 ')' 下标"""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(': depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0: return j
    return -1

mod_ports = {}
for p, src in files.items():
    for m in re.finditer(r'\bmodule\s+(\w+)', src):
        name = m.group(1)
        i = m.end()
        # 跳过 #( ... )
        while i < len(src) and src[i] in ' \t\r\n': i += 1
        if i < len(src) and src[i] == '#':
            while i < len(src) and src[i] != '(': i += 1
            j = find_match(src, i)
            if j < 0: continue
            i = j + 1
            while i < len(src) and src[i] in ' \t\r\n': i += 1
        if i >= len(src) or src[i] != '(':
            continue
        j = find_match(src, i)
        body = src[i+1:j]
        # 去注释
        body = re.sub(r'//[^\n]*', ' ', body)
        body = re.sub(r'/\*.*?\*/', ' ', body, flags=re.S)
        ports = []
        # 按顶层逗号切分
        parts, depth, cur = [], 0, ''
        for ch in body:
            if ch in '([{': depth += 1
            if ch in ')]}': depth -= 1
            if ch == ',' and depth == 0:
                parts.append(cur); cur = ''
            else:
                cur += ch
        parts.append(cur)
        for part in parts:
            part = part.strip()
            if not part: continue
            mm = re.match(r'(input|output|inout)\b', part)
            if not mm: continue
            # 去掉方向/类型/位宽, 取最后标识符
            ids = re.findall(r'[A-Za-z_]\w*', part)
            if ids:
                ports.append(ids[-1])
        mod_ports.setdefault(name, set()).update(ports)

bad = 0
checked = 0
for p, src in files.items():
    s = re.sub(r'//[^\n]*', ' ', src)
    s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S)
    for mname, ports in mod_ports.items():
        for m in re.finditer(r'\b' + mname + r'\b', s):
            # 实例化形式: NAME [#(...)] inst ( ... ) ;
            i = m.end()
            while i < len(s) and s[i] in ' \t\r\n': i += 1
            if i < len(s) and s[i] == '#':
                while i < len(s) and s[i] != '(': i += 1
                j = find_match(s, i)
                if j < 0: continue
                i = j + 1
                while i < len(s) and s[i] in ' \t\r\n': i += 1
            mi = re.match(r'([A-Za-z_]\w*)\s*\(', s[i:])
            if not mi: continue
            inst = mi.group(1)
            if inst in ('input','output','inout','wire','reg'): continue
            lp = i + mi.end() - 1
            rp = find_match(s, lp)
            if rp < 0: continue
            body = s[lp+1:rp]
            if '.'.encode().decode() not in ['.']:
                pass
            named = re.findall(r'\.\s*([A-Za-z_]\w*)\s*\(', body)
            if not named: continue
            checked += 1
            for pt in named:
                if pt not in ports:
                    bad += 1
                    print('PORT MISMATCH  %-34s -> %s.%s  (module %s ports: %s)'
                          % (os.path.basename(p), inst, pt, mname, ','.join(sorted(ports))[:80]))

print('modules:', len(mod_ports), ' instantiations checked:', checked, ' bad ports:', bad)
