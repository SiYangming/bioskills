#!/usr/bin/env bash
# pheatmap native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + pheatmap【可选】：不真实执行 R；
#     本测试以 python heredoc 做 argv（Rscript -e 表达式）构造断言与 parser 断言。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（表达矩阵 + 样品注释）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/DEG_expression_matrix.txt"
test -s "$WORK/sample_annotation.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^plot'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：plot（来自 docs/09.md 5.1 热图参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PheatmapSkill, build_parser

skill = PheatmapSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "plot", matrix="$WORK/DEG_expression_matrix.txt", output="$WORK/heatmap.pdf",
    scale="row", log2=True, cluster_rows=True, cluster_cols=True,
    show_rownames=False, show_colnames=True,
    annotation="$WORK/sample_annotation.txt",
    title="Differential Gene Expression Heatmap", width=8, height=10, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript" and cmd[1] == "-e", cmd
expr = cmd[2]
assert "pheatmap(m," in expr, expr
assert 'scale="row"' in expr, expr
assert "show_rownames=FALSE" in expr and "show_colnames=TRUE" in expr, expr
assert "cluster_rows=TRUE" in expr and "cluster_cols=TRUE" in expr, expr
assert "log2(m + 1)" in expr, expr
assert "$WORK/heatmap.pdf" in expr, expr
assert "$WORK/sample_annotation.txt" in expr, expr
assert "colorRampPalette" in expr and "PHEATMAP_OK" in expr, expr
print("  OK: plot ->", expr.splitlines()[-1])

ns = build_parser().parse_args(
    ["plot", "$WORK/DEG_expression_matrix.txt", "-o", "$WORK/h.png",
     "--scale", "column", "--no-log2", "--show-rownames", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "plot" and ns.scale == "column" and ns.log2 is False, ns
assert ns.show_rownames is True and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser plot")
PY

echo "==> [4/5] argv 构造验证：默认参数（无注释、log2 默认开）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PheatmapSkill

skill = PheatmapSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command("plot", matrix="$WORK/DEG_expression_matrix.txt",
                          output="$WORK/h2.pdf", threads=2)
expr = cmd[2]
assert "ann <- NA" in expr, expr
assert "log2(m + 1)" in expr, expr
assert 'scale="row"' in expr, expr
# 非法 scale 应抛错
try:
    skill.build_command("plot", matrix="$WORK/DEG_expression_matrix.txt",
                        output="$WORK/h3.pdf", scale="bogus")
    raise AssertionError("非法 --scale 应被拒绝")
except RuntimeError:
    pass
print("  OK: 默认参数 + 非法 scale 拒绝")
PY

echo "==> [5/5] R 环境冒烟（若已安装 Rscript）"
# 按任务要求测试不真实执行 R 分析；此处仅在装有 R 时打印版本做环境冒烟
if command -v Rscript >/dev/null 2>&1; then
    Rscript --version 2>&1 | head -n 1
else
    echo "  Rscript 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
