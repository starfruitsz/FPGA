# -*- coding: utf-8 -*-
"""bpf_ctrl 位精确参考模型（Python）

用途：Icarus 14 (devel s20260301) 对 "32bit 有符号 * 64bit 有符号" 会段错误，
      没法给 bpf_ctrl 写 testbench，所以用这个模型做等价验证：
      逐拍复现 bpf_ctrl.v 的定点运算（含 32bit 回卷、算术/逻辑右移），
      输入 78 点/周期的 48Hz 正弦（幅度 ±100 码），检查输出：

        正确：pp ≈ 200（中心增益 1.0），波形平滑
        2026-11-02 修复前的 bug（qb_64 少写 $signed）：pp = 595，
               输出在 214/809 两个电平之间跳 —— 就是用户看到的"开关信号"方波

运行： python tools/bpf_model.py
返回码：0 = 通过，1 = 失败
"""
import math
import sys

F_Q24 = 822350          # 2*sin(pi*48/6152.34)  Q24
Q_Q16 = 27307           # 1/Q, Q16 (Q = 2.4)
M64 = (1 << 64) - 1
FS = 6152.34            # decim512 之后的采样率
AMP = 100               # 输入幅度（码）
N = 12000


def s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def s64(v):
    v &= M64
    return v - (1 << 64) if v & (1 << 63) else v


def run(fix=True):
    band = 0
    low = 0
    out = []
    for n in range(N):
        din = 512 + int(round(AMP * math.sin(2.0 * math.pi * 48.0 * n / FS)))
        x_q16 = s32((din - 512) << 16)
        t1 = s32(s64(band * F_Q24) >> 24)                 # f*band
        low_n = s32(low + t1)
        if fix:
            qb = s32((band * Q_Q16) >> 16)                # 有符号乘法 + 算术右移
        else:
            qb = s32((((band & 0xFFFFFFFF) * Q_Q16) & M64) >> 16)   # 旧 bug
        high = s32(x_q16 - low_n - qb)
        t3 = s32(s64(high * F_Q24) >> 24)                 # f*high
        band_n = s32(band + t3)
        yq = s32(s64(band_n * Q_Q16) >> 32)               # 归一化 1/Q
        y = yq + 512
        y = 1023 if y > 1023 else (0 if y < 0 else y)
        out.append(y)
        low = low_n
        band = band_n
    seg = out[2000:]
    return min(seg), max(seg), max(seg) - min(seg), seg


def main():
    lo, hi, pp, seg = run(fix=True)
    lo_b, hi_b, pp_b, _ = run(fix=False)
    print("输入: 48Hz 正弦, 幅度 +-%d 码 (pp=%d)" % (AMP, 2 * AMP))
    print("修复后: min=%d max=%d pp=%d   -> 增益 %.2f" % (lo, hi, pp, pp / float(2 * AMP)))
    print("修复前: min=%d max=%d pp=%d   (bug: 负半周被破坏, 输出在两端跳)" % (lo_b, hi_b, pp_b))
    # 中心增益应为 1.0（pp 在 ±10% 内），且不能出现"两电平来回跳"
    ok = abs(pp - 2 * AMP) <= 0.10 * 2 * AMP and pp < 300
    print("判定:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
