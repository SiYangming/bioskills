#!/usr/bin/env bash
# ggplot2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + ggplot2【可选】：不真实执行 R；
#     本测试以 python heredoc 做 argv（Rscript -e 表达式）构造断言与 parser 断言。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（DESeq2 结果表）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/DESeq2_results.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^volcano'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：volcano（火山图参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Ggplot2Skill, build_parser

skill = Ggplot2Skill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "volcano", deg_table="$WORK/DESeq2_results.txt", output="$WORK/volcano_plot.pdf",
    lfc_col="log2FoldChange", padj_col="padj", lfc_cutoff=1, padj_cutoff=0.05,
    title="Volcano Plot of Differential Gene Expression", width=8, height=6, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript" and cmd[1] == "-e", cmd
expr = cmd[2]
for key in ("library(ggplot2)", "geom_point", "scale_color_manual", "geom_vline",
            "geom_hline", "theme_bw", "ggsave(", "GGPLOT2_OK"):
    assert key in expr, f"缺少 {key}"
assert 'res0[["log2FoldChange"]]' in expr, expr
assert 'res0[["padj"]]' in expr, expr
assert 'c(-1.0, 1.0)' in expr, expr
assert 'yintercept=-log10(0.05)' in expr, expr
assert "$WORK/volcano_plot.pdf" in expr, expr
assert "geom_text_repel" not in expr, "火山图子命令不含标签（标签见 ggrepel 模块）"
print("  OK: volcano ->", expr.splitlines()[-1])

ns = build_parser().parse_args(
    ["volcano", "$WORK/DESeq2_results.txt", "-o", "$WORK/v.png",
     "--padj-col", "FDR", "--lfc-cutoff", "2", "--padj-cutoff", "0.01",
     "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "volcano" and ns.padj_col == "FDR", ns
assert ns.lfc_cutoff == 2 and ns.padj_cutoff == 0.01 and ns.threads == 2, ns
print("  OK: parser volcano")
PY

echo "==> [4/5] argv 构造验证：自定义列名 + 非法列名拒绝"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Ggplot2Skill

skill = Ggplot2Skill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "volcano", deg_table="$WORK/DESeq2_results.txt", output="$WORK/v2.pdf",
    lfc_col="stat", padj_col="FDR", lfc_cutoff=2, padj_cutoff=0.01, threads=2,
)
expr = cmd[2]
assert 'res0[["stat"]]' in expr and 'res0[["FDR"]]' in expr, expr
assert 'c(-2.0, 2.0)' in expr, expr

# 非法列名（含空格/特殊字符）应被拒绝
try:
    skill.build_command("volcano", deg_table="$WORK/DESeq2_results.txt",
                        output="$WORK/v3.pdf", lfc_col="log2 FC")
    raise AssertionError("非法列名应被拒绝")
except RuntimeError:
    pass
print("  OK: 自定义列名 + 非法列名拒绝")
PY

echo "==> [5/5] R 环境冒烟（若已安装 Rscript）"
if command -v Rscript >/dev/null 2>&1; then
    Rscript --version 2>&1 | head -n 1
else
    echo "  Rscript 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
