# -*- coding: utf-8 -*-
"""图形层数学验证: 用 Python 复现 RTL 的 y 映射 + 竖线连接, 输出 ASCII 预览"""
import math

H_VIS, PLOT_H = 640, 448
N = 640

# 测试波形: 三个周期的正弦 + 一段阶跃(模拟控制响应)
samples = []
for x in range(N):
    if x < 320:
        v = 512 + int(300 * math.sin(2 * math.pi * x / 160))
    else:
        v = 900 if x < 400 else 300
    samples.append(max(0, min(1023, v)))

def y_of(s):
    return (PLOT_H - 1) - ((s * 7) >> 4)

# 逐像素判定(与 trace_layer 相同)
img = [[0] * H_VIS for _ in range(PLOT_H)]
hits = 0
for x in range(1, H_VIS):
    s_now, s_prev = samples[x], samples[x-1]
    y0, y1 = y_of(s_now), y_of(s_prev)
    lo, hi = min(y0, y1), max(y0, y1)
    for y in range(lo, hi + 1):
        img[y][x] = 1
        hits += 1

# 叠加网格(y%64==0 / x%64==0)与零轴 y=224
for y in range(PLOT_H):
    for x in range(H_VIS):
        if y % 64 == 0 or x % 64 == 0:
            img[y][x] = 2
for x in range(H_VIS):
    img[224][x] = 3

# 降采样成 80x22 ASCII
SX, SY = 8, 20
chars = {0: ' ', 1: '#', 2: '.', 3: '-'}
print("ASCII 预览(80x22, 每字符=8x20 像素):")
for row in range(0, PLOT_H, SY):
    line = ''
    for col in range(0, H_VIS, SX):
        block = [img[y][x] for y in range(row, min(row+SY, PLOT_H))
                              for x in range(col, min(col+SX, H_VIS))]
        # 波形优先, 其次轴, 再网格
        c = 1 if 1 in block else (3 if 3 in block else (2 if 2 in block else 0))
        line += chars[c]
    print(line)

print()
print("命中像素数:", hits)
print("正弦峰值 y:", y_of(812), " 谷值 y:", y_of(212), " 中点 y:", y_of(512))
print("阶跃高 y:", y_of(900), " 低 y:", y_of(300))
