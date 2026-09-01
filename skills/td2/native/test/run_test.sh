#!/usr/bin/env bash
# td2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - TD2.LongOrfs / TD2.Predict 二进制【可选】：若已安装
#     （conda activate td2-native / PATH 中可见），会额外做 --version 冒烟；
#     否则跳过真实执行。
# 说明：TD2 需要真实转录本序列才能产出 CDS，合成数据无法覆盖真实计算，
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

echo "==> [3/6] argv 构造验证 #1：longorfs 默认参数（-m 90 -M 90 -G 1）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Td2Skill, BIN_LONGORFS
skill = Td2Skill()
skill._resolve_bin = lambda b: "/opt/env/bin/" + b  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "longorfs", input="$WORK/transcripts.fa", output_dir="$WORK/out1",
    min_length=90, abs_min_length=90, genetic_code=1,
    strand_specific=True, alt_start=True, all_stopless=True,
)
s = " ".join(cmd)
assert BIN_LONGORFS in s and "/opt/env/bin/" in s, s
assert "-t $WORK/transcripts.fa" in s, s
assert "-O $WORK/out1" in s, s
assert "-m 90" in s, s
assert "-M 90" in s, s
assert "-G 1" in s, s
assert "-S" in s, s
assert "--alt-start" in s, s
assert "--all-stopless" in s, s
assert "--threads 8" in s, s   # 默认线程注入（per_subcommand_threads.longorfs=8）
print("  OK:", s)
PY

echo "==> [4/6] argv 构造验证 #2：longorfs + --gene-trans-map + 显式线程"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Td2Skill
skill = Td2Skill()
skill._resolve_bin = lambda b: "TD2.LongOrfs"
cmd = skill.build_command(
    "longorfs", input="$WORK/transcripts.fa", output_dir="$WORK/out2",
    gene_trans_map="$WORK/gene_trans_map.txt", threads=8,
)
s = " ".join(cmd)
assert "--gene-trans-map $WORK/gene_trans_map.txt" in s, s
assert "--threads 8" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：predict 全参数（retain 证据 + --psauron-all-frame）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Td2Skill, build_parser
skill = Td2Skill()
skill._resolve_bin = lambda b: "/opt/env/bin/" + b
cmd = skill.build_command(
    "predict", input="$WORK/transcripts.fa", output_dir="$WORK/out3",
    retain_mmseqs_hits="$WORK/hits.m8",
    retain_blastp_hits="$WORK/blastp.outfmt6",
    retain_hmmer_hits="$WORK/pfam.domtblout",
    psauron_all_frame=True, all_good=True, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/TD2.Predict" in s, s
assert "--retain-mmseqs-hits $WORK/hits.m8" in s, s
assert "--retain-blastp-hits $WORK/blastp.outfmt6" in s, s
assert "--retain-hmmer-hits $WORK/pfam.domtblout" in s, s
assert "--psauron-all-frame" in s, s
assert "--all-good" in s, s
assert "--threads 8" in s, s
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "-t", "$WORK/transcripts.fa", "-O", "$WORK/out4",
     "--retain-mmseqs-hits", "$WORK/hits.m8",
     "--psauron-all-frame", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK:", s)
PY

echo "==> [6/6] 二进制冒烟（若已安装）"
if command -v TD2.Predict >/dev/null 2>&1; then
    TD2.LongOrfs --version | head -n 1
    TD2.Predict --version | head -n 1
else
    echo "  TD2 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
