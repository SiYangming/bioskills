#!/usr/bin/env bash
# stringtie native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - stringtie 二进制【可选】：若已安装（conda activate stringtie-native / PATH 中有 stringtie），
#     会额外做 stringtie --version 冒烟；否则跳过真实执行。
# 说明：stringtie assemble 需要真实比对 BAM 才能产出 GTF，合成数据无法覆盖真实计算，
#      因此对 assemble/merge 采用「python 构造 argv 验证命令构建不崩溃」的断言方式；
#      fix_gtf 是纯 awk 文本修复，可真实执行并断言产物。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位 + 可真实修复的 GTF）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：assemble（nanoseq 长读模式默认参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StringtieSkill, build_parser
skill = StringtieSkill()
skill._resolve_binary = lambda: "/opt/env/bin/stringtie"
cmd = skill.build_command(
    "assemble", bam="$WORK/sample.sorted.bam", gtf="$WORK/sample.gtf",
    output="$WORK/sample.stringtie.gtf", label="sample1",
    min_transcript_len=200, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/stringtie" in s, s
assert "$WORK/sample.sorted.bam" in s, s
assert "-G $WORK/sample.gtf" in s, s
assert "-o $WORK/sample.stringtie.gtf" in s, s
assert "-l sample1" in s and "-m 200" in s and "-p 8" in s, s
assert "--conservative -L -R" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["assemble", "$WORK/sample.sorted.bam", "-G", "$WORK/sample.gtf",
     "-o", "$WORK/out.gtf", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser assemble")
PY

echo "==> [4/6] argv 构造验证 #2：merge"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StringtieSkill
skill = StringtieSkill()
skill._resolve_binary = lambda: "stringtie"
cmd = skill.build_command(
    "merge", gtf_list="$WORK/gtf_list.txt", gtf="$WORK/sample.gtf",
    output="$WORK/stringtie_merged_nonredundant.gtf", label="MSTRG",
    min_transcript_len=200, threads=4,
)
s = " ".join(cmd)
assert "stringtie --merge" in s, s
assert "-G $WORK/sample.gtf" in s, s
assert "-o $WORK/stringtie_merged_nonredundant.gtf" in s, s
assert "-l MSTRG" in s and "-m 200" in s, s
assert "$WORK/gtf_list.txt" in s, s
print("  OK:", s)
PY

echo "==> [5/6] fix_gtf 真实回归：坐标颠倒应被修复"
python "$NATIVE/main.py" fix_gtf "$WORK/sample.gtf" -o "$WORK/sample.fixed.gtf"
test -f "$WORK/sample.fixed.gtf"
grep -q $'chr1\ttest\texon\t100\t150' "$WORK/sample.fixed.gtf"
# 第二行原本 200/100 颠倒，修复后应为 start=100 end=200
grep -q $'chr1\ttest\texon\t100\t200' "$WORK/sample.fixed.gtf"
# 且修复后的行不再存在 start>end 的记录
if awk -F'\t' '$1 !~ /^#/ && $4 > $5 {bad++} END {exit bad>0 ? 1 : 0}' "$WORK/sample.fixed.gtf"; then
    echo '  OK: fix_gtf 修复后所有记录 $4<=$5'
else
    echo '  [FAIL] fix_gtf 仍存在 $4>$5 的记录' >&2
    exit 1
fi
echo "  OK: fix_gtf 坐标修复验证通过"

echo "==> [6/6] stringtie 冒烟（若已安装）"
if command -v stringtie >/dev/null 2>&1; then
    stringtie --version | head -n 1
else
    echo "  stringtie 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
