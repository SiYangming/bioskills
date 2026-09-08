#!/usr/bin/env bash
# quantifypolya native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + QuantifyPolyA【可选】：若 Rscript 可用且已安装 QuantifyPolyA 包，
#     会真实运行 quant（Load+Cluster，无 gff 冒烟）并断言输出文件；
#     否则退化为 argv 构造验证（任务要求的降级路径）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（每样本 poly(A) BED + colData）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/bed/brain1.bed" && test -f "$WORK/colData.tsv"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^quant'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证：quant（bed-dir + colData + contrast）生成 params.tsv 且键完整"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import QuantifyPolyASkill, build_parser

skill = QuantifyPolyASkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "quant", bed_dir="$WORK/bed", outdir="$WORK/out1",
    col_data="$WORK/colData.tsv", contrast="condition,Brain,UHR",
    quant_mode="canonical", max_gapwidth=24, threads=4, quiet=True,
)
s = " ".join(cmd)
assert "/opt/r/bin/Rscript" in s and "run_quantifypolya.R" in s, s
params = [c for c in cmd if c.endswith("params.tsv")]
assert params, "缺少 params.tsv"
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params[0]))
for key in ("bed_dir", "outdir", "col_data", "contrast", "quant_mode",
            "max_gapwidth", "threads", "quiet"):
    assert key in pairs, f"params.tsv 缺少 {key}"
assert pairs["bed_dir"].endswith("/bed") and "params" not in pairs["bed_dir"], pairs
assert pairs["quant_mode"] == "canonical" and pairs["contrast"] == "condition,Brain,UHR", pairs
assert pairs["max_gapwidth"] == "24" and pairs["threads"] == "4" and pairs["quiet"] == "TRUE", pairs
print("  OK:", s)

ns = build_parser().parse_args(
    ["quant", "--bed-dir", "$WORK/bed", "--outdir", "$WORK/o",
     "--col-data", "$WORK/colData.tsv", "--contrast", "condition,Brain,UHR",
     "--quant-mode", "gene", "--max-gapwidth", "50",
     "--min-count", "5", "--min-sample", "2", "--save-rds",
     "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "quant" and ns.quant_mode == "gene", ns
assert ns.max_gapwidth == 50 and ns.min_count == 5 and ns.min_sample == 2, ns
assert ns.save_rds and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser quant（全参数）")
PY

echo "==> [4/6] argv 构造验证：--bed-files 列表、可选键缺省省略、fasta/gff 透传"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import QuantifyPolyASkill, build_parser

skill = QuantifyPolyASkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"

def build_one(**extra):
    sk = QuantifyPolyASkill()
    sk._resolve_binary = lambda: "Rscript"
    sk.tmpdir = "$WORK"
    return sk.build_command("quant", bed_dir="$WORK/bed", outdir="$WORK/o", **extra)

def read_pairs(cmd):
    params = [c for c in cmd if c.endswith("params.tsv")][0]
    return dict(line.rstrip("\n").split("\t", 1) for line in open(params))

# 缺省值：quant_mode/max_gapwidth 写显式默认，threads/save_rds/quiet 等省略
p = read_pairs(build_one())
assert p["quant_mode"] == "canonical" and p["max_gapwidth"] == "24", p
for absent in ("threads", "save_rds", "quiet", "fasta", "gff", "col_data", "contrast", "min_count"):
    assert absent not in p, f"{absent} 不应写入（缺省）"
print("  OK: 缺省省略规则")

# fasta/gff 存在时写入绝对路径
p = read_pairs(build_one(fasta="$WORK/genome.fa", gff="$WORK/anno.gff3"))
assert p["fasta"].endswith("/genome.fa") and p["gff"].endswith("/anno.gff3"), p
print("  OK: fasta/gff 透传")

# --bed-files 逗号列表 → 逗号分隔的绝对路径
cmd = skill.build_command("quant", bed_files="$WORK/bed/brain1.bed,$WORK/bed/uhr1.bed",
                          outdir="$WORK/o2")
p = read_pairs(cmd)
assert "bed_dir" not in p and "bed_files" in p, p
assert p["bed_files"] == "$WORK/bed/brain1.bed,$WORK/bed/uhr1.bed", p
print("  OK:", " ".join(cmd))

# threads=auto 省略键；非法 quant_mode / threads 值由 argparse 拒绝
assert "threads" not in read_pairs(build_one(threads="auto"))
try:
    build_parser().parse_args(["quant", "--bed-dir", "$WORK/bed", "--outdir", "$WORK/o",
                               "--quant-mode", "bad"])
    raise AssertionError("非法 --quant-mode 应被 argparse 拒绝")
except SystemExit:
    pass
try:
    build_parser().parse_args(["quant", "--bed-dir", "$WORK/bed", "--outdir", "$WORK/o",
                               "--threads", "bad"])
    raise AssertionError("非法 --threads 值应被 argparse 拒绝")
except SystemExit:
    pass
# 缺少 --bed-dir/--bed-files 应被 mutually-exclusive required 拒绝
try:
    build_parser().parse_args(["quant", "--outdir", "$WORK/o"])
    raise AssertionError("缺少输入（bed-dir/bed-files）应被 argparse 拒绝")
except SystemExit:
    pass
print("  OK: threads=auto 省略键、非法值拒绝、必填互斥组")
PY

echo "==> [5/6] build_command 运行时校验：缺输入/缺 outdir 报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import QuantifyPolyASkill
skill = QuantifyPolyASkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
for kw in (dict(outdir="$WORK/o"),                     # 缺 bed 输入
           dict(bed_dir="$WORK/bed"),                  # 缺 outdir
           dict(bed_dir="$WORK/bed", outdir="$WORK/o", quant_mode="x")):  # 非法 mode
    try:
        skill.build_command("quant", **kw)
        raise AssertionError("应抛出 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
try:
    skill.build_command("analyze", bed_dir="$WORK/bed", outdir="$WORK/o")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] 真实回归（Rscript + QuantifyPolyA 可用时；Load+Cluster 无 gff 冒烟）"
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'suppressPackageStartupMessages(library(QuantifyPolyA))' >/dev/null 2>&1; then
    python "$NATIVE/main.py" quant --bed-dir "$WORK/bed" --outdir "$WORK/real_out" \
        --threads 2 --quiet > "$WORK/run.log" 2>&1
    test -s "$WORK/real_out/polyA_sites.tsv" || { cat "$WORK/run.log"; exit 1; }
    grep -q "QUANTIFYPOLYA_OK" "$WORK/run.log"
    echo "  OK: quant 真实回归通过（polyA_sites.tsv 已产出）"
elif command -v Rscript >/dev/null 2>&1; then
    echo "  Rscript 可用但 QuantifyPolyA 包未安装（bash native/install.sh 安装），跳过真实回归（argv 构造验证已通过）"
else
    echo "  Rscript 不可用，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
