#!/usr/bin/env bash
# =============================================================================
#  tools/lint.sh -- verilator 静态检查门禁（2026-11-02 建立）
#
#  环境坑（实测，已在本脚本里绕开）：
#    - oss-cad-suite 的 bin/verilator 是 Perl 包装脚本，本机 Perl 5.42 缺
#      Pod::Usage -> "Can't locate Pod/Usage.pm"；同目录 verilator_bin.exe
#      才是真正的二进制，直接调用即可。
#    - verilator_bin 的 VERILATOR_ROOT 编译期写死成构建机路径
#      (/yosyshq/share/verilator)，必须显式指向 oss-cad-suite/share/verilator，
#      否则报 "Cannot find verilated_std.sv"。
#
#  门禁策略：
#    BLOCK    = 必须零告警（当前只有 bpf_ctrl.v，2026-11-02 定点事故模块）
#    ADVISORY = 历史遗留宽度告警，只打印不阻塞（清完一个就挪进 BLOCK）
#
#  用法：
#    tools/lint.sh                      # 跑门禁
#    tools/lint.sh a.v b.v              # 指定文件全部按阻塞处理
#  返回：0 = 通过，1 = 阻塞项有告警，2 = 环境缺失
# =============================================================================
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUITE="${OSS_CAD_SUITE:-$ROOT/downloads/oss-cad-suite}"
BIN="$SUITE/bin/verilator_bin.exe"

if [ ! -x "$BIN" ]; then
    echo "找不到 verilator_bin: $BIN"
    echo "可用 OSS_CAD_SUITE 环境变量指定 oss-cad-suite 目录"
    exit 2
fi
export VERILATOR_ROOT="$SUITE/share/verilator"

if [ "$#" -gt 0 ]; then
    BLOCK="$*"
    ADVISORY=""
else
    BLOCK="$ROOT/FPGA/src/vga/app/bpf_ctrl.v"
    ADVISORY="$ROOT/FPGA/src/vga/app/bpf50.v \
$ROOT/FPGA/src/vga/app/decim512.v \
$ROOT/FPGA/src/eso.v \
$ROOT/FPGA/src/vga/abs/trace_layer.v \
$ROOT/FPGA/src/vga/app/scope_meas.v"
fi

echo "verilator: $("$BIN" --version 2>/dev/null | head -1)"

lint_one() {
    "$BIN" --lint-only -Wall \
        -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-VARHIDDEN -Wno-UNDRIVEN \
        "$1" 2>&1 | grep -E "Warning|Error" || true
}

rc=0
echo "== BLOCK =="
for f in $BLOCK; do
    out=$(lint_one "$f")
    if [ -n "$(echo "$out" | tr -d '[:space:]')" ]; then
        echo "FAIL $(basename "$f")"
        echo "$out"
        rc=1
    else
        echo "OK   $(basename "$f")"
    fi
done

if [ -n "$ADVISORY" ]; then
    echo "== ADVISORY (不阻塞，历史遗留) =="
    for f in $ADVISORY; do
        n=$(lint_one "$f" | grep -c "Warning" || true)
        if [ "$n" -gt 0 ]; then echo "warn $(basename "$f")  ($n 条)"; else echo "OK   $(basename "$f")"; fi
    done
fi

echo "LINT_RC=$rc"
exit $rc
