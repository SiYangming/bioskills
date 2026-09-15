#!/usr/bin/env bash
# exonerate native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - exonerate 二进制【可选】：若已安装（conda activate / PATH 中有 exonerate），
#     会额外做 exonerate --version 冒烟；否则跳过真实执行。
# 说明：exonerate 需真实序列才能比对，合成数据无法覆盖真实计算，因此对 align/parallel
#      采用「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch 二进制解析，
#      不依赖已安装工具）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 禁止生成 __pycache__（保持仓库干净）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（迷你 FASTA 占位）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^align' "$WORK/commands.txt"
grep -q '^parallel' "$WORK/commands.txt"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：align（protein2genome + showtargetgff）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ExonerateSkill, build_parser
skill = ExonerateSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "align", query="$WORK/homolog.fasta", target="$WORK/genome.fasta",
    model="protein2genome", showtargetgff="yes", bestn=1, percent=50, score=100,
)
s = " ".join(cmd)
assert "/opt/env/bin/exonerate" in s, s
assert "--model protein2genome" in s, s
assert "--showtargetgff yes" in s, s
assert "--bestn 1" in s and "--percent 50" in s and "--score 100" in s, s
assert "$WORK/homolog.fasta" in s and "$WORK/genome.fasta" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["align", "$WORK/homolog.fasta", "$WORK/genome.fasta",
     "-o", "$WORK/exonerate.gff", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "align" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser align")
PY

echo "==> [4/5] argv 构造验证 #2：parallel（exonerate_parallel.pl）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ExonerateSkill
skill = ExonerateSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "parallel", query="$WORK/homolog.fasta", target="$WORK/genome.fasta",
    coverage_ratio=0.4, evalue="1e-9", threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/exonerate_parallel.pl" in s, s
assert "--cpu 8" in s, s
assert "--coverage_ratio 0.4" in s and "--evalue 1e-9" in s, s
assert "$WORK/homolog.fasta" in s and "$WORK/genome.fasta" in s, s
print("  OK:", s)
PY

echo "==> [5/5] exonerate 冒烟（若已安装）"
if command -v exonerate >/dev/null 2>&1; then
    exonerate --version | head -n 1
else
    echo "  exonerate 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
