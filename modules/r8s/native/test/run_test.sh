#!/usr/bin/env bash
# r8s native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - r8s 二进制【可选】：若已安装（native/install.sh 编译 / brew install r8s / 自建容器），
#     会额外做 `r8s -v -b` 版本冒烟；否则跳过真实执行。
# 说明：r8s 真实分析需要 NEXUS 树 + 化石校准，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃 + 自省命令断言」的方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; find "$NATIVE" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; }
trap cleanup EXIT

echo "==> [1/5] 生成测试数据（最小 NEXUS 输入）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/r8s_in.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^run" "$WORK/commands.txt"
grep -q "^version" "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证（monkeypatch _resolve_program）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import R8sSkill, build_parser

skill = R8sSkill()
skill._resolve_program = lambda: "/opt/env/bin/r8s"   # monkeypatch：惰性解析二进制

cmd = skill.build_command("run", input="$WORK/r8s_in.txt")
assert cmd == ["/opt/env/bin/r8s", "-b", "-f", "$WORK/r8s_in.txt"], cmd
cmd = skill.build_command("version")
assert cmd == ["/opt/env/bin/r8s", "-v", "-b"], cmd
# extra_args 透传
cmd = skill.build_command("run", input="$WORK/r8s_in.txt", extra_args="-r")
assert cmd == ["/opt/env/bin/r8s", "-b", "-f", "$WORK/r8s_in.txt", "-r"], cmd
# 缺 input 应报错
try:
    skill.build_command("run")
    raise AssertionError("run 缺 input 未报错")
except ValueError:
    pass
# 线程优先级：--threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("run", 8) == 8
assert skill._effective_threads("run", None) == 4
assert skill._effective_threads("version", None) == 1
skill.build_command("run", input="$WORK/r8s_in.txt", threads=6)
assert skill.env_vars.get("OMP_NUM_THREADS") == "6", skill.env_vars
print("  OK: run/version argv + 线程优先级")

# parser：位置参数与 -f/--input 等价，子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["run", "$WORK/r8s_in.txt", "--threads", "4", "--tmpdir", "$WORK"])
assert ns.subcommand == "run" and ns.input == "$WORK/r8s_in.txt" and ns.threads == 4, ns
ns2 = build_parser().parse_args(["run", "--input", "$WORK/r8s_in.txt"])
assert ns2.input_opt == "$WORK/r8s_in.txt", ns2
print("  OK: parser run")
PY

echo "==> [4/5] 未知子命令应报错"
if python "$NATIVE/main.py" notacommand 2>/dev/null; then
    echo "  [FAIL] 未知子命令未报错" >&2; exit 1
else
    echo "  OK: 未知子命令被拒绝"
fi

echo "==> [5/5] r8s 冒烟（若已安装；r8s -v -b 退出码 1 属正常）"
if command -v r8s >/dev/null 2>&1; then
    r8s -v -b 2>&1 | head -n 1 || true
else
    echo "  r8s 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
