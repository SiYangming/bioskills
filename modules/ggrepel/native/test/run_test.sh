#!/usr/bin/env bash
# ggrepel native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + ggrepel（含 ggplot2）【可选】：不真实执行 R；
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
python "$NATIVE/main.py" --list-commands | grep -q '^label'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：label（火山图基因标签）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GgrepelSkill, build_parser

skill = GgrepelSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "label", deg_table="$WORK/DESeq2_results.txt", output="$WORK/volcano_labeled.pdf",
    top=20, max_overlaps=20, lfc_col="log2FoldChange", padj_col="padj",
    lfc_cutoff=1, padj_cutoff=0.05, title="Volcano Plot with Gene Labels",
    width=8, height=6, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript" and cmd[1] == "-e", cmd
expr = cmd[2]
for key in ("library(ggrepel)", "geom_text_repel", "geom_point", "ggsave(",
            "aes(label=gene)", "max.overlaps=20", "GGREPEL_OK"):
    assert key in expr, f"缺少 {key}"
assert 'res0[["log2FoldChange"]]' in expr and 'res0[["padj"]]' in expr, expr
assert "head(df[order(df\$padj), , drop=FALSE], 20)" in expr, expr
assert "$WORK/volcano_labeled.pdf" in expr, expr
print("  OK: label ->", expr.splitlines()[-1])

ns = build_parser().parse_args(
    ["label", "$WORK/DESeq2_results.txt", "-o", "$WORK/v.png",
     "--top", "10", "--max-overlaps", "30", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "label" and ns.top == 10 and ns.max_overlaps == 30, ns
assert ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser label")
PY

echo "==> [4/5] argv 构造验证：自定义列名 + 非法参数拒绝"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GgrepelSkill

skill = GgrepelSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "label", deg_table="$WORK/DESeq2_results.txt", output="$WORK/v2.pdf",
    top=5, lfc_col="stat", padj_col="FDR", max_overlaps=5, threads=2,
)
expr = cmd[2]
assert 'res0[["stat"]]' in expr and 'res0[["FDR"]]' in expr, expr
assert "drop=FALSE], 5)" in expr, expr
assert "max.overlaps=5" in expr, expr

# --top<=0 应被拒绝
try:
    skill.build_command("label", deg_table="$WORK/DESeq2_results.txt",
                        output="$WORK/v3.pdf", top=0)
    raise AssertionError("--top<=0 应被拒绝")
except RuntimeError:
    pass
# 非法列名应被拒绝
try:
    skill.build_command("label", deg_table="$WORK/DESeq2_results.txt",
                        output="$WORK/v4.pdf", padj_col="p adj")
    raise AssertionError("非法列名应被拒绝")
except RuntimeError:
    pass
print("  OK: 自定义列名 + 非法 --top/列名拒绝")
PY

echo "==> [5/5] R 环境冒烟（若已安装 Rscript）"
if command -v Rscript >/dev/null 2>&1; then
    Rscript --version 2>&1 | head -n 1
else
    echo "  Rscript 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
