#!/usr/bin/env bash
# isoseq3 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - isoseq3 二进制【可选】：若已安装（conda activate isoseq3-native / PATH 中有 isoseq3），
#     会额外做 isoseq3 refine --version 冒烟；否则跳过真实执行。
# 说明：isoseq3 refine 需要 lima 清理后的有效 ccs BAM 才能产出结果，合成数据无法覆盖
#      真实计算，因此本脚本对 refine 子命令采用「python 构造 argv 验证命令构建不崩溃」。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小 BAM + primers.fasta）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/in.bam"
grep -q "NEB_5p" "$WORK/primers.fasta"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：refine 默认（--require-polya）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IsoSeq3Skill
skill = IsoSeq3Skill()
skill._resolve_binary = lambda: "/opt/env/bin/isoseq3"  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "refine", bam="$WORK/in.bam", primers="$WORK/primers.fasta",
    outdir="$WORK/out1", prefix="sample", threads=4,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/isoseq3 refine"), s
assert "-j 4" in s, s
assert "--require-polya" in s, s
assert "$WORK/out1/sample.bam" in s, s
assert "$WORK/in.bam $WORK/primers.fasta" in s, s
print("  OK:", s)
PY

echo "==> [4/5] argv 构造验证 #2：refine 关闭 polya + 自定义输出"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IsoSeq3Skill, build_parser
skill = IsoSeq3Skill()
skill._resolve_binary = lambda: "isoseq3"
cmd = skill.build_command(
    "refine", bam="$WORK/in.bam", primers="$WORK/primers.fasta",
    output="$WORK/out2/final.bam", require_polya=False,
    min_polya_length=20, threads=2,
)
s = " ".join(cmd)
assert "--require-polya" not in s, s
assert "--min-polya-length 20" in s, s
assert "-j 2" in s, s
assert "$WORK/out2/final.bam" in s, s
ns = build_parser().parse_args(
    ["refine", "--bam", "$WORK/in.bam", "--primers", "$WORK/primers.fasta",
     "--outdir", "$WORK/out3", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "refine" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK:", s)
PY

echo "==> [5/5] isoseq3 冒烟（若已安装）"
if command -v isoseq3 >/dev/null 2>&1; then
    isoseq3 refine --version | head -n 1
else
    echo "  isoseq3 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
