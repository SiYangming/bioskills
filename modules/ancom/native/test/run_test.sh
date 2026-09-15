#!/usr/bin/env bash
# ancom native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + ANCOM 源码【可选】：若 Rscript 可用且 ANCOM_HOME（或 ~/software/ANCOM）下有
#     programs/ancom.R，会真实运行 analyze 并断言结果 CSV；否则退化为 argv / params.tsv 构造验证
#     （无 R 环境亦可全绿）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 时在 native/ 产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（OTU 表 + 元数据）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^analyze'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：analyze 生成 params.tsv 且键完整"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AncomSkill, build_parser

skill = AncomSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", feature_table="$WORK/feature-table.tsv", metadata="$WORK/sample-metadata.tsv",
    output="$WORK/ancom_result.csv", sample_var="SampleID", main_var="Subject",
    group_var="Subject", out_cut=0.05, zero_cut=0.9, lib_cut=0, neg_lb=True,
    p_adj_method="BH", alpha=0.05, adj_formula="BodySite",
    rand_formula="~ 1 | Subject", ancom_home="$WORK/ANCOM", threads=4,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/r/bin/Rscript", cmd
assert "run_ancom.R" in s, s
params = [c for c in cmd if c.endswith("params.tsv")]
assert params, "缺少 params.tsv"
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params[0]))
for key in ("feature_table", "metadata", "output", "sample_var", "main_var",
            "group_var", "out_cut", "zero_cut", "lib_cut", "neg_lb",
            "p_adj_method", "alpha", "adj_formula", "rand_formula", "ancom_home"):
    assert key in pairs, f"params.tsv 缺少 {key}"
assert pairs["sample_var"] == "SampleID" and pairs["main_var"] == "Subject", pairs
assert pairs["neg_lb"] == "TRUE" and pairs["p_adj_method"] == "BH", pairs
assert pairs["ancom_home"] == "$WORK/ANCOM", pairs
print("  OK:", s)

ns = build_parser().parse_args(
    ["analyze", "$WORK/feature-table.tsv", "$WORK/sample-metadata.tsv",
     "--sample-var", "SampleID", "--main-var", "Subject", "-o", "$WORK/out.csv",
     "--alpha", "0.01", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "analyze" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.sample_var == "SampleID" and ns.main_var == "Subject" and ns.alpha == 0.01, ns
print("  OK: parser analyze")
PY

echo "==> [3b/5] params.tsv 缺省值 + 非法/缺参报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AncomSkill

skill = AncomSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", feature_table="$WORK/feature-table.tsv", metadata="$WORK/sample-metadata.tsv",
    output="$WORK/out2.csv", sample_var="SampleID", main_var="Subject")
params = [c for c in cmd if c.endswith("params.tsv")][0]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert pairs["out_cut"] == "0.05" and pairs["zero_cut"] == "0.9", pairs
assert pairs["lib_cut"] == "0" and pairs["neg_lb"] == "FALSE", pairs
assert pairs["p_adj_method"] == "BH" and pairs["alpha"] == "0.05", pairs
assert "group_var" not in pairs and "adj_formula" not in pairs, pairs
print("  OK: 缺省值 / 可选键省略")

for bad in (
    dict(metadata="$WORK/sample-metadata.tsv", output="$WORK/o.csv",
         sample_var="SampleID", main_var="Subject"),                       # 缺 feature_table
    dict(feature_table="$WORK/feature-table.tsv", output="$WORK/o.csv",
         sample_var="SampleID", main_var="Subject"),                       # 缺 metadata
    dict(feature_table="$WORK/feature-table.tsv", metadata="$WORK/sample-metadata.tsv",
         sample_var="SampleID", main_var="Subject"),                       # 缺 output
    dict(feature_table="$WORK/feature-table.tsv", metadata="$WORK/sample-metadata.tsv",
         output="$WORK/o.csv", main_var="Subject"),                        # 缺 sample_var
    dict(feature_table="$WORK/feature-table.tsv", metadata="$WORK/sample-metadata.tsv",
         output="$WORK/o.csv", sample_var="SampleID"),                     # 缺 main_var
):
    try:
        skill.build_command("analyze", **bad)
        raise AssertionError(f"缺必填参数应报错: {bad}")
    except ValueError:
        pass

# parser 缺 --sample-var/--main-var/--output 应由 argparse 拒绝（SystemExit）
for bad_argv in (
    ["analyze", "$WORK/feature-table.tsv", "$WORK/sample-metadata.tsv", "-o", "$WORK/o.csv"],
    ["analyze", "$WORK/feature-table.tsv", "$WORK/sample-metadata.tsv",
     "--sample-var", "SampleID", "--main-var", "Subject"],
):
    try:
        from main import build_parser as bp
        bp().parse_args(bad_argv)
        raise AssertionError(f"缺必填参数应被 argparse 拒绝: {bad_argv}")
    except SystemExit:
        pass
print("  OK: 缺必填参数报错（build_command + parser）")
PY

echo "==> [4/5] ANCOM_HOME 环境变量回退（未传 --ancom-home 时不写该键）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AncomSkill
skill = AncomSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command("analyze", feature_table="$WORK/feature-table.tsv",
                          metadata="$WORK/sample-metadata.tsv", output="$WORK/out3.csv",
                          sample_var="SampleID", main_var="Subject")
params = [c for c in cmd if c.endswith("params.tsv")][0]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert "ancom_home" not in pairs, "未传 --ancom-home 时不应写 ancom_home（由 run_ancom.R 回退 ANCOM_HOME）"
print("  OK: ancom_home 回退交 driver 处理")
PY

echo "==> [5/5] 真实回归（Rscript + ANCOM 源码可用时）"
ANCOM_HOME_RESOLVED="${ANCOM_HOME:-$HOME/software/ANCOM}"
if command -v Rscript >/dev/null 2>&1 && [[ -f "$ANCOM_HOME_RESOLVED/programs/ancom.R" ]]; then
    python "$NATIVE/main.py" analyze "$WORK/feature-table.tsv" "$WORK/sample-metadata.tsv" \
        --sample-var SampleID --main-var Subject -o "$WORK/ancom_result.csv" \
        --ancom-home "$ANCOM_HOME_RESOLVED" \
        > "$WORK/run.log" 2>&1
    test -s "$WORK/ancom_result.csv" || { cat "$WORK/run.log"; exit 1; }
    grep -q "ANCOM_OK" "$WORK/run.log"
    echo "  OK: analyze 真实回归通过"
else
    echo "  Rscript/ANCOM 源码未就绪，跳过真实回归（argv/params 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
