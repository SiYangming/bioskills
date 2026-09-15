#!/usr/bin/env bash
# signalp native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - signalp 二进制【可选】：若已安装（PATH 中有 signalp 且持有授权模型），
#     会额外做 signalp -version 冒烟；否则跳过真实执行。
# 说明：SignalP 5.0 需授权模型 + 真实蛋白序列才能预测，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（最小蛋白质 FASTA）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：predict（13.md 分泌蛋白步骤1 参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SignalpSkill, build_parser
skill = SignalpSkill()
skill._resolve_binary = lambda: "/opt/signalp/bin/signalp"
cmd = skill.build_command(
    "predict", fasta="$WORK/proteins.fasta", organism="euk",
    batch=30000, gff3=True, prefix="proteins",
)
s = " ".join(cmd)
assert "/opt/signalp/bin/signalp" in s, s
assert "-org euk" in s, s
assert "-fasta $WORK/proteins.fasta" in s, s
assert "-batch 30000" in s, s
assert "-gff3" in s, s
assert "-prefix proteins" in s, s
assert "-mature" not in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/proteins.fasta", "-org", "euk", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser predict")
PY

echo "==> [4/6] argv 构造验证 #2：mature 与 organism 校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SignalpSkill
skill = SignalpSkill()
skill._resolve_binary = lambda: "signalp"
c = skill.build_command("mature", fasta="$WORK/proteins.fasta", organism="archaea")
s = " ".join(c)
assert "-mature" in s and "-org arch" in s, s
print("  OK mature:", s)

# 非法 -org 必须报错
try:
    skill.build_command("predict", fasta="$WORK/proteins.fasta", organism="human")
except ValueError as e:
    print("  OK organism 非法报错:", e)
else:
    raise AssertionError("非法 organism 应抛 ValueError")

# 缺 fasta 必须报错
try:
    skill.build_command("predict", organism="euk")
except ValueError as e:
    print("  OK 缺 fasta 报错:", e)
else:
    raise AssertionError("缺 fasta 应抛 ValueError")

# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("predict", 4) == 4
assert skill._effective_threads("predict", None) == 1   # meta per_subcommand_threads.predict=1
print("  OK threads priority")
PY

echo "==> [5/6] 线程不注入命令行（单线程工具契约）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SignalpSkill
skill = SignalpSkill()
skill._resolve_binary = lambda: "signalp"
c = skill.build_command("predict", fasta="x.fa", organism="euk", threads=8)
assert c == ["signalp", "-org", "euk", "-fasta", "x.fa"], c
print("  OK 未注入 -p/-threads:", " ".join(c))
PY

echo "==> [6/6] signalp 冒烟（若已安装且持有授权模型）"
if command -v signalp >/dev/null 2>&1; then
    signalp -version 2>&1 | head -n 2 || true
else
    echo "  signalp 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
