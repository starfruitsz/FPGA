
def dabble(data, bits=10):
    bcd = 0   # 12-bit
    rows = []
    for i in range(bits):
        # 加3修正: 三个BCD位
        digits = [(bcd >> (4*j)) & 0xF for j in range(3)]
        corr = []
        newbcd = bcd
        for j in range(3):
            d = digits[j]
            nd = d + 3 if d > 4 else d
            newbcd = (newbcd & ~(0xF << (4*j))) | ((nd & 0xF) << (4*j))
        corr.append((digits, [( (newbcd >> (4*j)) & 0xF) for j in range(3)]))
        bcd = newbcd
        # 左移并入下一bit
        bit = (data >> (bits-1-i)) & 1
        bcd = ((bcd << 1) | bit) & 0xFFF
        rows.append((i+1, bit, bcd))
    return rows

for val in (753, 1023):
    print('value', val, bin(val))
    rows = dabble(val)
    for r in rows:
        print('  step %2d bit=%d bcd=%04X -> %d%d%d' % (r[0], r[1], r[2], (r[2]>>8)&0xF, (r[2]>>4)&0xF, r[2]&0xF))
