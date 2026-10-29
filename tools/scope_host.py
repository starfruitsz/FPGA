#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scope_host.py -- 简易示波器上位机（PC 端 MVP）

功能:
  * 从串口读取 FPGA 上报的 2 字节帧（先低字节、后高字节），还原 10bit AD 码值
  * 实时滚动显示最近 N 点波形（需要 matplotlib）
  * 可选保存 CSV，便于事后分析
  * 不发任何命令，只做"只读监听"；FPGA 端默认每 26ms 上报一帧

用法:
  python scope_host.py --port COM3 --baud 115200
  python scope_host.py --port COM3 --csv capture.csv --window 640
  python scope_host.py --port COM3 --no-plot        # 只记录

依赖:
  pip install pyserial matplotlib
"""
import argparse
import csv
import sys
import time
from collections import deque

try:
    import serial
except ImportError:
    serial = None


def parse_frames(buf, window, verbose=False):
    """把字节流切成一帧 2 字节: 低字节在前、高字节在后。"""
    vals = []
    for i in range(0, len(buf) - 1, 2):
        lo, hi = buf[i], buf[i + 1]
        v = lo | ((hi & 0x03) << 8)      # AD 只有 10bit，高字节忽略 bit3..7
        vals.append(v)
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM3")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--window", type=int, default=640, help="显示点数")
    ap.add_argument("--csv", default="", help="保存到 CSV 文件")
    ap.add_argument("--no-plot", action="store_true")
    ap.add_argument("--seconds", type=float, default=0, help="0=一直运行")
    args = ap.parse_args()

    if serial is None:
        print("缺少 pyserial: pip install pyserial", file=sys.stderr)
        return 1

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except Exception as e:
        print("打开串口失败:", e, file=sys.stderr)
        return 1

    data = deque(maxlen=args.window)
    f = None
    writer = None
    if args.csv:
        f = open(args.csv, "w", newline="", encoding="utf-8")
        writer = csv.writer(f)
        writer.writerow(["index", "value"])

    plot = not args.no_plot
    if plot:
        try:
            import matplotlib.pyplot as plt
        except ImportError:
            print("没有 matplotlib，改为纯文本模式", file=sys.stderr)
            plot = False

    if plot:
        plt.ion()
        fig, ax = plt.subplots(figsize=(9, 3.5))
        ax.set_ylim(0, 1023)
        ax.set_xlim(0, args.window)
        ax.set_ylabel("AD code")
        ax.set_title("FPGA scope UART monitor")
        line, = ax.plot([], [], lw=0.8)

    n = 0
    t0 = time.time()
    try:
        while True:
            chunk = ser.read(64)
            if not chunk:
                continue
            for v in parse_frames(chunk, args.window):
                data.append(v)
                n += 1
                if writer:
                    writer.writerow([n, v])
            if plot and len(data) >= args.window:
                line.set_data(range(len(data)), list(data))
                fig.canvas.draw_idle()
                fig.canvas.flush_events()
            if args.seconds and (time.time() - t0) > args.seconds:
                break
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        if f:
            f.close()
        print("收到 %d 个采样点" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
