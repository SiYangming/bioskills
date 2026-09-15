#!/usr/bin/env bash
# wgcna native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + WGCNA【可选】：不真实执行 R；
#     本测试以 python heredoc 做 argv（Rscript -e 表达式）构造断言与 parser 断言。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（表达矩阵 + 性状数据）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/expression_matrix.txt"
test -s "$WORK/trait_data.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --list-commands | grep -q '^check'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：run（全流程 + 性状关联）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import WGCNAPythonSkill, build_parser

skill = WGCNAPythonSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "run", expr="$WORK/expression_matrix.txt", outdir="$WORK/wgcna_out",
    trait="$WORK/trait_data.txt", power=6, min_module_size=30,
    merge_cut_height=0.25, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript" and cmd[1] == "-e", cmd
expr = cmd[2]
for key in ("goodSamplesGenes", "pickSoftThreshold", "adjacency", "TOMsimilarity",
            "cutreeDynamic", "mergeCloseModules", "corPvalueStudent",
            "gene_module_assignment.txt", "module_eigengenes.txt",
            "module_trait_correlation.txt", "cutHeight=0.25", "minClusterSize=30"):
    assert key in expr, f"缺少 {key}"
assert "power <- 6" in expr, expr
assert "allowWGCNAThreads(nThreads=4)" in expr, expr
assert "$WORK/wgcna_out" in expr, expr
assert "WGCNA_OK" in expr, expr
print("  OK: run ->", expr.splitlines()[-1])

ns = build_parser().parse_args(
    ["run", "$WORK/expression_matrix.txt", "--outdir", "$WORK/out",
     "--power", "12", "--min-module-size", "20", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.power == 12 and ns.min_module_size == 20, ns
assert ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证：run（自动软阈值，无性状）+ check"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import WGCNAPythonSkill, build_parser

skill = WGCNAPythonSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"

cmd = skill.build_command("run", expr="$WORK/expression_matrix.txt", outdir="$WORK/out2", threads=2)
expr = cmd[2]
assert "power <- sft\$powerEstimate" in expr, expr
assert "module_trait_correlation" not in expr, "未提供 trait 时不应做性状关联"
assert "if (is.na(power) || power < 1) power <- 6" in expr, expr
print("  OK: run 自动软阈值")

cmd2 = skill.build_command("check", expr="$WORK/expression_matrix.txt",
                           output="$WORK/qc.txt", threads=2)
expr2 = cmd2[2]
assert "WGCNA_OK" in expr2 and "goodSamplesGenes" in expr2, expr2
assert "$WORK/qc.txt" in expr2, expr2
print("  OK: check")

ns = build_parser().parse_args(
    ["check", "$WORK/expression_matrix.txt", "-o", "$WORK/qc2.txt", "--threads", "4"])
assert ns.subcommand == "check" and ns.output == "$WORK/qc2.txt", ns
print("  OK: parser check")
PY

echo "==> [5/5] R 环境冒烟（若已安装 Rscript）"
if command -v Rscript >/dev/null 2>&1; then
    Rscript --version 2>&1 | head -n 1
else
    echo "  Rscript 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
