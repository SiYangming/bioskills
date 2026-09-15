#!/usr/bin/env bash
# viennarna native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ViennaRNA 二进制【可选】：若已安装（conda activate viennarna / PATH 中有 RNAfold），
#     会额外做 RNAfold 真实折叠回归 + --version 冒烟；否则仅做 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（可折叠的 pre-miRNA 样序列）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：rnafold"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ViennarnaSkill, build_parser
skill = ViennarnaSkill()
skill._resolve_binary = lambda: "/opt/env/bin/RNAfold"
cmd = skill.build_command(
    "rnafold", input="$WORK/pre_mirna.fa", partition=True, no_lp=True,
    temperature=37.0, no_guess=True, threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/RNAfold "), s
assert "-p" in s and "--noLP" in s and "--noPS" in s, s
assert "-T 37.0" in s, s
assert s.endswith("$WORK/pre_mirna.fa"), s
print("  OK:", s)
ns = build_parser().parse_args(
    ["rnafold", "$WORK/pre_mirna.fa", "-p", "--noLP", "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "rnafold" and ns.partition and ns.no_lp and ns.threads == 1, ns
print("  OK: parser rnafold")
PY

echo "==> [4/6] argv 构造验证 #2：rnaeval / rnaplot"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ViennarnaSkill
skill = ViennarnaSkill()
skill._resolve_binary = lambda: "RNAeval"
cmd = skill.build_command("rnaeval", input="$WORK/structure.txt", temperature=37.0)
s = " ".join(cmd)
assert s == "RNAeval -T 37.0 $WORK/structure.txt", s
print("  OK:", s)
skill2 = ViennarnaSkill()
skill2._resolve_binary = lambda: "RNAplot"
cmd2 = skill2.build_command("rnaplot", input="$WORK/structure.txt",
                            plot_format="svg", output="$WORK/struct")
s2 = " ".join(cmd2)
assert s2 == "RNAplot -t svg -o $WORK/struct $WORK/structure.txt", s2
print("  OK:", s2)
PY

echo "==> [5/6] RNAfold 真实折叠回归（若已安装）"
if command -v RNAfold >/dev/null 2>&1; then
    RNAfold --version
    python "$NATIVE/main.py" rnafold "$WORK/pre_mirna.fa" > "$WORK/fold.txt"
    test -s "$WORK/fold.txt"
    # 输出应含点括号结构（二级结构）与自由能（负数）
    grep -qE '[().]{10,}' "$WORK/fold.txt" || { echo "  [FAIL] 未找到二级结构输出" >&2; exit 1; }
    grep -qE '\(\s*-?[0-9]+\.[0-9]+\)' "$WORK/fold.txt" || echo "  [warn] 未匹配到自由能括号（结构可能为全无配对）"
    echo "  OK: RNAfold 真实折叠通过"
else
    echo "  RNAfold 未安装，跳过真实折叠（argv 构造验证已通过）"
fi

echo "==> [6/6] 自省命令冒烟"
python "$NATIVE/main.py" --list-commands >/dev/null
echo "  OK"

echo "ALL TESTS PASSED"
