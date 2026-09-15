#!/usr/bin/env bash
# goseq native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + goseq【可选】：若 Rscript 可用且已安装 goseq 包，会额外做 library() 冒烟
#     （不做真实富集，避免依赖 GO.db / 具体物种）；否则仅 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（goseq 输入格式）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/gene_lengths.tsv" && test -f "$WORK/gene2go.tsv" && test -f "$WORK/de_genes.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^go'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "goseq", d.get("title")
for k in ("subcommand", "genes", "lengths", "gene2cat", "output", "method", "test_cats", "threads"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证：go 生成 params.tsv 且键完整"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GoseqSkill, _R_DRIVER, build_parser

skill = GoseqSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "go", genes="$WORK/de_genes.txt", lengths="$WORK/gene_lengths.tsv",
    gene2cat="$WORK/gene2go.tsv", output="$WORK/go_enrichment.tsv",
    method="Wallenius", test_cats="GO:CC,GO:BP,GO:MF",
    use_genes_without_cat=True, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript", cmd
assert cmd[1] == "-e" and cmd[2] == _R_DRIVER, cmd
assert "nullp" in cmd[2] and "goseq(" in cmd[2], "内嵌 R 驱动应调用 nullp + goseq"
params = cmd[-1]
assert params.endswith("params.tsv"), params
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
for key in ("genes", "lengths", "gene2cat", "output", "method",
            "test_cats", "use_genes_without_cat", "threads"):
    assert key in pairs, f"params.tsv 缺少 {key}"
assert pairs["method"] == "Wallenius" and pairs["threads"] == "4", pairs
assert pairs["use_genes_without_cat"] == "TRUE", pairs
print("  OK:", " ".join(cmd[:2]), params)

ns = build_parser().parse_args(
    ["go", "--genes", "$WORK/de_genes.txt", "--lengths", "$WORK/gene_lengths.tsv",
     "--gene2cat", "$WORK/gene2go.tsv", "-o", "$WORK/go.tsv",
     "--method", "Hypergeometric", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "go" and ns.method == "Hypergeometric" and ns.threads == 8, ns
assert ns.tmpdir == "/tmp" and ns.use_genes_without_cat is True, ns
print("  OK: parser go（子命令后 --threads/--tmpdir）")
PY

echo "==> [4/5] argv 构造验证：--no-use-genes-without-cat 与空 test-cats"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GoseqSkill, build_parser

skill = GoseqSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command("go", genes="$WORK/de_genes.txt", lengths="$WORK/gene_lengths.tsv",
                          gene2cat="$WORK/gene2go.tsv", output="$WORK/go.tsv",
                          use_genes_without_cat=False, test_cats="", threads=2)
params = cmd[-1]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert pairs["use_genes_without_cat"] == "FALSE" and pairs["test_cats"] == "", pairs
print("  OK: use_genes_without_cat=FALSE + 空 test_cats")

ns = build_parser().parse_args(
    ["go", "--genes", "$WORK/de_genes.txt", "--lengths", "$WORK/gene_lengths.tsv",
     "--gene2cat", "$WORK/gene2go.tsv", "-o", "$WORK/go.tsv", "--no-use-genes-without-cat"]
)
assert ns.use_genes_without_cat is False, ns
print("  OK: parser --no-use-genes-without-cat")

# 缺必填 / 非法 method 应报错
for bad in (dict(genes=None, lengths="$WORK/x", gene2cat="$WORK/y", output="$WORK/z"),
            dict(genes="$WORK/a", lengths="$WORK/b", gene2cat="$WORK/c", output="$WORK/d",
                 method="Bad")):
    try:
        skill.build_command("go", **bad)
        raise AssertionError(f"应报错: {bad}")
    except RuntimeError:
        pass
print("  OK: 缺参与非法 method 校验")
PY

echo "==> [5/5] 真实冒烟（Rscript + goseq 可用时，仅 library 加载）"
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'suppressPackageStartupMessages(library(goseq))' >/dev/null 2>&1; then
    Rscript -e 'cat("goseq", as.character(packageVersion("goseq")), "\n")'
    echo "  OK: goseq 包可加载"
else
    echo "  Rscript/goseq 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
