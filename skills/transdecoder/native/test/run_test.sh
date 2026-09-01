#!/usr/bin/env bash
# transdecoder native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - TransDecoder.LongOrfs / TransDecoder.Predict 二进制【可选】：若已安装
#     （conda activate transdecoder-native / PATH 中可见），会额外做 --version 冒烟；
#     否则跳过真实执行。
# 说明：TransDecoder 需要真实转录本序列才能产出 CDS，合成数据无法覆盖真实计算，
#      因此本脚本对子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成转录本 FASTA + 占位证据文件）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "longorfs"
python "$NATIVE/main.py" --list-commands | grep -q "predict"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：longorfs 默认参数（-m 50 -G Universal）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TransdecoderSkill, BIN_LONGORFS
skill = TransdecoderSkill()
skill._resolve_bin = lambda b: "/opt/env/bin/" + b  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "longorfs", input="$WORK/transcripts.fa", output_dir="$WORK/out1",
    min_protein_length=50, genetic_code="Universal",
    strand_specific=True, complete_orfs_only=True,
)
s = " ".join(cmd)
assert BIN_LONGORFS in s and "/opt/env/bin/" in s, s
assert "-t $WORK/transcripts.fa" in s, s
assert "-O $WORK/out1" in s, s
assert "-m 50" in s, s
assert "-G Universal" in s, s
assert "-S" in s, s
assert "--complete_orfs_only" in s, s
# longorfs 不注入 --cpu
assert "--cpu" not in s, s
print("  OK:", s)
PY

echo "==> [4/6] argv 构造验证 #2：longorfs + --gene-trans-map"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TransdecoderSkill
skill = TransdecoderSkill()
skill._resolve_bin = lambda b: "TransDecoder.LongOrfs"
cmd = skill.build_command(
    "longorfs", input="$WORK/transcripts.fa", output_dir="$WORK/out2",
    gene_trans_map="$WORK/gene_trans_map.txt", threads=2,
)
s = " ".join(cmd)
assert "--gene_trans_map $WORK/gene_trans_map.txt" in s, s
assert "--cpu" not in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：predict 全参数（retain 证据 + 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TransdecoderSkill, build_parser
skill = TransdecoderSkill()
skill._resolve_bin = lambda b: "/opt/env/bin/" + b
cmd = skill.build_command(
    "predict", input="$WORK/transcripts.fa", output_dir="$WORK/out3",
    retain_pfam_hits="$WORK/pfam.domtblout",
    retain_blastp_hits="$WORK/blastp.outfmt6",
    single_best_only=True, no_refine_starts=True, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/TransDecoder.Predict" in s, s
assert "--retain_pfam_hits $WORK/pfam.domtblout" in s, s
assert "--retain_blastp_hits $WORK/blastp.outfmt6" in s, s
assert "--single_best_only" in s, s
assert "--no_refine_starts" in s, s
assert "--cpu 8" in s, s
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "-t", "$WORK/transcripts.fa", "-O", "$WORK/out4",
     "--retain-pfam-hits", "$WORK/pfam.domtblout",
     "--no-refine-starts", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK:", s)
PY

echo "==> [6/6] 二进制冒烟（若已安装）"
if command -v TransDecoder.Predict >/dev/null 2>&1; then
    TransDecoder.LongOrfs --version | head -n 1
    TransDecoder.Predict --version | head -n 1
else
    echo "  TransDecoder 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
