#!/usr/bin/env bash
# geta（GETA）native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - geta.pl 等脚本【可选】：若已安装（conda activate / PATH 中有 geta.pl），会额外做
#     geta.pl --help 冒烟；否则跳过真实执行。
# 说明：GETA 需重复序列库 + RNA-seq + AUGUSTUS 物种参数才能跑通，合成数据无法覆盖真实计算，
#      因此对 geta / best_models / gff3_to_gtf 采用「python 构造 argv 验证命令构建不崩溃」的
#      断言方式（monkeypatch 脚本解析，不依赖已安装工具）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 禁止生成 __pycache__（保持仓库干净）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（基因组/reads/同源蛋白/库/gff3 迷你占位）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^geta' "$WORK/commands.txt"
grep -q '^best_models' "$WORK/commands.txt"
grep -q '^gff3_to_gtf' "$WORK/commands.txt"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：geta（geta.pl 一站式预测）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GetaSkill, build_parser
skill = GetaSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "geta", genome="$WORK/genome.fasta", rm_species="fungi",
    reads1="$WORK/reads.1.fastq", reads2="$WORK/reads.2.fastq",
    protein="$WORK/homolog.fasta", augustus_species="malassezia_sympodialis",
    rm_lib="$WORK/consensi.fa", pfam_db="$WORK/Pfam-AB.hmm",
    gene_prefix="MS01Gene", threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/geta.pl" in s, s
assert "--RM_species fungi" in s, s
assert "--genome $WORK/genome.fasta" in s, s
assert "-1 $WORK/reads.1.fastq" in s and "-2 $WORK/reads.2.fastq" in s, s
assert "--protein $WORK/homolog.fasta" in s, s
assert "--use_existed_augustus_species malassezia_sympodialis" in s, s
assert "--RM_lib $WORK/consensi.fa" in s, s
assert "--cpu 8" in s, s
assert "--pfam_db $WORK/Pfam-AB.hmm" in s and "--gene_prefix MS01Gene" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["geta", "--genome", "$WORK/genome.fasta", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "geta" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser geta")
PY

echo "==> [4/5] argv 构造验证 #2：best_models + gff3_to_gtf"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GetaSkill
skill = GetaSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name

cmd = skill.build_command("best_models", gff3="$WORK/out.gff3")
s = " ".join(cmd)
assert "/opt/env/bin/bestGeneModels.pl" in s, s
assert "$WORK/out.gff3" in s, s
print("  OK:", s)

cmd = skill.build_command("gff3_to_gtf", genome="$WORK/genome.fasta", gff3="$WORK/bestGeneModels.gff3")
s = " ".join(cmd)
assert "/opt/env/bin/gff3ToGtf.pl" in s, s
assert "$WORK/genome.fasta" in s and "$WORK/bestGeneModels.gff3" in s, s
print("  OK:", s)
PY

echo "==> [5/5] geta.pl 冒烟（若已安装）"
if command -v geta.pl >/dev/null 2>&1; then
    geta.pl --help 2>&1 | head -n 3 || true
else
    echo "  geta.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
