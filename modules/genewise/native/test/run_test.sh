#!/usr/bin/env bash
# genewise（GeneWise / wise2）native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - genewise 二进制【可选】：若已安装（conda activate / PATH 中有 genewise），会额外做
#     genewise -version 冒烟；否则跳过真实执行。
# 说明：genewise 需真实序列才能预测基因结构，合成数据无法覆盖真实计算，因此对
#      genewise/homolog/gff2gff3 采用「python 构造 argv 验证命令构建不崩溃」的断言方式
#      （monkeypatch 二进制解析，不依赖已安装工具）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 禁止生成 __pycache__（保持仓库干净）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（迷你 FASTA + genewise GFF 占位）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^genewise' "$WORK/commands.txt"
grep -q '^homolog' "$WORK/commands.txt"
grep -q '^gff2gff3' "$WORK/commands.txt"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：genewise（-gff）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenewiseSkill, build_parser
skill = GenewiseSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command("genewise", protein="$WORK/homolog.fasta", dna="$WORK/genome.fasta", gff=True)
s = " ".join(cmd)
assert "/opt/env/bin/genewise" in s, s
assert "-gff" in s, s
assert "$WORK/homolog.fasta" in s and "$WORK/genome.fasta" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["genewise", "$WORK/homolog.fasta", "$WORK/genome.fasta", "-gff",
     "-o", "$WORK/gene.gff", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "genewise" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser genewise")
PY

echo "==> [4/5] argv 构造验证 #2：homolog（homolog_genewise）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenewiseSkill
skill = GenewiseSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "homolog", protein="$WORK/homolog.fasta", dna="$WORK/genome.fasta",
    coverage_ratio=0.4, evalue="1e-9", max_gene_length=2000, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/homolog_genewise" in s, s
assert "--cpu 8" in s, s
assert "--coverage_ratio 0.4" in s and "--evalue 1e-9" in s and "--max_gene_length 2000" in s, s
assert "$WORK/homolog.fasta" in s and "$WORK/genome.fasta" in s, s
print("  OK:", s)
PY

echo "==> [4b] argv 构造验证 #3：gff2gff3（homolog_genewiseGFF2GFF3）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenewiseSkill
skill = GenewiseSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "gff2gff3", gff="$WORK/genewise.gff", genome="$WORK/genome.fasta",
    min_score=15, gene_prefix="genewise",
)
s = " ".join(cmd)
assert "/opt/env/bin/homolog_genewiseGFF2GFF3" in s, s
assert "--genome $WORK/genome.fasta" in s, s
assert "--min_score 15" in s and "--gene_prefix genewise" in s, s
assert "$WORK/genewise.gff" in s, s
print("  OK:", s)
PY

echo "==> [5/5] genewise 冒烟（若已安装）"
if command -v genewise >/dev/null 2>&1; then
    genewise -version 2>&1 | head -n 3
else
    echo "  genewise 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
