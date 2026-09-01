#!/usr/bin/env bash
# orffinder native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ORFfinder 二进制【可选】：若已安装（conda activate orffinder-native / PATH 中可见），
#     会额外做 -version 冒烟；否则跳过真实执行。
# 说明：ORFfinder 需要真实核酸序列才能产出 ORF，合成数据无法覆盖真实计算，
#      因此本脚本对 run 子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成核酸 FASTA）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "run"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：run 默认 outfmt=2（Text ASN.1，自动输出路径）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrffinderSkill, SUFFIX_MAP
skill = OrffinderSkill()
skill._resolve_bin = lambda: "/opt/env/bin/ORFfinder"  # 不真实执行，仅验证构建
cmd = skill.build_command("run", input="$WORK/transcripts.fa")
s = " ".join(cmd)
assert "/opt/env/bin/ORFfinder" in s, s
assert "-in $WORK/transcripts.fa" in s, s
assert "-out $WORK/transcripts.asn1" in s, s   # outfmt=2 默认 -> .asn1
assert "-outfmt 2" in s, s
# 默认不注入 -s/-ml（用户未显式给出）
assert "-s" not in s and "-ml" not in s, s
assert SUFFIX_MAP[2] == ".asn1", SUFFIX_MAP
print("  OK:", s)
PY

echo "==> [4/6] argv 构造验证 #2：run 显式 outfmt=0 + 结构化参数"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrffinderSkill
skill = OrffinderSkill()
skill._resolve_bin = lambda: "ORFfinder"
cmd = skill.build_command(
    "run", input="$WORK/transcripts.fa", outfmt=0,
    genetic_code=1, start_codon=2, min_length=30,
    strand="plus", ignore_nested=True,
)
s = " ".join(cmd)
assert "-outfmt 0" in s, s
assert "-out $WORK/transcripts_orf.fa" in s, s   # outfmt=0 -> _orf.fa
assert "-g 1" in s, s
assert "-s 2" in s, s
assert "-ml 30" in s, s
assert "-strand plus" in s, s
assert "-n true" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：parser 可解析完整 argv（子命令后 --threads/--tmpdir）+ gz 输入"
python3 - <<PY
import sys, gzip, os
sys.path.insert(0, "$NATIVE")
from main import OrffinderSkill, build_parser
# gz 输入应被解压到 tmpdir
with gzip.open("$WORK/transcripts.fa.gz", "wt", encoding="utf-8") as fh:
    fh.write(">tx1\nATGGCTGTTGATGCATTGCCGAAGCGTGAATAA\n")
os.makedirs("$WORK/tmp", exist_ok=True)
skill = OrffinderSkill()
skill.tmpdir = "$WORK/tmp"
skill._resolve_bin = lambda: "ORFfinder"
cmd = skill.build_command("run", input="$WORK/transcripts.fa.gz", outfmt=2)
s = " ".join(cmd)
assert "$WORK/tmp/orffinder_" in s and "/transcripts.fa " in s, s   # 解压到 tmpdir 子目录
assert "-out $WORK/transcripts.asn1" in s, s
# parser 可解析完整 argv
ns = build_parser().parse_args(
    ["run", "-in", "$WORK/transcripts.fa", "-out", "$WORK/out.asn1",
     "-outfmt", "2", "--start-codon", "2", "--min-length", "30",
     "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.outfmt == 2 and ns.start_codon == 2 and ns.min_length == 30, ns
print("  OK:", s)
PY

echo "==> [6/6] 二进制冒烟（若已安装）"
if command -v ORFfinder >/dev/null 2>&1; then
    ORFfinder -version | head -n 2
else
    echo "  ORFfinder 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
