# -*- coding: utf-8 -*-
"""按锚点行插入注释块（初学者友好）。
spec = { path: [[anchor, [comment lines...]], ...] }
anchor: 去空白后以该字符串开头的行；可用 "anchor#n" 指定第 n 次出现(从 1 开始)。
"""
import io, json, sys

def annotate(path, items):
    lines = io.open(path, encoding='utf-8', newline='').read().split('\n')
    crlf = any(l.endswith('\r') for l in lines)
    lines = [l[:-1] if l.endswith('\r') else l for l in lines]
    inserts, missing = {}, []
    for anchor, comments in items:
        occ = 1
        if '#' in anchor:
            base, _, num = anchor.rpartition('#')
            if num.isdigit():
                anchor, occ = base, int(num)
        hits = [i for i, ln in enumerate(lines) if ln.strip().startswith(anchor)]
        if len(hits) < occ:
            missing.append('%s (want #%d, found %d)' % (anchor, occ, len(hits)))
            continue
        inserts.setdefault(hits[occ-1], []).extend(comments)
    out = []
    for i, ln in enumerate(lines):
        if i in inserts:
            out.extend(inserts[i])
        out.append(ln)
    nl = '\r\n' if crlf else '\n'
    io.open(path, 'w', encoding='utf-8', newline='').write(nl.join(out))
    return len(missing), missing

if __name__ == '__main__':
    spec = json.load(io.open(sys.argv[1], encoding='utf-8'))
    total = 0
    for path, items in spec.items():
        m, names = annotate(path, items)
        total += m
        print('%-32s blocks=%d missing=%d' % (path.split('/')[-1], len(items)-m, m))
        for n in names:
            print('    MISSING:', n)
    print('missing total =', total)
