#!/usr/bin/env bash
# r_matrixeqtl native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + MatrixEQTL【可选】：若 Rscript 可用且已安装 MatrixEQTL 包，
#     会真实运行 analyze 并断言输出文件；否则退化为 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（MatrixEQTL 输入格式）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^analyze'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：analyze 生成 params.tsv 且键完整"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RMatrixEQTLSkill, build_parser

skill = RMatrixEQTLSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", snps="$WORK/snps.txt", gene="$WORK/ge.txt",
    output="$WORK/eqtl.txt", model="linear", pv_threshold=1e-2,
    pv_threshold_cis=0.05, cis_dist=1000000,
    snpspos="$WORK/snpspos.txt", genepos="$WORK/genepos.txt", threads=4,
)
s = " ".join(cmd)
assert "/opt/r/bin/Rscript" in s, s
assert "run_matrixeqtl.R" in s, s
params = [c for c in cmd if c.endswith("params.tsv")]
assert params, "缺少 params.tsv"
import os
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params[0]))
for key in ("snps", "gene", "output", "model", "pv_threshold",
            "pv_threshold_cis", "cis_dist", "snpspos", "genepos", "slice_size", "threads"):
    assert key in pairs, f"params.tsv 缺少 {key}"
assert pairs["model"] == "linear" and pairs["pv_threshold_cis"] == "0.05", pairs
print("  OK:", s)

ns = build_parser().parse_args(
    ["analyze", "$WORK/snps.txt", "$WORK/ge.txt", "-o", "$WORK/out.txt",
     "--model", "anova", "--pv-threshold", "1e-3", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "analyze" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser analyze")
PY

echo "==> [3b/5] argv 构造验证：--output-prefix 与别名参数（--trans-p/--cis-p/--snps-loc/--gene-loc）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RMatrixEQTLSkill, build_parser

skill = RMatrixEQTLSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", snps="$WORK/snps.txt", gene="$WORK/ge.txt",
    output_prefix="$WORK/eq", model="linear",
    pv_threshold=1e-6, pv_threshold_cis=1e-3,
    snpspos="$WORK/snpspos.txt", genepos="$WORK/genepos.txt",
    threads=4, pvalue_hist=True, quiet=True)
params = [c for c in cmd if c.endswith("params.tsv")][0]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert "output_prefix" in pairs and "output" not in pairs, pairs
assert pairs["pv_threshold"] == "1e-06" and pairs["pv_threshold_cis"] == "0.001", pairs
assert pairs.get("pvalue_hist") == "TRUE" and pairs.get("verbose") == "FALSE", pairs
print("  OK:", " ".join(cmd))

ns = build_parser().parse_args(
    ["analyze", "$WORK/snps.txt", "$WORK/ge.txt", "--output-prefix", "$WORK/eq",
     "--trans-p", "1e-6", "--cis-p", "1e-3",
     "--snps-loc", "$WORK/snpspos.txt", "--gene-loc", "$WORK/genepos.txt",
     "--pvalue-hist", "--quiet", "--threads", "8"])
assert ns.output_prefix == "$WORK/eq" and ns.output is None, ns
assert ns.pv_threshold == 1e-6 and ns.pv_threshold_cis == 1e-3, ns
assert ns.pvalue_hist and ns.quiet and ns.threads == 8, ns
print("  OK: parser 别名（--trans-p/--cis-p/--snps-loc/--gene-loc/--pvalue-hist/--quiet）")

# threads=auto / 缺省 → 不写 threads 键（R 驱动自动检测）；整数 → 显式 pin
def build_one(**extra):
    skill2 = RMatrixEQTLSkill()
    skill2._resolve_binary = lambda: "Rscript"
    skill2.tmpdir = "$WORK"
    return skill2.build_command(
        "analyze", snps="$WORK/snps.txt", gene="$WORK/ge.txt",
        output_prefix="$WORK/eqauto", **extra)

def read_pairs(cmd):
    params = [c for c in cmd if c.endswith("params.tsv")][0]
    return dict(line.rstrip("\n").split("\t", 1) for line in open(params))

assert "threads" not in read_pairs(build_one(threads="auto")), "auto 不应写 threads 键"
assert "threads" not in read_pairs(build_one()), "缺省不应写 threads 键（默认 auto）"
assert read_pairs(build_one(threads=4))["threads"] == "4", "整数应显式 pin"
ns2 = build_parser().parse_args(["analyze", "$WORK/snps.txt", "$WORK/ge.txt",
                                 "--output-prefix", "$WORK/e2", "--threads", "auto"])
assert ns2.threads == "auto", ns2
# 非法值（如 "bad"）应由 argparse 类型校验拒绝（SystemExit）
try:
    build_parser().parse_args(["analyze", "$WORK/snps.txt", "$WORK/ge.txt",
                               "-o", "$WORK/e3.txt", "--threads", "bad"])
    raise AssertionError("非法 --threads 值应被 argparse 拒绝")
except SystemExit:
    pass
print("  OK: threads auto/缺省省略键、整数 pin、parser 接受 auto")
PY

echo "==> [4/5] non-cis 模式 argv（无 snpspos/genepos 亦可）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RMatrixEQTLSkill
skill = RMatrixEQTLSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command("analyze", snps="$WORK/snps.txt", gene="$WORK/ge.txt",
                          output="$WORK/eqtl2.txt", pv_threshold=1e-2)
params = [c for c in cmd if c.endswith("params.tsv")][0]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert pairs["pv_threshold_cis"] == "0.0" and "snpspos" not in pairs, pairs
print("  OK: trans-only 参数文件")
PY

echo "==> [5/5] 真实回归（Rscript + MatrixEQTL 可用时）"
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'suppressPackageStartupMessages(library(MatrixEQTL))' >/dev/null 2>&1; then
    python "$NATIVE/main.py" analyze "$WORK/snps.txt" "$WORK/ge.txt" \
        -o "$WORK/eqtl_result.txt" --pv-threshold 1e-2 \
        --covariates "$WORK/covariates.txt" --threads 2 \
        > "$WORK/run.log" 2>&1
    test -s "$WORK/eqtl_result.txt" || { cat "$WORK/run.log"; exit 1; }
    grep -q '^gene_01' "$WORK/eqtl_result.txt" && echo "  OK: gene_01 显著关联出现"
    grep -q "RMATRIXEQTL_OK" "$WORK/run.log"
    echo "  OK: analyze 真实回归通过"
else
    echo "  Rscript/MatrixEQTL 未安装，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
