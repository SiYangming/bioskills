#!/usr/bin/env bash
# genemark-es native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - gmes_petap.pl 及配套脚本【可选】：若已安装（GENEMARK_PATH 指向 gmes 目录），
#     会额外做入口存在性冒烟；否则跳过真实执行。
# 说明：真实预测需要真实基因组且运行需 ~/.gm_key（官方许可），合成数据无法覆盖真实计算，
#      因此对 es/et/convert_hints 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTA/GFF 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：es（--ES --fungus --cores）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkESSkill, build_parser
skill = GeneMarkESSkill()
skill._resolve_script = lambda name: f"/opt/gmes/{name}"
cmd = skill.build_command("es", genome="$WORK/genome.fasta", fungus=True, threads=8)
s = " ".join(cmd)
assert "/opt/gmes/gmes_petap.pl" in s, s
assert "--sequence $WORK/genome.fasta" in s, s
assert "--ES" in s and "--fungus" in s, s
assert "--cores 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["es", "$WORK/genome.fasta", "--fungus", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "es" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser es")
PY

echo "==> [4/5] argv 构造验证 #2：et（--ET --et_score --cores）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkESSkill
skill = GeneMarkESSkill()
skill._resolve_script = lambda name: f"/opt/gmes/{name}"
cmd = skill.build_command(
    "et", genome="$WORK/genome.fasta", introns="$WORK/introns.gff",
    fungus=True, et_score=10, threads=8,
)
s = " ".join(cmd)
assert "/opt/gmes/gmes_petap.pl" in s, s
assert "--sequence $WORK/genome.fasta" in s, s
assert "--ET $WORK/introns.gff" in s, s
assert "--et_score 10" in s and "--cores 8" in s and "--fungus" in s, s
print("  OK:", s)
PY

echo "==> [5/5] argv 构造验证 #3：convert_hints（写 stdout -> -o 落盘）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkESSkill
skill = GeneMarkESSkill()
skill._resolve_script = lambda name: f"/opt/gmes/{name}"
cmd = skill.build_command("convert_hints", genome="$WORK/genome.fasta", hints="$WORK/hints.gff")
s = " ".join(cmd)
assert "/opt/gmes/hints2genemarkETintron.pl" in s, s
assert "$WORK/genome.fasta" in s and "$WORK/hints.gff" in s, s
print("  OK:", s)
PY

echo "==> [5/5] gmes_petap.pl 冒烟（若已安装）"
if [[ -n "${GENEMARK_PATH:-}" && -f "${GENEMARK_PATH}/gmes_petap.pl" ]]; then
    echo "  检测到 GENEMARK_PATH=${GENEMARK_PATH}/gmes_petap.pl"
elif command -v gmes_petap.pl >/dev/null 2>&1; then
    command -v gmes_petap.pl
else
    echo "  gmes_petap.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
