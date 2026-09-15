#!/usr/bin/env bash
# emperor native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - emperor + scikit-bio【可选】：若 `python3 -c "import emperor, skbio"` 成功，
#     会真实运行 plot 并断言输出 HTML；否则退化为 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 时在 native/ 产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（ordination + 元数据表）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^plot'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：plot（python3 驱动 run_emperor.py）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EmperorSkill, build_parser

skill = EmperorSkill()
skill._resolve_binary = lambda: "/opt/env/bin/python3"
cmd = skill.build_command(
    "plot", ordination="$WORK/ordination.txt", metadata="$WORK/sample-metadata.tsv",
    output="$WORK/emperor.html", custom_axes=["DaysSinceExperimentStart"],
    dimensions=3, ignore_missing_samples=True, remote=False, threads=4,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/python3", cmd
assert "run_emperor.py" in s, s
assert "--ordination $WORK/ordination.txt" in s, s
assert "--metadata $WORK/sample-metadata.tsv" in s, s
assert "--output $WORK/emperor.html" in s, s
assert "--custom-axis DaysSinceExperimentStart" in s, s
assert "--dimensions 3" in s, s
assert "--ignore-missing-samples" in s, s
assert "--remote" not in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["plot", "$WORK/ordination.txt", "$WORK/sample-metadata.tsv",
     "-o", "$WORK/out.html", "--dimensions", "2", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "plot" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.ordination == "$WORK/ordination.txt" and ns.dimensions == 2, ns
print("  OK: parser plot")
PY

echo "==> [4/5] argv 构造验证：custom_axes 逗号字符串 + 缺参与远程资源开关"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EmperorSkill

skill = EmperorSkill()
skill._resolve_binary = lambda: "python3"
cmd = skill.build_command(
    "plot", ordination="$WORK/ordination.txt", metadata="$WORK/md.tsv",
    output="$WORK/e.html", custom_axes="A,B", remote=True)
s = " ".join(cmd)
assert "--custom-axis A" in s and "--custom-axis B" in s, s
assert "--remote" in s, s
print("  OK:", s)

# 缺必填参数应报错
for bad in (
    dict(metadata="$WORK/md.tsv", output="$WORK/e.html"),                 # 缺 ordination
    dict(ordination="$WORK/ordination.txt", output="$WORK/e.html"),      # 缺 metadata
    dict(ordination="$WORK/ordination.txt", metadata="$WORK/md.tsv"),    # 缺 output
):
    try:
        skill.build_command("plot", **bad)
        raise AssertionError(f"缺必填参数应报错: {bad}")
    except ValueError:
        pass
print("  OK: 缺必填参数报错")
PY

echo "==> [5/5] 真实回归（emperor + skbio 可用时）"
if python3 -c 'import emperor, skbio' >/dev/null 2>&1; then
    python "$NATIVE/main.py" plot "$WORK/ordination.txt" "$WORK/sample-metadata.tsv" \
        -o "$WORK/emperor.html" --dimensions 2 > "$WORK/run.log" 2>&1 || {
            echo "  [FAIL] plot 真实运行失败："; cat "$WORK/run.log"; exit 1; }
    test -s "$WORK/emperor.html" || { echo "  [FAIL] 未生成 HTML"; exit 1; }
    grep -q "EMPEROR_OK" "$WORK/run.log"
    echo "  OK: plot 真实回归通过"
else
    echo "  emperor/skbio 未安装，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
