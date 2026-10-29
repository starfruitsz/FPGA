# -*- coding: utf-8 -*-
"""由 pins/scope_pins.csv 生成 Gowin 物理约束 .cst（IO 列表初始化配置）"""
import io, os

HERE = os.path.dirname(os.path.abspath(__file__))
CSV  = os.path.join(HERE, 'scope_pins.csv')
OUT  = os.path.join(HERE, 'project_2025_11_07_scope.cst')

def parse(path):
    rows = []
    with io.open(path, 'r', encoding='utf-8') as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            parts = [p.strip() for p in s.split(',')]
            if len(parts) < 6:
                print('WARN line %d: 列数不足 -> %s' % (ln, s))
                continue
            port, pin, dr, drive, pull, vccio = parts[:6]
            note = parts[6] if len(parts) > 6 else ''
            rows.append(dict(port=port, pin=pin, dir=dr, drive=drive,
                             pull=pull, vccio=vccio, note=note))
    return rows

def main():
    rows = parse(CSV)
    out = []
    out.append('// ==========================================================================')
    out.append('// project_2025_11_07_scope.cst   [由 pins/gen_cst.py 自动生成, 勿手改]')
    out.append('// 来源: pins/scope_pins.csv   (共 %d 个端口)' % len(rows))
    out.append('// 用法: python gen_cst.py；或把本文件内容合并进原工程 .cst')
    out.append('// ==========================================================================')
    out.append('')
    seen = set()
    for r in rows:
        if r['port'] in seen:
            print('WARN 重复端口: %s' % r['port'])
        seen.add(r['port'])
        if r['note']:
            out.append('// %s' % r['note'])
        out.append('IO_LOC "%s" %s;' % (r['port'], r['pin']))
        if r['dir'] == 'out':
            out.append('IO_PORT "%s" PULL_MODE=%s DRIVE=%s BANK_VCCIO=%s;'
                       % (r['port'], r['pull'], r['drive'], r['vccio']))
        else:
            out.append('IO_PORT "%s" PULL_MODE=%s BANK_VCCIO=%s;'
                       % (r['port'], r['pull'], r['vccio']))
    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    print('OK  %d ports -> %s' % (len(rows), OUT))

if __name__ == '__main__':
    main()
