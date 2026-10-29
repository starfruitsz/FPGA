# -*- coding: utf-8 -*-
"""在指定行号之前插入注释块（保留原文件行尾风格）。"""
import io, json, sys

def apply(path, inserts):
    with io.open(path, 'r', encoding='utf-8', newline='') as f:
        raw = f.read()
    crlf = '\r\n' in raw
    lines = raw.split('\n')
    # 去掉行尾 \r 便于处理
    stripped = [l[:-1] if l.endswith('\r') else l for l in lines]
    out = []
    for i, ln in enumerate(stripped, start=1):
        for c in inserts.get(str(i), []):
            out.append(c)
        out.append(ln)
    for c in inserts.get('END', []):
        out.append(c)
    nl = '\r\n' if crlf else '\n'
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(nl.join(out))
    return len(out), crlf

if __name__ == '__main__':
    spec = json.load(io.open(sys.argv[1], 'r', encoding='utf-8'))
    for path, ins in spec.items():
        n, crlf = apply(path, ins)
        print('OK %s -> %d lines (crlf=%s)' % (path, n, crlf))
