#!/usr/bin/env bash
# augustus native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - augustus 及配套脚本【可选】：若已安装（conda activate augustus / AUGUSTUS_*_PATH），
#     会额外做 augustus --version 冒烟；否则跳过真实执行。
# 说明：真实预测/训练需要真实基因组与注释，合成数据无法覆盖真实计算，因此对
#      predict/etraining/optimize/gff2gb/bam2hints 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（FASTA/GFF/GenBank/BAM 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证 #1：predict（--species/--hintsfile/--CRF，GFF 写 stdout）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AugustusSkill, build_parser
skill = AugustusSkill()
skill._resolve_tool = lambda name, kind: f"/opt/augustus/{kind}/{name}"
cmd = skill.build_command(
    "predict", genome="$WORK/genome.fasta", species="malassezia_sympodialis",
    hintsfile="$WORK/hints.gff", crf=1,
)
s = " ".join(cmd)
assert "/opt/augustus/bin/augustus" in s, s
assert "--species=malassezia_sympodialis" in s, s
assert "--hintsfile=$WORK/hints.gff" in s, s
assert "--CRF=1" in s, s
assert s.endswith("$WORK/genome.fasta"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/genome.fasta", "--species", "malassezia_sympodialis",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser predict")
PY

echo "==> [4/7] argv 构造验证 #2：etraining / new_species"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AugustusSkill
skill = AugustusSkill()
skill._resolve_tool = lambda name, kind: f"/opt/augustus/{kind}/{name}"
cmd = skill.build_command("etraining", genes_gb="$WORK/genes.gb",
                          species="malassezia_sympodialis", crf=1)
s = " ".join(cmd)
assert "/opt/augustus/bin/etraining" in s, s
assert "--species=malassezia_sympodialis" in s and "--CRF=1" in s, s
assert s.endswith("$WORK/genes.gb"), s
print("  OK:", s)
cmd = skill.build_command("new_species", species="malassezia_sympodialis")
s = " ".join(cmd)
assert "/opt/augustus/scripts/new_species.pl" in s, s
assert "--species=malassezia_sympodialis" in s, s
print("  OK:", s)
PY

echo "==> [5/7] argv 构造验证 #3：optimize（--cpus 由线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AugustusSkill
skill = AugustusSkill()
skill._resolve_tool = lambda name, kind: f"/opt/augustus/{kind}/{name}"
cmd = skill.build_command("optimize", genes_gb="$WORK/genes.gb.train",
                          species="malassezia_sympodialis",
                          rounds=5, kfold=8, threads=8)
s = " ".join(cmd)
assert "/opt/augustus/scripts/optimize_augustus.pl" in s, s
assert "--species=malassezia_sympodialis" in s, s
assert "--rounds 5" in s and "--kfold 8" in s and "--cpus 8" in s, s
print("  OK:", s)
PY

echo "==> [6/7] argv 构造验证 #4：gff2gb / bam2hints"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AugustusSkill
skill = AugustusSkill()
skill._resolve_tool = lambda name, kind: f"/opt/augustus/{kind}/{name}"
cmd = skill.build_command("gff2gb", annotation="$WORK/annotation.gff3",
                          genome="$WORK/genome.fasta", flank=100,
                          output="$WORK/genes.raw.gb")
s = " ".join(cmd)
assert "/opt/augustus/scripts/gff2gbSmallDNA.pl" in s, s
assert "$WORK/annotation.gff3" in s and "$WORK/genome.fasta" in s, s
assert "100 $WORK/genes.raw.gb" in s, s
print("  OK:", s)
cmd = skill.build_command("bam2hints", bam="$WORK/rnaseq.bam", output="$WORK/hints.gff")
s = " ".join(cmd)
assert "/opt/augustus/bin/bam2hints" in s, s
assert "--intronsonly" in s, s
assert "--in=$WORK/rnaseq.bam" in s and "--out=$WORK/hints.gff" in s, s
print("  OK:", s)
PY

echo "==> [7/7] augustus 冒烟（若已安装）"
if command -v augustus >/dev/null 2>&1; then
    augustus --version 2>&1 | head -n 2
else
    echo "  augustus 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
