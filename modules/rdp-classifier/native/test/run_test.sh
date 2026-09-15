#!/usr/bin/env bash
# rdp-classifier native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - rdp_classifier 二进制【可选】：若已安装（conda activate / PATH 中有 rdp_classifier），
#     会额外做一次 --help 冒烟；否则跳过真实执行。
# 说明：RDP Classifier 需要真实 16S 序列 + 训练集才能产出分类结果，合成数据无法覆盖真实计算，
#      因此对 classify 采用「python 构造 argv 验证命令构建不崩溃且 JAVA_OPTS 透传」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 时在 native/ 产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（查询 FASTA + 训练集占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^classify'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：classify（JAVA_OPTS 透传 + 选项顺序）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RdpClassifierSkill, build_parser

skill = RdpClassifierSkill()
skill._resolve_binary = lambda: "/opt/env/bin/rdp_classifier"
cmd = skill.build_command(
    "classify", query="$WORK/rep_set.fna",
    train_propfile="$WORK/rRNAClassifier.properties",
    output="$WORK/rdp_assigned_taxonomy.txt",
    format="allrank", conf=0.8, min_words=5, threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/rdp_classifier", cmd
# JAVA_OPTS（env_vars 默认 -Xmx6g）应透传为 JVM 参数，置于 classify 之前
assert "-Xmx6g" in cmd, s
assert cmd.index("-Xmx6g") < cmd.index("classify"), s
assert "classify" in cmd, s
assert "-t $WORK/rRNAClassifier.properties" in s, s
assert "-o $WORK/rdp_assigned_taxonomy.txt" in s, s
assert "-f allrank" in s, s
assert "-c 0.8" in s, s
assert "-w 5" in s, s
assert s.rstrip().endswith("$WORK/rep_set.fna"), s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["classify", "$WORK/rep_set.fna", "-o", "$WORK/out.txt",
     "-f", "fixrank", "-c", "0.9", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "classify" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.query == "$WORK/rep_set.fna" and ns.conf == 0.9, ns
print("  OK: parser classify")
PY

echo "==> [4/5] argv 构造验证：默认格式/无 -t 时仅用内置默认训练集"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RdpClassifierSkill

skill = RdpClassifierSkill()
skill._resolve_binary = lambda: "rdp_classifier"
cmd = skill.build_command("classify", query="$WORK/rep_set.fna", output="$WORK/out2.txt")
s = " ".join(cmd)
assert "-f fixrank" in s, s              # 默认格式 fixrank
assert "-c 0.8" in s, s                  # 默认置信度 0.8
assert "-t" not in cmd, s                # 未提供 -t 时不出现
assert s.rstrip().endswith("$WORK/rep_set.fna"), s
print("  OK:", s)

# 缺 query 应报错
try:
    skill.build_command("classify", output="$WORK/x.txt")
    raise AssertionError("缺少 query 应报错")
except ValueError:
    pass
print("  OK: 缺少 query 报错")
PY

echo "==> [5/5] rdp_classifier 冒烟（若已安装）"
if command -v rdp_classifier >/dev/null 2>&1; then
    (rdp_classifier 2>&1 || true) | head -n 3 || true
else
    echo "  rdp_classifier 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
