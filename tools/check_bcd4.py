# -*- coding: utf-8 -*-
"""模拟新 bcd.v 的 4 位双 dabble，验证 1023 -> 1023"""
def conv(data):
    bcd = 0  # 16 bit
    for i in range(10):
        # 四个半字节加 3 修正
        nb = bcd
        for j in range(4):
            d = (bcd >> (4*j)) & 0xF
            nd = d + 3 if d > 4 else d
            nb = (nb & ~(0xF << (4*j))) | ((nd & 0xF) << (4*j))
        bcd = nb
        bit = (data >> (9-i)) & 1
        bcd = ((bcd << 1) | bit) & 0xFFFF
    return bcd

for v in (0, 1, 9, 10, 99, 100, 999, 1000, 1023):
    b = conv(v)
    d = [(b >> 12) & 0xF, (b >> 8) & 0xF, (b >> 4) & 0xF, b & 0xF]
    print('%4d -> %d%d%d%d  %s' % (v, d[0], d[1], d[2], d[3], 'OK' if int(''.join(map(str,d))) == v else 'FAIL'))
