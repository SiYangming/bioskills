#!/usr/bin/env bash
# fastp native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - fastp 二进制【可选】：若已安装（conda activate fastp-native / PATH 中可见），
#     会额外做 --version 冒烟；否则跳过真实执行，退化为 argv 构造验证。
# 说明：合成 FASTQ 无法覆盖真实计算，因此对 run 子命令采用
#       「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成双端 FASTQ.gz，含 3' 接头）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "run"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run 双端全参数（-i/-I/-o/-O/-h/-j + QC/接头参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastpSkill, THREAD_FLAG
skill = FastpSkill()
skill._resolve_binary = lambda: "/opt/env/bin/fastp"  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "run",
    in1="$WORK/R1.fq.gz", in2="$WORK/R2.fq.gz",
    out1="$WORK/out1.fq.gz", out2="$WORK/out2.fq.gz",
    html="$WORK/report.html", json="$WORK/report.json",
    adapter_sequence="AGATCGGAAGAGCACACGTCTGA",
    detect_adapter_for_pe=True,
    qualified_quality_phred=20, unqualified_percent_limit=30, length_required=50,
    threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/fastp"), s
assert "-i $WORK/R1.fq.gz" in s, s
assert "-I $WORK/R2.fq.gz" in s, s
assert "-o $WORK/out1.fq.gz" in s, s
assert "-O $WORK/out2.fq.gz" in s, s
assert "-h $WORK/report.html" in s, s
assert "-j $WORK/report.json" in s, s
assert f"{THREAD_FLAG} 8" in s, s
assert "--adapter_sequence AGATCGGAAGAGCACACGTCTGA" in s, s
assert "--detect_adapter_for_pe" in s, s
assert "-q 20" in s and "-u 30" in s and "-l 50" in s, s
print("  OK:", s)
PY

echo "==> [4/5] argv 构造验证 #2：run 单端最小参数 + 缺参报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastpSkill
skill = FastpSkill()
skill._resolve_binary = lambda: "fastp"
cmd = skill.build_command(
    "run",
    in1="$WORK/R1.fq.gz", out1="$WORK/se.fq.gz",
    html="$WORK/se.html", json="$WORK/se.json",
    threads=4,
)
s = " ".join(cmd)
assert "-I" not in s and "-O" not in s, s
assert "-i $WORK/R1.fq.gz" in s and "-o $WORK/se.fq.gz" in s, s
assert "-h $WORK/se.html" in s and "-j $WORK/se.json" in s, s
# fastp 0.20+ 线程 flag 必须是 -w（-t 已被 --trim_tail1 占用）
assert "-w 4" in s and "-t " not in s, s
print("  OK:", s)
PY
echo "  -> 缺参报错（run 缺少 -i 应非零退出）："
if python "$NATIVE/main.py" run -o "$WORK/x.fq.gz" >/dev/null 2>&1; then
    echo "[FAIL] 缺 -i 参数时应报错退出" >&2
    exit 1
fi
echo "  OK: 缺 -i 参数正确报错"

echo "==> [5/5] 二进制冒烟（若已安装）"
if command -v fastp >/dev/null 2>&1; then
    fastp --version | head -n 1
else
    echo "  fastp 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
