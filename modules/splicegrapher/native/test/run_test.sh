#!/usr/bin/env bash
# splicegrapher native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SpliceGrapher 脚本【可选】：若已安装（PATH 中有 build_classifiers.py 等），会额外做可执行探测；
#     否则跳过真实执行。
# 说明：SpliceGrapher 真实运行需参考基因组/基因模型/RNA-seq 并训练 SVM，耗时且需大数据，
#      因此对四个子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（最小基因组/GFF3/SAM/分类器占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：build_classifiers"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SpliceGrapherSkill, build_parser
skill = SpliceGrapherSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/build_classifiers.py"
cmd = skill.build_command("build_classifiers", donors="gt,gc", acceptors="ag",
                          num_examples=400, logfile="$WORK/cc.log")
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/build_classifiers.py"), s
assert "-d gt,gc" in s and "-a ag" in s and "-n 400" in s and "-l $WORK/cc.log" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["build_classifiers", "-d", "gt,gc", "-a", "ag", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "build_classifiers" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser build_classifiers")
PY

echo "==> [4/6] argv 构造验证 #2：sam_filter / predict_graphs"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SpliceGrapherSkill
skill = SpliceGrapherSkill()
skill._resolve_binary = lambda *a, **k: "sam_filter.py"
cmd = skill.build_command("sam_filter", input="$WORK/alignments.sam",
                          classifiers="$WORK/classifiers.zip",
                          output="$WORK/filtered.sam", verbose=True)
s = " ".join(cmd)
assert "sam_filter.py $WORK/alignments.sam $WORK/classifiers.zip" in s, s
assert "-o $WORK/filtered.sam" in s and s.endswith("-v"), s
print("  OK:", s)

skill._resolve_binary = lambda *a, **k: "predict_graphs.py"
cmd = skill.build_command("predict_graphs", input="$WORK/alignments.sam", verbose=True)
s = " ".join(cmd)
assert "predict_graphs.py $WORK/alignments.sam" in s and s.endswith("-v"), s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：realignment_pipeline"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SpliceGrapherSkill
skill = SpliceGrapherSkill()
skill._resolve_binary = lambda *a, **k: "realignment_pipeline.py"
cmd = skill.build_command("realignment_pipeline", input="$WORK/graphs",
                          fastq1="$WORK/A.1.fastq", fastq2="$WORK/A.2.fastq")
s = " ".join(cmd)
assert "realignment_pipeline.py $WORK/graphs" in s, s
assert "-1 $WORK/A.1.fastq -2 $WORK/A.2.fastq" in s, s
print("  OK:", s)
PY

echo "==> [6/6] SpliceGrapher 脚本存在性冒烟（若已安装）"
if command -v build_classifiers.py >/dev/null 2>&1; then
    echo "  已安装：$(command -v build_classifiers.py)"
else
    echo "  SpliceGrapher 脚本未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
