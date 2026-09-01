#!/usr/bin/env bash
# flair native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - flair 二进制【可选】：若已安装（conda activate flair-native / PATH 中有 flair），
#     会额外做 flair --version 冒烟；否则跳过真实执行。
# 说明：flair collapse 需要真实 long-read 数据才能产出结果，合成数据无法覆盖真实计算，
#      因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：bam2bed12"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FlairSkill, build_parser
skill = FlairSkill()
skill._resolve_subcommand_bin = lambda sc: "/opt/env/bin/bam2Bed12"
cmd = skill.build_command("bam2bed12", input="$WORK/sample.sorted.bam", threads=4)
s = " ".join(cmd)
assert "/opt/env/bin/bam2Bed12" in s, s
assert "-i $WORK/sample.sorted.bam" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(["bam2bed12", "-i", "$WORK/sample.sorted.bam", "-o", "$WORK/sample.bed12", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "bam2bed12" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser bam2bed12")
PY

echo "==> [4/6] argv 构造验证 #2：annotate"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FlairSkill
skill = FlairSkill()
skill._resolve_subcommand_bin = lambda sc: "identify_gene_isoform"
cmd = skill.build_command("annotate", input="$WORK/sample.bed12", gtf="$WORK/sample.gtf", output="$WORK/sample.annotated.bed")
s = " ".join(cmd)
assert "identify_gene_isoform" in s, s
assert "$WORK/sample.bed12" in s and "$WORK/sample.gtf" in s and "$WORK/sample.annotated.bed" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：collapse（nanoseq 默认参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FlairSkill
skill = FlairSkill()
skill._resolve_subcommand_bin = lambda sc: "/opt/env/bin/flair"
cmd = skill.build_command(
    "collapse",
    annotated_bed="$WORK/sample.annotated.bed", genome="$WORK/sample.fa",
    reads="$WORK/sample.fastq.gz", prefix="$WORK/out/sample",
    gtf="$WORK/sample.gtf", min_support=3, end_window=100,
    intpriming_threshold=30, threads=8, mm2_args="-I8g,--MD",
)
s = " ".join(cmd)
assert "flair collapse" in s, s
assert "-q $WORK/sample.annotated.bed" in s, s
assert "-g $WORK/sample.fa" in s, s
assert "-r $WORK/sample.fastq.gz" in s, s
assert "-o $WORK/out/sample" in s, s
assert "-f $WORK/sample.gtf" in s, s
assert "-s 3" in s and "-w 100" in s, s
assert "--intprimingthreshold 30" in s, s
assert "--trust_ends --remove_internal_priming --stringent --check_splice" in s, s
assert "--mm2_args -I8g,--MD" in s and "--quiet" in s, s
assert "-t 8" in s, s
print("  OK:", s)
PY

echo "==> [6/6] flair 冒烟（若已安装）"
if command -v flair >/dev/null 2>&1; then
    flair --version | head -n 1
else
    echo "  flair 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
