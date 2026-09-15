#!/usr/bin/env bash
# genomethreader native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - gth/gthconsensus/gthgetseq 二进制【可选】：若已安装（conda activate genomethreader /
#     PATH 中有 gth），会额外做 gth --version 冒烟；否则跳过真实执行。
# 说明：gth 真实剪接比对需要真实基因组 + cDNA/蛋白序列，合成数据无法覆盖真实计算，
#      因此对 align/consensus/getseq 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（FASTA/GFF3 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：align（gth，蛋白证据，gff3out + intermediate）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenomeThreaderSkill, build_parser
skill = GenomeThreaderSkill()
skill._resolve_tool = lambda name: f"/opt/gth/bin/{name}"
cmd = skill.build_command(
    "align", genomic="$WORK/genome.fasta", protein="$WORK/protein.fasta",
    species="arabidopsis", output="$WORK/out.gff3", threads=1,
)
s = " ".join(cmd)
assert "/opt/gth/bin/gth" in s, s
assert "-genomic $WORK/genome.fasta" in s, s
assert "-protein $WORK/protein.fasta" in s, s
assert "-species arabidopsis" in s, s
assert "-intermediate" in s and "-gff3out" in s, s
assert "-o $WORK/out.gff3" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["align", "-genomic", "$WORK/genome.fasta", "-cdna", "$WORK/cdna.fasta",
     "-o", "$WORK/cdna.gff3", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "align" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser align")
PY

echo "==> [4/6] argv 构造验证 #2：consensus"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenomeThreaderSkill
skill = GenomeThreaderSkill()
skill._resolve_tool = lambda name: f"/opt/gth/bin/{name}"
cmd = skill.build_command(
    "consensus", inputs=["$WORK/a.gff3", "$WORK/b.gff3"],
    species="arabidopsis", output="$WORK/consensus.gff3",
)
s = " ".join(cmd)
assert "/opt/gth/bin/gthconsensus" in s, s
assert "$WORK/a.gff3" in s and "$WORK/b.gff3" in s, s
assert "-species arabidopsis" in s and "-gff3out" in s, s
assert "-o $WORK/consensus.gff3" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：getseq（写 stdout -> -o 落盘）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GenomeThreaderSkill
skill = GenomeThreaderSkill()
skill._resolve_tool = lambda name: f"/opt/gth/bin/{name}"
cmd = skill.build_command("getseq", inputs=["$WORK/intermediate.gff3"], get_mode="protein")
s = " ".join(cmd)
assert "/opt/gth/bin/gthgetseq" in s, s
assert "-getprotein" in s, s
assert "$WORK/intermediate.gff3" in s, s
print("  OK:", s)
PY

echo "==> [6/6] gth 冒烟（若已安装）"
if command -v gth >/dev/null 2>&1; then
    gth --version | head -n 1
else
    echo "  gth 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
