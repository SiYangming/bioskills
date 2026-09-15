#!/usr/bin/env bash
# ea-utils native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - fastq-join / fastq-mcf / fastq-stats / fastq-clipper【可选】：若 PATH 中存在
#     （conda activate ea-utils / 官方容器内），追加真实执行断言；否则跳过真实执行，
#     仅做 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成 paired FASTQ + 接头）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：join（fastq-join）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EaUtilsSkill, build_parser, BINARY_BY_SUBCOMMAND
skill = EaUtilsSkill()
skill._resolve_binary_for = lambda sub: f"/opt/env/bin/{BINARY_BY_SUBCOMMAND[sub]}"
cmd = skill.build_command(
    "join", read1="$WORK/r1.fastq", read2="$WORK/r2.fastq",
    output="$WORK/out.", min_overlap=6, pct_diff=8, verify=" ", threads=1,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/fastq-join", cmd
assert "$WORK/r1.fastq" in s and "$WORK/r2.fastq" in s, s
assert "-o $WORK/out." in s and "-m 6" in s and "-p 8" in s, s
assert "-v" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["join", "$WORK/r1.fastq", "$WORK/r2.fastq", "-o", "$WORK/out.", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "join" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser join")
PY

echo "==> [4/6] argv 构造验证 #2：mcf / stats / clipper"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EaUtilsSkill, BINARY_BY_SUBCOMMAND
skill = EaUtilsSkill()
skill._resolve_binary_for = lambda sub: f"/opt/env/bin/{BINARY_BY_SUBCOMMAND[sub]}"

mcf = skill.build_command(
    "mcf", adapters="$WORK/adapters.fa", reads=["$WORK/r1.fastq", "$WORK/r2.fastq"],
    output=["$WORK/clean1.fq", "$WORK/clean2.fq"], qual=30, min_len=50, pct_diff=10, threads=1,
)
s = " ".join(mcf)
assert mcf[0] == "/opt/env/bin/fastq-mcf", mcf
assert "-o $WORK/clean1.fq" in s and "-o $WORK/clean2.fq" in s, s
assert "-q 30" in s and "-l 50" in s and "-p 10" in s, s
assert s.rstrip().endswith("$WORK/adapters.fa $WORK/r1.fastq $WORK/r2.fastq"), s
print("  OK:", s)

stats = skill.build_command("stats", reads="$WORK/single.fastq", per_base="$WORK/pb.tsv", no_dups=True, threads=1)
s = " ".join(stats)
assert stats[0] == "/opt/env/bin/fastq-stats", stats
assert "-x $WORK/pb.tsv" in s and "-D" in s and s.rstrip().endswith("$WORK/single.fastq"), s
print("  OK:", s)

clip = skill.build_command("clipper", input="$WORK/single.fastq", adapters="AGATCGGAAGAGC", output="$WORK/clipped.fastq", pct_diff=10, threads=1)
s = " ".join(clip)
assert clip[0] == "/opt/env/bin/fastq-clipper", clip
assert "-o $WORK/clipped.fastq" in s and s.rstrip().endswith("$WORK/single.fastq AGATCGGAAGAGC"), s
print("  OK:", s)
PY

echo "==> [5/6] 真实执行（fastq-join / fastq-clipper 若已安装）"
if command -v fastq-join >/dev/null 2>&1; then
    python "$NATIVE/main.py" join "$WORK/r1.fastq" "$WORK/r2.fastq" -o "$WORK/joined." || true
    test -f "$WORK/joined.join"
    grep -q '^@' "$WORK/joined.join"
    echo "  OK: fastq-join 真实拼接产物 joined.join"
else
    echo "  fastq-join 未安装，跳过真实拼接（argv 构造验证已通过）"
fi
if command -v fastq-clipper >/dev/null 2>&1; then
    python "$NATIVE/main.py" clipper "$WORK/single.fastq" AGATCGGAAGAGC -o "$WORK/clipped.fastq"
    test -s "$WORK/clipped.fastq"
    echo "  OK: fastq-clipper 真实切除产物 clipped.fastq"
else
    echo "  fastq-clipper 未安装，跳过真实切除（argv 构造验证已通过）"
fi

echo "==> [6/6] 冒烟（若已安装）"
if command -v fastq-mcf >/dev/null 2>&1; then
    fastq-mcf -h 2>&1 | grep -i version | head -n 1 || true
else
    echo "  ea-utils 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
