#!/usr/bin/env bash
# clusterprofiler native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + clusterProfiler + 物种注释库【可选】：不真实执行 R；
#     本测试以 python heredoc 做 argv（Rscript -e 表达式）构造断言与 parser 断言。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（DEG 列表 + DESeq2 结果表）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/DEG_list.txt"
test -s "$WORK/DESeq2_results.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^go'
python "$NATIVE/main.py" --list-commands | grep -q '^kegg'
python "$NATIVE/main.py" --list-commands | grep -q '^gsea'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：go（enrichGO）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClusterProfilerSkill, build_parser

skill = ClusterProfilerSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "go", gene_list="$WORK/DEG_list.txt", output="$WORK/GO_enrichment_results.txt",
    ont="ALL", orgdb="org.Mm.eg.db", keytype="SYMBOL", pvalue=0.05, qvalue=0.05,
    padjust="BH", threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript" and cmd[1] == "-e", cmd
expr = cmd[2]
assert "enrichGO" in expr, expr
assert 'OrgDb=org.Mm.eg.db' in expr, expr
assert 'ont="ALL"' in expr, expr
assert "pAdjustMethod=\\"BH\\"" in expr, expr
assert "$WORK/GO_enrichment_results.txt" in expr, expr
assert "MulticoreParam(workers=4)" in expr, expr
assert "CLUSTERPROFILER_OK" in expr, expr
print("  OK: go ->", expr.splitlines()[-1])

ns = build_parser().parse_args(
    ["go", "$WORK/DEG_list.txt", "-o", "$WORK/out.txt",
     "--ont", "BP", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "go" and ns.threads == 8 and ns.tmpdir == "/tmp" and ns.ont == "BP", ns
print("  OK: parser go")
PY

echo "==> [4/5] argv 构造验证：kegg（enrichKEGG + SYMBOL->ENTREZID）+ gsea（gseGO）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClusterProfilerSkill, build_parser

skill = ClusterProfilerSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "kegg", gene_list="$WORK/DEG_list.txt", output="$WORK/KEGG_enrichment_results.txt",
    organism="hsa", keytype="SYMBOL", pvalue=0.05, padjust="BH", qvalue=0.05, threads=2,
)
expr = cmd[2]
assert "enrichKEGG" in expr and "bitr" in expr, expr
assert 'organism="hsa"' in expr, expr
assert "$WORK/KEGG_enrichment_results.txt" in expr, expr
print("  OK: kegg")
# ENTREZID 输入时不做 bitr 转换
cmd2 = skill.build_command(
    "kegg", gene_list="$WORK/DEG_list.txt", output="$WORK/K2.txt",
    organism="mmu", keytype="ENTREZID", threads=2,
)
assert "entrez <- genes" in cmd2[2] and "bitr" not in cmd2[2], cmd2[2]
print("  OK: kegg ENTREZID 直通")

cmd3 = skill.build_command(
    "gsea", gene_rank="$WORK/DESeq2_results.txt", output="$WORK/GSEA_results.txt",
    rank_col="log2FoldChange", ont="BP", keytype="SYMBOL", pvalue=0.05, threads=4,
)
expr3 = cmd3[2]
assert "gseGO" in expr3 and 'res0[["log2FoldChange"]]' in expr3, expr3
assert "$WORK/GSEA_results.txt" in expr3, expr3
print("  OK: gsea")

ns = build_parser().parse_args(
    ["gsea", "$WORK/DESeq2_results.txt", "-o", "$WORK/g.txt",
     "--rank-col", "stat", "--ont", "MF"])
assert ns.rank_col == "stat" and ns.ont == "MF", ns
print("  OK: parser gsea")
PY

echo "==> [5/5] R 环境冒烟（若已安装 Rscript）"
if command -v Rscript >/dev/null 2>&1; then
    Rscript --version 2>&1 | head -n 1
else
    echo "  Rscript 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
