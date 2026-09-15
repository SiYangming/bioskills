#!/usr/bin/env bash
# trimal native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - trimAl 二进制【可选】：若已安装（conda activate trimal / PATH 中有 trimal），
#     会额外做真实 MSA 修剪；否则仅做「python 构造 argv 验证命令构建不崩溃」。
# 说明：trimAl 为单线程工具，--threads 仅统一接口保留（不注入命令行）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（含空位的核酸比对）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：trim（automated1 与 gt 两种策略）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TrimalSkill, build_parser
skill = TrimalSkill()
skill._resolve_tool = lambda name: f"/opt/env/bin/{name}"

cmd = skill.build_command("trim", input="$WORK/sample.aln", output="$WORK/sample.trimmed.aln")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/trimal", s
assert "-in $WORK/sample.aln" in s and "-out $WORK/sample.trimmed.aln" in s, s
assert "-automated1" in s, s
print("  OK:", s)

cmd2 = skill.build_command("trim", input="$WORK/sample.aln", output="$WORK/o.aln",
                           method="gt", gt_threshold=0.8)
s2 = " ".join(cmd2)
assert "-gt 0.8" in s2, s2
print("  OK:", s2)

ns = build_parser().parse_args(
    ["trim", "$WORK/sample.aln", "-o", "$WORK/o.aln", "-m", "gappyout",
     "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "trim" and ns.method == "gappyout", ns
assert ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser trim")
PY

echo "==> [4/5] argv 构造验证：readal / statal / version"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TrimalSkill
skill = TrimalSkill()
skill._resolve_tool = lambda name: f"/opt/env/bin/{name}"

r = skill.build_command("readal", input="$WORK/sample.aln", output="$WORK/sample.phy",
                        readal_format="phylip")
assert r[0] == "/opt/env/bin/readal", r
assert "-in $WORK/sample.aln" in " ".join(r) and "-out $WORK/sample.phy" in " ".join(r), r
assert "-phylip" in r, r
print("  OK:", " ".join(r))

st = skill.build_command("statal", input="$WORK/sample.aln", output="$WORK/sample.stats.txt")
assert st[0] == "/opt/env/bin/statal", st
assert "-in $WORK/sample.aln" in " ".join(st), st
print("  OK:", " ".join(st))

v = skill.build_command("version")
assert v == ["/opt/env/bin/trimal", "-h"], v
print("  OK:", " ".join(v))
PY

echo "==> [5/5] trimAl 真实冒烟（若已安装）"
if command -v trimal >/dev/null 2>&1; then
    python "$NATIVE/main.py" trim "$WORK/sample.aln" -o "$WORK/sample.trimmed.aln" -m gt --gt-threshold 0.8
    test -s "$WORK/sample.trimmed.aln" && echo "  OK: 生成修剪后比对 sample.trimmed.aln"
else
    echo "  trimAl 未安装，跳过真实执行（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
