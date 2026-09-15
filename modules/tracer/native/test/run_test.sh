#!/usr/bin/env bash
# tracer native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - tracer【可选】：Tracer 为交互式 Java GUI，无法在无头环境执行，
#     因此统一以「python 构造 argv 验证命令构建」的方式断言；不执行真实 GUI。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（MCMC trace 日志）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：run（单/多日志载入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TracerSkill, build_parser

skill = TracerSkill()
skill._resolve_binary = lambda: "/opt/env/bin/tracer"

# 单日志
cmd = skill.build_command("run", logs="$WORK/beast.log")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/tracer", s
assert cmd[1] == "$WORK/beast.log", s
print("  OK:", s)

# 多日志（list）
cmd = skill.build_command("run", logs=["$WORK/beast.log", "$WORK/beast2.log"])
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/tracer", s
assert cmd[1:] == ["$WORK/beast.log", "$WORK/beast2.log"], s
print("  OK:", s)

# 无日志（仅打开 GUI）也应构造出纯启动器命令
cmd = skill.build_command("run")
assert cmd == ["/opt/env/bin/tracer"], cmd
print("  OK:", " ".join(cmd))

# parser 可解析子命令后 --threads/--tmpdir（接口统一）
ns = build_parser().parse_args(["run", "$WORK/beast.log", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.logs == ["$WORK/beast.log"], ns
print("  OK: parser run --threads/--tmpdir")

# 未知子命令应报错
try:
    skill.build_command("nope")
    raise AssertionError("未知子命令应抛 ValueError")
except ValueError:
    print("  OK: 未知子命令被拒绝")
PY

echo "==> [4/4] CLI 端到端（monkeypatch 二进制后 dry-run 不启动 GUI）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
import main as m

# 用 monkeypatch 让 _resolve_binary 返回假路径，并把 base.run_command 替换为记录器，
# 避免真正启动 GUI。
captured = {}
import base
m.TracerSkill._resolve_binary = lambda self: "tracer"
def fake_run_command(args, **kw):
    captured["args"] = list(args)
    class R:
        returncode = 0
        stdout = ""
        stderr = ""
    return R()
base.run_command = fake_run_command

rc = m.main(["run", "$WORK/beast.log", "$WORK/beast2.log"])
assert rc == 0, rc
assert captured["args"][0].endswith("tracer"), captured["args"]
assert captured["args"][1:] == ["$WORK/beast.log", "$WORK/beast2.log"], captured["args"]
print("  OK: main() 端到端 argv =", " ".join(captured["args"]))
PY

echo "ALL TESTS PASSED"
