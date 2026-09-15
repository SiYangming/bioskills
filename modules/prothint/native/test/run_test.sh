#!/usr/bin/env bash
# prothint native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ProtHint【可选】：若已安装（PATH 中有 prothint.py，或设置 PROTHINT_HOME），
#     会额外做 prothint.py --version 冒烟；否则跳过真实执行。
# 说明：ProtHint 真实运行需要参考蛋白库 + DIAMOND/Spaln 剪接比对，合成数据无法覆盖真实计算，
#      因此对 predict/high_confidence/augustus_hints 采用
#      「python 构造 argv 验证命令构建不崩溃（monkeypatch 脚本解析）」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（最小 FASTA + GFF 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：predict（prothint.py 主流程）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ProthintSkill, build_parser
skill = ProthintSkill()
skill._resolve_script = lambda name: "/opt/ProtHint/bin/" + name
cmd = skill.build_command(
    "predict", genome="$WORK/genome.fasta", proteins="$WORK/proteins.fasta",
    workdir="$WORK/prothint_out", gene_mark_gtf="$WORK/genemark.gtf",
    fungus=True, evalue=0.001, threads=8,
)
s = " ".join(cmd)
assert s.startswith(sys.executable), s
assert "/opt/ProtHint/bin/prothint.py" in s, s
assert "$WORK/genome.fasta" in s and "$WORK/proteins.fasta" in s, s
assert "--workdir $WORK/prothint_out" in s, s
assert "--geneMarkGtf $WORK/genemark.gtf" in s, s
assert "--fungus" in s and "--evalue 0.001" in s and "--threads 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/genome.fasta", "$WORK/proteins.fasta",
     "--workdir", "$WORK/out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.genome.endswith("genome.fasta") and ns.proteins.endswith("proteins.fasta"), ns
print("  OK: parser predict")
PY

echo "==> [4/6] argv 构造验证 #2：high_confidence"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ProthintSkill
skill = ProthintSkill()
skill._resolve_script = lambda name: "/opt/ProtHint/bin/" + name
cmd = skill.build_command(
    "high_confidence", prothint_gff="$WORK/prothint.gff", output="$WORK/evidence.gff",
    intron_coverage=95, add_top_proteins=True,
)
s = " ".join(cmd)
assert s.startswith(sys.executable), s
assert "/opt/ProtHint/bin/print_high_confidence.py" in s, s
assert s.endswith("$WORK/prothint.gff --intronCoverage 95 --addTopProteins"), s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：augustus_hints"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ProthintSkill
skill = ProthintSkill()
skill._resolve_script = lambda name: "/opt/ProtHint/bin/" + name
cmd = skill.build_command(
    "augustus_hints", prothint_gff="$WORK/prothint.gff", evidence_gff="$WORK/evidence.gff",
    chains_gff="$WORK/chains.gff", output="$WORK/hints.gff",
)
s = " ".join(cmd)
assert "/opt/ProtHint/bin/prothint2augustus.py" in s, s
assert s.endswith("$WORK/prothint.gff $WORK/evidence.gff $WORK/chains.gff $WORK/hints.gff"), s
print("  OK:", s)
# 缺参应报 ValueError
try:
    skill.build_command("augustus_hints", prothint_gff="$WORK/prothint.gff")
    raise SystemExit("[FAIL] 缺参未报错")
except ValueError:
    print("  OK: 缺参校验触发")
PY

echo "==> [6/6] ProtHint 冒烟（若已安装）"
if command -v prothint.py >/dev/null 2>&1; then
    prothint.py --version | head -n 1
elif [[ -n "${PROTHINT_HOME:-}" && -x "${PROTHINT_HOME}/bin/prothint.py" ]]; then
    "${PROTHINT_HOME}/bin/prothint.py" --version | head -n 1
else
    echo "  ProtHint 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
