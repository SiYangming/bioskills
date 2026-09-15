#!/usr/bin/env bash
# pathview native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + pathview【可选】：若 Rscript 可用且已安装 pathview 包，会额外做 library() 冒烟
#     （不做真实出图，避免联网抓取 KEGG kgml）；否则仅 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（pathview 输入格式）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/study.ko.txt" && test -f "$WORK/cpd.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^plot'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "pathview", d.get("title")
for k in ("subcommand", "kegg_ids", "gene_data", "cpd_data", "species", "out_dir", "threads"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证：plot 生成 params.tsv 且键完整"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PathviewSkill, _R_DRIVER, build_parser

skill = PathviewSkill()
skill._resolve_binary = lambda: "/opt/r/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "plot", kegg_ids="ko00010,ko00020", gene_data="$WORK/study.ko.txt",
    cpd_data="$WORK/cpd.txt", species="ko", out_dir="$WORK/kegg_out",
    out_suffix="study1", gene_idtype="KEGG", cpd_idtype="KEGG",
    kegg_dir="$WORK", discrete=False, threads=4,
)
assert cmd[0] == "/opt/r/bin/Rscript", cmd
assert cmd[1] == "-e" and cmd[2] == _R_DRIVER, cmd
assert "pathview" in cmd[2] and "pathview::pathview" in cmd[2], "内嵌 R 驱动应调用 pathview::pathview"
params = cmd[-1]
assert params.endswith("params.tsv"), params
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
for key in ("kegg_ids", "gene_data", "cpd_data", "species", "out_dir",
            "out_suffix", "gene_idtype", "cpd_idtype", "kegg_dir", "threads"):
    assert key in pairs, f"params.tsv 缺少 {key}"
assert pairs["kegg_ids"] == "ko00010,ko00020" and pairs["threads"] == "4", pairs
print("  OK:", " ".join(cmd[:2]), params)

ns = build_parser().parse_args(
    ["plot", "--kegg-ids", "ko00010", "--gene-data", "$WORK/study.ko.txt",
     "--species", "hsa", "--out-dir", "$WORK/out", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "plot" and ns.kegg_ids == "ko00010" and ns.threads == 8, ns
assert ns.tmpdir == "/tmp" and ns.species == "hsa", ns
print("  OK: parser plot（子命令后 --threads/--tmpdir）")
PY

echo "==> [4/5] argv 构造验证：cpd-only 与 discrete 着色"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PathviewSkill
skill = PathviewSkill()
skill._resolve_binary = lambda: "Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command("plot", kegg_ids="ko00010", cpd_data="$WORK/cpd.txt",
                          discrete=True, threads=2)
params = cmd[-1]
pairs = dict(line.rstrip("\n").split("\t", 1) for line in open(params))
assert "gene_data" not in pairs and "cpd_data" in pairs, pairs
assert pairs.get("discrete") == "TRUE", pairs
print("  OK: cpd-only + discrete")
# 缺 kegg_ids / 缺数据 应报错
for bad in (dict(kegg_ids=None, gene_data="$WORK/study.ko.txt"),
            dict(kegg_ids="ko00010")):
    try:
        skill.build_command("plot", **bad)
        raise AssertionError(f"应报错: {bad}")
    except RuntimeError:
        pass
print("  OK: 缺参校验")
PY

echo "==> [5/5] 真实冒烟（Rscript + pathview 可用时，仅 library 加载）"
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'suppressPackageStartupMessages(library(pathview))' >/dev/null 2>&1; then
    Rscript -e 'cat("pathview", as.character(packageVersion("pathview")), "\n")'
    echo "  OK: pathview 包可加载"
else
    echo "  Rscript/pathview 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
