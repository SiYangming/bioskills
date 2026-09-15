#!/usr/bin/env bash
# paml native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - PAML 程序【可选】：若已安装（conda activate paml / PATH 中有 baseml），
#     会额外做 baseml banner（paml version 4.9i）冒烟；否则跳过真实执行。
# 说明：PAML 真实分析需要真实多序列比对与控制参数，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃 + 自省命令断言」的方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; find "$NATIVE" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; }
trap cleanup EXIT

echo "==> [1/5] 生成测试数据（最小 ctl + phy + trees）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/codeml.ctl" && test -f "$WORK/input.phy" && test -f "$WORK/input.trees"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for prog in baseml basemlg chi2 codeml evolver infinitesites mcmctree pamp yn00; do
    grep -q "^${prog}" "$WORK/commands.txt" || { echo "  [FAIL] --list-commands 缺少 ${prog}" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证（monkeypatch _resolve_program）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PamlSkill, build_parser, SUBCOMMANDS

skill = PamlSkill()
# monkeypatch：惰性解析二进制，测试不依赖真实安装
skill._resolve_program = lambda name: f"/opt/env/bin/{name}"

# 1) codeml + 显式 ctl
cmd = skill.build_command("codeml", ctl="$WORK/codeml.ctl", threads=8)
assert cmd == ["/opt/env/bin/codeml", "$WORK/codeml.ctl"], cmd
# 2) mcmctree 默认 ctl（省略时为 <subcommand>.ctl）
cmd = skill.build_command("mcmctree")
assert cmd == ["/opt/env/bin/mcmctree", "mcmctree.ctl"], cmd
# 3) yn00 + extra_args 透传
cmd = skill.build_command("yn00", ctl="$WORK/yn00.ctl", extra_args="-o out")
assert cmd == ["/opt/env/bin/yn00", "$WORK/yn00.ctl", "-o", "out"], cmd
# 4) 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("codeml", 8) == 8, skill._effective_threads("codeml", 8)
assert skill._effective_threads("mcmctree", None) == 4, skill._effective_threads("mcmctree", None)
assert skill._effective_threads("baseml", None) == 1, skill._effective_threads("baseml", None)
# build_command 会把线程写入 OMP_NUM_THREADS
skill.build_command("codeml", ctl="$WORK/codeml.ctl", threads=6)
assert skill.env_vars.get("OMP_NUM_THREADS") == "6", skill.env_vars
print("  OK: 9 个子命令 =", " ".join(SUBCOMMANDS))

# parser 可解析完整 argv（子命令后 --threads/--tmpdir）
ns = build_parser().parse_args(["codeml", "$WORK/codeml.ctl", "--threads", "4", "--tmpdir", "$WORK"])
assert ns.subcommand == "codeml" and ns.threads == 4 and ns.tmpdir == "$WORK", ns
print("  OK: parser codeml")
PY

echo "==> [4/5] 未知子命令应报错"
if python "$NATIVE/main.py" notaprogram 2>/dev/null; then
    echo "  [FAIL] 未知子命令未报错" >&2; exit 1
else
    echo "  OK: 未知子命令被拒绝"
fi

echo "==> [5/5] PAML 冒烟（若已安装）"
if command -v baseml >/dev/null 2>&1; then
    baseml 2>&1 | head -n 1 || true
else
    echo "  baseml 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
