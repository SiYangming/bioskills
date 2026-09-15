#!/usr/bin/env bash
# annovar native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）+ perl（脚本占位用）
#   - ANNOVAR 脚本【可选】：若已设置 ANNOVAR_HOME（或 PATH 中有 table_annovar.pl），
#     会额外做 --help 冒烟；否则跳过真实执行。
# 说明：ANNOVAR 需真实注释库才能产出结果，合成数据无法覆盖真实注释计算，
#      因此全部子命令采用「python 构造 argv 验证命令构建不崩溃」（monkeypatch _resolve_binary）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位 VCF / humandb / 脚本）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/variants.vcf" && test -d "$WORK/humandb"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "annovar", d.get("title")
for k in ("input", "db_dir", "buildver", "protocol", "operation", "extra_args"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证 #1：table_annovar（文档 9.3 完整注释）"
python3 - <<PY
import sys, shutil
sys.path.insert(0, "$NATIVE")
from main import AnnovarSkill, build_parser
PERL = shutil.which("perl") or "perl"
skill = AnnovarSkill()
skill._resolve_binary = lambda *a, **k: "/opt/annovar/table_annovar.pl"
cmd = skill.build_command(
    "table_annovar", input="$WORK/variants.vcf", db_dir="$WORK/humandb/", buildver="hg38",
    out="$WORK/variants.annovar", remove=True,
    protocol="refGene,1000g2015aug_all,avsnp150", operation="g,f,f",
    nastring=".", vcfinput=True, otherinfo=True, threads=4,
)
s = " ".join(cmd)
assert cmd[0] == PERL and cmd[1] == "/opt/annovar/table_annovar.pl", cmd
assert s.startswith(f"{PERL} /opt/annovar/table_annovar.pl $WORK/variants.vcf $WORK/humandb/"), s
assert "-buildver hg38" in s and "-out $WORK/variants.annovar" in s, s
assert "-remove" in s, s
assert "-protocol refGene,1000g2015aug_all,avsnp150" in s, s
assert "-operation g,f,f" in s, s
assert "-nastring ." in s and "-vcfinput" in s and "--otherinfo" in s, s
assert "-thread 4" in s, s
print("  OK:", s)
# 默认线程（per_subcommand_threads.table_annovar=1）不出 -thread
s2 = " ".join(skill.build_command("table_annovar", input="$WORK/variants.vcf",
                                  db_dir="$WORK/humandb/", buildver="hg38"))
assert "-thread" not in s2, s2
print("  OK: default no -thread")
# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["table_annovar", "$WORK/variants.vcf", "$WORK/humandb/",
                                "-buildver", "hg38", "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "table_annovar" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.buildver == "hg38", ns
print("  OK: parser table_annovar")
PY

echo "==> [4/5] argv 构造验证 #2：geneanno / regionanno / filter / downdb"
python3 - <<PY
import sys, shutil
sys.path.insert(0, "$NATIVE")
from main import AnnovarSkill
PERL = shutil.which("perl") or "perl"
skill = AnnovarSkill()
skill._resolve_binary = lambda *a, **k: "annotate_variation.pl"

g = " ".join(skill.build_command("geneanno", input="$WORK/variants.vcf",
                                 db_dir="$WORK/humandb/", buildver="hg38"))
assert g == f"{PERL} annotate_variation.pl -geneanno -buildver hg38 $WORK/variants.vcf $WORK/humandb/", g
print("  OK:", g)

r = " ".join(skill.build_command("regionanno", input="$WORK/variants.vcf",
                                 db_dir="$WORK/humandb/", buildver="hg38", dbtype="cytoBand"))
assert r == f"{PERL} annotate_variation.pl -regionanno -buildver hg38 -dbtype cytoBand $WORK/variants.vcf $WORK/humandb/", r
print("  OK:", r)

f = " ".join(skill.build_command("filter", input="$WORK/variants.vcf", db_dir="$WORK/humandb/",
                                 buildver="hg38", dbtype="1000g2015aug_all", maf=0.01))
assert f == (f"{PERL} annotate_variation.pl -filter -buildver hg38 -dbtype 1000g2015aug_all "
             "-maf 0.01 $WORK/variants.vcf $WORK/humandb/"), f
print("  OK:", f)

d = " ".join(skill.build_command("downdb", dbtype="refGene", db_dir="$WORK/humandb/",
                                 buildver="hg38", webfrom="annovar"))
assert d == f"{PERL} annotate_variation.pl -downdb -buildver hg38 -webfrom annovar refGene $WORK/humandb/", d
print("  OK:", d)
PY

echo "==> [5/5] ANNOVAR 冒烟（若已设置 ANNOVAR_HOME / 脚本在 PATH）"
if [[ -n "${ANNOVAR_HOME:-}" && -f "${ANNOVAR_HOME}/table_annovar.pl" ]]; then
    perl "${ANNOVAR_HOME}/table_annovar.pl" --help 2>&1 | head -n 2 || true
elif command -v table_annovar.pl >/dev/null 2>&1; then
    table_annovar.pl --help 2>&1 | head -n 2 || true
else
    echo "  ANNOVAR 未安装（未设置 ANNOVAR_HOME），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
