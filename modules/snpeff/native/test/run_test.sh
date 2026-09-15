#!/usr/bin/env bash
# snpeff native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - snpEff 二进制【可选】：若已安装（conda activate <env> / PATH 中有 snpEff），
#     会额外做 snpEff -version 冒烟；否则跳过真实执行。
# 说明：SnpEff eff/build 需真实数据库（bin 索引）才能产出注释，合成数据无法覆盖真实计算，
#      因此全部子命令采用「python 构造 argv 验证命令构建不崩溃」（monkeypatch _resolve_binary）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位 VCF / FASTA / GTF / config）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/variants.vcf"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "snpeff", d.get("title")
assert "extra_args" in d["properties"], d["properties"].keys()
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证 #1：eff（文档 6.3 注释用法）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnpeffSkill, build_parser
skill = SnpeffSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/snpEff"
cmd = skill.build_command(
    "eff", genome="malassezia_sympodialis", input="$WORK/variants.vcf",
    config="$WORK/snpEff.config", csv_stats="$WORK/variants.SnpEff.csv",
    html_stats="$WORK/variants.SnpEff.html", updown=500, output="$WORK/variant.SnpEff.vcf",
    threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/snpEff eff"), s
assert "-csvStats $WORK/variants.SnpEff.csv" in s, s
assert "-s $WORK/variants.SnpEff.html" in s, s
assert "-c $WORK/snpEff.config" in s, s
assert "-ud 500" in s, s
assert "-v" in s, s
assert s.rstrip().endswith("malassezia_sympodialis $WORK/variants.vcf"), s
print("  OK:", s)
# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(
    ["eff", "GRCh38.105", "$WORK/variants.vcf", "-o", "$WORK/out.vcf",
     "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "eff" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.output == "$WORK/out.vcf" and ns.genome == "GRCh38.105", ns
print("  OK: parser eff")
PY

echo "==> [4/5] argv 构造验证 #2：build / download / databases"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnpeffSkill
skill = SnpeffSkill()
skill._resolve_binary = lambda *a, **k: "snpEff"
b = " ".join(skill.build_command(
    "build", genome="malassezia_sympodialis", config="$WORK/snpEff.config",
    gtf22=True, no_check_cds=True, threads=1))
assert b == "snpEff build -c $WORK/snpEff.config -gtf22 -noCheckCds -v malassezia_sympodialis", b
print("  OK:", b)
d = " ".join(skill.build_command("download", genome="GRCh38.105", threads=1))
assert d == "snpEff download -v GRCh38.105", d
print("  OK:", d)
db = " ".join(skill.build_command("databases", threads=1))
assert db == "snpEff databases -v", db
print("  OK:", db)
PY

echo "==> [5/5] snpEff 冒烟（若已安装）"
if command -v snpEff >/dev/null 2>&1; then
    snpEff -version 2>&1 | head -n 1 || true
else
    echo "  snpEff 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
