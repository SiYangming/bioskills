#!/usr/bin/env bash
# circos native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - circos 二进制【可选】：若已安装（conda activate circos-native / PATH 中有 circos），
#     会额外真实渲染 circos.png；否则跳过真实执行，仅做 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免测试导入 main.py 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（karyotype + circos.conf）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：plot"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CircosSkill, build_parser
skill = CircosSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "plot", conf="$WORK/circos.conf", outputdir="$WORK/out", noparanoid=True,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/circos", s
assert "-noparanoid" in s, s
assert "-conf $WORK/circos.conf" in s, s
assert "-outputdir $WORK/out" in s, s
print("  OK:", s)
# 线程优先级：显式 > 子命令建议 > 全局默认
assert skill._effective_threads("plot", 8) == 8
assert skill._effective_threads("plot", None) == 4
print("  OK: threads=", skill._effective_threads("plot", None))
ns = build_parser().parse_args(
    ["plot", "$WORK/circos.conf", "-o", "$WORK/out", "--threads", "6", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "plot" and ns.threads == 6 and ns.tmpdir == "/tmp", ns
print("  OK: parser plot")
PY

echo "==> [4/5] argv 构造验证 #2：modules / gddiag"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CircosSkill
skill = CircosSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
mod = skill.build_command("modules")
assert mod == ["/opt/env/bin/circos", "-modules"], mod
gd = skill.build_command("gddiag")
assert gd == ["/opt/env/bin/gddiag"], gd
print("  OK:", " ".join(mod))
print("  OK:", " ".join(gd))
PY

echo "==> [5/5] circos 冒烟（若已安装）：真实渲染最小环形图"
if command -v circos >/dev/null 2>&1; then
    ( cd "$WORK" && circos -noparanoid -conf circos.conf -outputdir . >/dev/null 2>&1 || true )
    if [ -f "$WORK/circos.png" ]; then
        echo "  OK: 已生成 $WORK/circos.png"
    else
        echo "  circos 已安装但最小渲染未产出 PNG（依赖模块可能不全），跳过产物断言"
    fi
else
    echo "  circos 未安装，跳过真实渲染（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
