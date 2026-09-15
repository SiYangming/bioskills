#!/usr/bin/env bash
# mcscanx native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - MCScanX / duplicate_gene_classifier / java【可选】：未安装时退化为 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（input.gff + input.blast + control）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^scan'
python "$NATIVE/main.py" --list-commands | grep -q '^classify'
python "$NATIVE/main.py" --list-commands | grep -q '^dual'
python "$NATIVE/main.py" --list-commands | grep -q '^circle'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证（monkeypatch 二进制）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import McscanxSkill, build_parser

skill = McscanxSkill()
skill._resolve_binary = lambda: "/opt/env/bin/MCScanX"

def fake_tool(name):
    return "/opt/env/bin/" + name
skill._resolve_tool = fake_tool

# scan
cmd = skill.build_command("scan", prefix="$WORK/input")
s = " ".join(cmd)
assert cmd == ["/opt/env/bin/MCScanX", "$WORK/input"], s
print("  OK:", s)

# classify
cmd = skill.build_command("classify", prefix="$WORK/input")
s = " ".join(cmd)
assert cmd == ["/opt/env/bin/duplicate_gene_classifier", "$WORK/input"], s
print("  OK:", s)

# dual（java <class> -g -s -c -o）
cmd = skill.build_command(
    "dual", gff="$WORK/input.gff", collinearity="$WORK/input.collinearity",
    control="$WORK/control", output="$WORK/dual.png",
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/java" and cmd[1] == "dual_synteny_plotter", s
assert "-g $WORK/input.gff" in s and "-s $WORK/input.collinearity" in s, s
assert "-c $WORK/control" in s and "-o $WORK/dual.png" in s, s
print("  OK:", s)

# circle
cmd = skill.build_command(
    "circle", gff="$WORK/input.gff", collinearity="$WORK/input.collinearity",
    control="$WORK/control", output="$WORK/circle.png",
)
assert cmd[1] == "circle_plotter", cmd
print("  OK:", " ".join(cmd))

# parser 可解析子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["scan", "$WORK/input", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "scan" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser scan --threads/--tmpdir")

# 缺参应报错
try:
    skill.build_command("dual", gff="$WORK/input.gff")
    raise AssertionError("dual 缺参应抛 ValueError")
except ValueError:
    print("  OK: dual 缺参被拒绝")
PY

echo "==> [4/4] 组件冒烟（若已安装）"
if command -v MCScanX >/dev/null 2>&1; then
    MCScanX 2>&1 | head -n 2 || true
else
    echo "  MCScanX 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
