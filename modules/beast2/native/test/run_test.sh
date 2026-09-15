#!/usr/bin/env bash
# beast2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - BEAST2【可选】：若已安装（native/install.sh / conda activate beast2 / brew），
#     会额外做 `beast -version` 冒烟；否则跳过真实执行。
# 说明：beast 真实运行需要完整 XML 与真实比对，MCMC 耗时长，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃 + 自省命令断言」的方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; find "$NATIVE" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; }
trap cleanup EXIT

echo "==> [1/5] 生成测试数据（混合占位：xml / trees / log）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/input.xml" && test -f "$WORK/input.trees" && test -f "$WORK/a.log"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for c in beast treeannotator logcombiner loganalyser densitetree beauti version; do
    grep -q "^${c}" "$WORK/commands.txt" || { echo "  [FAIL] --list-commands 缺少 ${c}" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证（monkeypatch _resolve_program）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Beast2Skill, build_parser

skill = Beast2Skill()
skill._resolve_program = lambda name: f"/opt/env/bin/{name}"   # monkeypatch：惰性解析

# beast：BEAGLE + 线程 + 实例数
cmd = skill.build_command("beast", input="$WORK/input.xml", beagle=True, threads=8, instances=8)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/beast", cmd
assert "-beagle -beagle_CPU -beagle_SSE -beagle_double" in s, s
assert "-instances 8" in s and "-threads 8" in s, s
assert s.endswith("$WORK/input.xml"), s
# treeannotator：-burnin input output
cmd = skill.build_command("treeannotator", input="$WORK/input.trees", output="$WORK/tree_abbr.BEAST2", burnin=20)
assert cmd == ["/opt/env/bin/treeannotator", "-burnin", "20", "$WORK/input.trees", "$WORK/tree_abbr.BEAST2"], cmd
# logcombiner：-b -o inputs...
cmd = skill.build_command("logcombiner", inputs=["$WORK/a.log", "$WORK/b.log"], output="$WORK/combined.log", burnin=10)
assert cmd == ["/opt/env/bin/logcombiner", "-b", "10", "-o", "$WORK/combined.log", "$WORK/a.log", "$WORK/b.log"], cmd
# version
assert skill.build_command("version") == ["/opt/env/bin/beast", "-version"]
# 线程优先级：--threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("beast", 8) == 8
assert skill._effective_threads("beast", None) == 8      # per_subcommand_threads.beast = 8
assert skill._effective_threads("treeannotator", None) == 4
print("  OK: beast/treeannotator/logcombiner/version argv + 线程优先级")

ns = build_parser().parse_args(["beast", "$WORK/input.xml", "--beagle", "--threads", "4", "--tmpdir", "$WORK"])
assert ns.subcommand == "beast" and ns.beagle and ns.threads == 4 and ns.tmpdir == "$WORK", ns
print("  OK: parser beast")
PY

echo "==> [4/5] 未知子命令应报错"
if python "$NATIVE/main.py" notacommand 2>/dev/null; then
    echo "  [FAIL] 未知子命令未报错" >&2; exit 1
else
    echo "  OK: 未知子命令被拒绝"
fi

echo "==> [5/5] BEAST2 冒烟（若已安装；Java≥20 末尾可能报错，属已知兼容问题）"
if command -v beast >/dev/null 2>&1; then
    beast -version 2>&1 | grep -m1 -E "^v?2\." || true
else
    echo "  beast 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
