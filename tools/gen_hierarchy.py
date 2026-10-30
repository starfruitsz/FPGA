# -*- coding: utf-8 -*-
"""生成 Verilog 模块层次树（Mermaid + ASCII + 表），供 VS Code 阅读/预览。"""
import io, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else r'C:/Users/Administrator/Desktop/task/FPGA/src'
OUT  = sys.argv[2] if len(sys.argv) > 2 else r'C:/Users/Administrator/Desktop/task/HIERARCHY.md'
TOP  = 'sparkroad_scope_top'

def strip_code(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    t = re.sub(r'//[^\n]*', ' ', t)
    t = re.sub(r'"(?:[^"\\]|\\.)*"', '""', t)
    return t

files = []
for r, ds, fs in os.walk(ROOT):
    ds[:] = [d for d in ds if not d.startswith('_') and d not in ('src_original_backup',)]
    for f in fs:
        if f.endswith('.v'):
            files.append(os.path.join(r, f))
files.sort()

mods = {}
for p in files:
    src = strip_code(io.open(p, encoding='utf-8', errors='replace').read())
    for m in re.finditer(r'\bmodule\s+(\w+)', src):
        name = m.group(1)
        mods.setdefault(name, {'file': os.path.relpath(p, os.path.dirname(ROOT)).replace('\\','/'),
                               'children': [], 'parents': set()})

for p in files:
    src = strip_code(io.open(p, encoding='utf-8', errors='replace').read())
    for m in re.finditer(r'\bmodule\s+(\w+)(.*?)\bendmodule', src, re.S):
        mname, body = m.group(1), m.group(2)
        body = re.sub(r'\bmodule\s+\w+.*?\bendmodule', ' ', body, flags=re.S)
        for t in mods:
            if t == mname:
                continue
            for im in re.finditer(r'(?m)^\s*' + re.escape(t) + r'\s*(?:#\s*\([^;]*?\)\s*)?(\w+)\s*\(', body):
                inst = im.group(1)
                if inst in ('begin','if','else','case','for','while','always','assign'):
                    continue
                mods[mname]['children'].append((t, inst))
                mods[t]['parents'].add((mname, inst))

def tree(name, depth=0, seen=None, out=None):
    if seen is None: seen = set()
    if out is None: out = []
    out.append('  ' * depth + ('+-- ' if depth else '') + name + '  (' + os.path.basename(mods[name]['file']) + ')')
    if name in seen:
        out.append('  ' * (depth+1) + '(递归/重复引用)')
        return out
    seen.add(name)
    for t, inst in mods[name]['children']:
        out.append('  ' * (depth+1) + '|  [' + inst + ']')
        tree(t, depth+2, seen, out)
    seen.discard(name)
    return out

lines = []
lines.append('# Verilog 模块层次树')
lines.append('')
lines.append('> 由 `tools/gen_hierarchy.py` 自动生成；在 VS Code 中打开本文件，')
lines.append('> 按 Ctrl+Shift+V 预览（安装 Markdown Preview Mermaid Support 可渲染下图）。')
lines.append('')
lines.append('生成命令：python tools/gen_hierarchy.py（默认根目录 FPGA/src）。')
lines.append('')
lines.append('## 1. Mermaid 层次图（从 ' + TOP + ' 开始）')
lines.append('')
lines.append('```mermaid')
lines.append('graph TD')
lines.append('  ' + TOP + '["' + TOP + '"]')
seen_edges = set()
def walk(n, seen=None):
    if seen is None: seen = set()
    if n in seen: return
    seen.add(n)
    for t, inst in mods[n]['children']:
        key = (n, t, inst)
        if key in seen_edges: continue
        seen_edges.add(key)
        lines.append('  ' + n + ' -->|' + inst + '| ' + t)
        walk(t, seen)
walk(TOP)
lines.append('```')
lines.append('')
lines.append('## 2. ASCII 树')
lines.append('')
lines.append('```')
for l in tree(TOP):
    lines.append(l)
lines.append('```')
lines.append('')
lines.append('## 3. 模块清单')
lines.append('')
lines.append('| 模块 | 文件 | 例化父模块 | 子模块数 |')
lines.append('|---|---|---|---|')
for name in sorted(mods):
    parents = ', '.join(sorted(set(p for p, _ in mods[name]['parents']))) or '-'
    lines.append('| ' + name + ' | ' + mods[name]['file'] + ' | ' + parents + ' | ' + str(len(mods[name]['children'])) + ' |')
lines.append('')
io.open(OUT, 'w', encoding='utf-8', newline='').write('\n'.join(lines) + '\n')
print('modules:', len(mods), '->', OUT)
print('top children:', len(mods[TOP]['children']))
