#!/usr/bin/env bash
# ensembl-vep native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - vep 二进制【可选】：若已安装（conda activate <env> / PATH 中有 vep），
#     会额外做 vep --version 冒烟；否则跳过真实执行。
# 说明：VEP 注释需要本地缓存数据库，合成数据无法覆盖真实注释计算，
#      因此全部子命令采用「python 构造 argv 验证命令构建不崩溃」（monkeypatch _resolve_binary）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位 VCF / 缓存目录）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/variants.vcf" && test -d "$WORK/vep_cache"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "ensembl-vep", d.get("title")
for k in ("input", "output", "species", "assembly", "threads", "extra_args"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证 #1：annotate（文档 10.3 基础注释）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EnsemblVepSkill, build_parser
skill = EnsemblVepSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/vep"
cmd = skill.build_command(
    "annotate", input="$WORK/variants.vcf", output="$WORK/variants.vep.vcf",
    cache=True, cache_version=104, species="homo_sapiens", assembly="GRCh38",
    vcf=True, force_overwrite=True, threads=4,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/vep -i $WORK/variants.vcf -o $WORK/variants.vep.vcf"), s
assert "--cache" in s and "--cache_version 104" in s, s
assert "--species homo_sapiens" in s and "--assembly GRCh38" in s, s
assert "--vcf" in s and "--force_overwrite" in s, s
assert "--fork 4" in s, s
print("  OK:", s)
# 全注释（文档 10.3 示例 2）+ 默认线程（per_subcommand_threads.annotate=8）
cmd2 = skill.build_command("annotate", input="$WORK/variants.vcf", output="$WORK/full.vcf",
                           cache=True, species="homo_sapiens", assembly="GRCh38", vcf=True,
                           sift="b", polyphen="b", ccds=True, uniprot=True, hgvs=True,
                           symbol=True, numbers=True, domains=True, regulatory=True,
                           canonical=True, protein=True, biotype=True, tsl=True, appris=True)
s2 = " ".join(cmd2)
for flag in ("--sift b", "--polyphen b", "--ccds", "--uniprot", "--hgvs", "--symbol",
             "--numbers", "--domains", "--regulatory", "--canonical", "--protein",
             "--biotype", "--tsl", "--appris", "--fork 8"):
    assert flag in s2, (flag, s2)
print("  OK:", s2)
# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["annotate", "-i", "$WORK/variants.vcf", "-o", "$WORK/o.vcf",
                                "--species", "homo_sapiens", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "annotate" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.cache is True, ns
print("  OK: parser annotate")
PY

echo "==> [4/5] argv 构造验证 #2：cache / filter"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EnsemblVepSkill
skill = EnsemblVepSkill()
skill._resolve_binary = lambda *a, **k: "vep_install"
c = " ".join(skill.build_command("cache", auto="cf", species="homo_sapiens",
                                 assembly="GRCh38", dir_cache="$WORK/vep_cache", convert=True))
assert c == "vep_install -a cf -s homo_sapiens -y GRCh38 -c $WORK/vep_cache --CONVERT", c
print("  OK:", c)

skill._resolve_binary = lambda *a, **k: "filter_vep"
f = " ".join(skill.build_command("filter", input="$WORK/variants.vep.vcf",
                                 output="$WORK/filtered.vcf", filter_expr="IMPACT is HIGH",
                                 force_overwrite=True))
assert f.startswith("filter_vep -i $WORK/variants.vep.vcf -o $WORK/filtered.vcf"), f
assert '-f "IMPACT is HIGH"' in f or "-f IMPACT is HIGH" in f, f
assert "--force_overwrite" in f, f
print("  OK:", f)
PY

echo "==> [5/5] vep 冒烟（若已安装）"
if command -v vep >/dev/null 2>&1; then
    vep --version 2>&1 | head -n 1 || true
else
    echo "  vep 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
