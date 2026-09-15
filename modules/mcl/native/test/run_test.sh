#!/usr/bin/env bash
# mcl native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - mcl / mcxdump 二进制【可选】：未安装时全部退化为「python 构造 argv 验证命令构建」
#     断言（monkeypatch 二进制解析），不实际运行聚类（合成图无法覆盖真实计算）。
# 覆盖：cluster（ABC + inflation + -te 线程）/ dump（mcxdump）/ version / parser / 缺二进制报错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（小型 ABC 图 + 标签）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/graph.abc"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^cluster'
python "$NATIVE/main.py" --list-commands | grep -q '^dump'
python "$NATIVE/main.py" --list-commands | grep -q '^version'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证：cluster（ABC + inflation + -te 线程）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MclSkill, build_parser, _BINARIES

assert _BINARIES == {"cluster": "mcl", "dump": "mcxdump", "version": "mcl"}, _BINARIES

skill = MclSkill()
skill._resolve_sub_binary = lambda sub: "/opt/mcl/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "cluster", graph="$WORK/graph.abc", abc=True, inflation=1.5,
    output="$WORK/mclOutput", threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/mcl/bin/mcl "), s
assert "$WORK/graph.abc" in s and "--abc" in s, s
assert "-I 1.5" in s, s
assert "-o $WORK/mclOutput" in s, s
assert "-te 8" in s, s
print("  OK:", s)

# 不带 --abc / 默认线程（per_subcommand_threads.cluster=8）→ 仍注入 -te 8
cmd = skill.build_command("cluster", graph="$WORK/graph.abc", output="$WORK/out2")
s = " ".join(cmd)
assert "--abc" not in s, s
assert "-te 8" in s, s
assert "-I" not in s, s
print("  OK:", s)
PY

echo "==> [4/7] argv 构造验证：cluster 高级参数 + dump（mcxdump）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MclSkill, _BINARIES

skill = MclSkill()
skill._resolve_sub_binary = lambda sub: "/opt/mcl/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "cluster", graph="$WORK/graph.abc", abc=True, inflation=2.0,
    scheme=6, tf="gq(0.7)", pre_inflation=1.2,
    output="$WORK/out3", threads=4,
)
s = " ".join(cmd)
for frag in ("-I 2.0", "-o $WORK/out3", "-te 4", "-scheme 6", "-pi 1.2"):
    assert frag in s, (frag, s)
assert "-tf gq(0.7)" in s, s
print("  OK:", s)

# dump：mcxdump -imx <matrix> -o <out> -tab <labels> --dump-pairs --no-values
cmd = skill.build_command(
    "dump", matrix="$WORK/graph.mci", output="$WORK/graph.abc",
    tab="$WORK/labels.txt", dump_pairs=True, no_values=True,
)
s = " ".join(cmd)
assert s.startswith("/opt/mcl/bin/mcxdump "), s
assert "-imx $WORK/graph.mci" in s, s
assert "-o $WORK/graph.abc" in s, s
assert "-tab $WORK/labels.txt" in s, s
assert "--dump-pairs" in s and "--no-values" in s, s
print("  OK:", s)

# version
cmd = skill.build_command("version")
assert cmd == ["/opt/mcl/bin/mcl", "--version"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [5/7] parser 解析（子命令后 --threads / --tmpdir）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser

ns = build_parser().parse_args(
    ["cluster", "$WORK/graph.abc", "--abc", "-I", "1.5",
     "-o", "$WORK/o", "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "cluster" and ns.abc is True
assert ns.inflation == 1.5 and ns.output == "$WORK/o"
assert ns.threads == 8 and ns.tmpdir == "/tmp", ns

ns = build_parser().parse_args(
    ["dump", "-imx", "$WORK/graph.mci", "-o", "$WORK/o.abc"])
assert ns.subcommand == "dump" and ns.matrix == "$WORK/graph.mci"
print("  OK: parser cluster / dump")
PY

echo "==> [6/7] 运行时校验：缺必填 / 未知子命令 / 缺二进制"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MclSkill

skill = MclSkill()
skill._resolve_sub_binary = lambda sub: "mcl"

for kw in (dict(output="o"),                        # cluster 缺 graph
           dict(graph="g.abc")):                    # cluster 缺 output
    try:
        skill.build_command("cluster", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
for kw in (dict(output="o"), dict(matrix="m.mci")):  # dump 缺 matrix / output
    try:
        skill.build_command("dump", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass

# 真实缺二进制（PATH 置空目录，排除宿主已装 mcl 的干扰）→ 明确报错
import os
emptybin = os.path.join("$WORK", "emptybin")
os.makedirs(emptybin, exist_ok=True)
os.environ["PATH"] = emptybin
clean = MclSkill()
try:
    clean.build_command("cluster", graph="g.abc", output="o")
    raise AssertionError("缺 mcl 二进制应抛 RuntimeError")
except RuntimeError as e:
    assert "未找到可执行文件" in str(e), e
print("  OK: 运行时参数校验")
PY

echo "==> [7/7] mcl 冒烟（若已安装）"
if command -v mcl >/dev/null 2>&1; then
    mcl --version | head -n 1
else
    echo "  mcl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
