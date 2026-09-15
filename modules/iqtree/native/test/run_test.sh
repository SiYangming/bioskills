#!/usr/bin/env bash
# iqtree native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - iqtree【可选】：本测试对 ml/model 采用「python 构造 argv 验证命令构建不崩溃」的断言方式
#     （避免与系统可能安装的 v2/v3 在 -nt/-T 线程参数上的差异冲突），有二进制时仅做 --version 冒烟。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（小蛋白比对占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^ml' "$WORK/commands.txt"
grep -q '^model' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：ml（ModelFinder Plus + UFBoot + aLRT，14.md 4.7）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IqtreeSkill, build_parser
skill = IqtreeSkill()
skill._resolve_binary = lambda: "/opt/env/bin/iqtree"
cmd = skill.build_command(
    "ml", input="$WORK/aln.phy", model="MFP", bootstrap=1000,
    alrt=1000, threads=8, prefix="$WORK/out_protein",
)
s = " ".join(cmd)
assert "/opt/env/bin/iqtree" in s, s
assert "-s $WORK/aln.phy" in s, s
assert "-m MFP" in s, s
assert "-bb 1000" in s and "-alrt 1000" in s, s
assert "-nt 8" in s, s
assert "-pre $WORK/out_protein" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["ml", "$WORK/aln.phy", "-m", "LG+G4", "-bb", "1000",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "ml" and ns.model == "LG+G4" and ns.bootstrap == 1000, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser ml")
PY

echo "==> [4/5] argv 构造验证 #2：model（仅 ModelFinder）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IqtreeSkill
skill = IqtreeSkill()
skill._resolve_binary = lambda: "iqtree"
cmd = skill.build_command("model", input="$WORK/aln.fasta", threads=4, prefix="$WORK/mf")
s = " ".join(cmd)
assert s.startswith("iqtree -s $WORK/aln.fasta -m MF"), s
assert "-nt 4" in s, s
assert "-pre $WORK/mf" in s, s
assert "-bb" not in s and "-alrt" not in s, s
print("  OK:", s)
PY

echo "==> [5/5] iqtree 冒烟（若已安装；不做真实建树）"
if command -v iqtree >/dev/null 2>&1; then
    iqtree --version 2>&1 | head -n 1
else
    echo "  iqtree 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
