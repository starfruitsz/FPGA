# -*- coding: utf-8 -*-
"""把 adda_pins.csv 里的 24 脚并口 AD/DA 引脚写进 FPGA_TD/eg4/SparkRoad.adc。

用法:
    python tools/gen_adda_pins.py            # 写入项目默认 .adc
    python tools/gen_adda_pins.py --dry-run  # 只打印，不改文件

约定:
  * csv 每行 "信号,引脚[,说明]"，引脚留空则跳过（保持未约束，TD 会自动乱放）
  * .adc 中该段由下面的 MARK 标记围起来，重复运行只替换这一段
"""
import csv, io, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "FPGA", "src", "adc", "pins", "adda_pins.csv")
ADC_PATH = os.path.join(ROOT, "FPGA_TD", "eg4", "SparkRoad.adc")
MARK_BEGIN = "#### 并口 AD/DA 24 脚模块（由 tools/gen_adda_pins.py 生成，勿手改本段）"
MARK_END = "#### 并口 AD/DA 段结束"


def load_pins():
    pins, missing = [], []
    with io.open(CSV_PATH, encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0].lstrip().startswith("#"):
                continue
            name = row[0].strip()
            pin = row[1].strip() if len(row) > 1 else ""
            if not pin:
                missing.append(name)
                continue
            pins.append((name, pin))
    return pins, missing


def main():
    pins, missing = load_pins()
    if missing:
        print("!! 以下信号未填引脚，跳过: " + ", ".join(missing))
    if not pins:
        print("没有可用引脚，退出（请先填 FPGA/src/adc/pins/adda_pins.csv）")
        return 1

    block = [MARK_BEGIN]
    for name, pin in pins:
        block.append("set_pin_assignment {%s} { LOCATION = %s; IOSTANDARD = LVCMOS33; }" % (name, pin))
    block.append(MARK_END)
    block_txt = "\n".join(block)

    if "--dry-run" in sys.argv:
        print(block_txt)
        return 0

    text = io.open(ADC_PATH, encoding="utf-8", newline="").read()
    if MARK_BEGIN in text:
        head, rest = text.split(MARK_BEGIN, 1)
        tail = rest.split(MARK_END, 1)[1] if MARK_END in rest else ""
        text = head + block_txt + tail
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + block_txt + "\n"

    io.open(ADC_PATH, "w", encoding="utf-8", newline="").write(text)
    print("已写入 %d 条引脚 -> %s" % (len(pins), ADC_PATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
