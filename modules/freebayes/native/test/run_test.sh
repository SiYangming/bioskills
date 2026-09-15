#!/usr/bin/env bash
# freebayes native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - freebayes 二进制【可选】：若已安装（conda activate <env> / PATH 中有 freebayes），
#     会额外做 freebayes --version 冒烟；否则跳过真实执行。
# 说明：freebayes 需要真实 BAM 才能产出 VCF，合成数据无法覆盖真实检测计算，
#      因此 call/parallel 采用「python 构造 argv 验证命令构建不崩溃」（monkeypatch _resolve_binary）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位 FASTA/BAM/regions）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/reference.fa" && test -f "$WORK/regions.bed"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "freebayes", d.get("title")
for k in ("reference", "bams", "ploidy", "extra_args"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证 #1：call（文档 7.2 多样本 + 过滤）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FreebayesSkill, build_parser
skill = FreebayesSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/freebayes"
cmd = skill.build_command(
    "call", reference="$WORK/reference.fa", bams=["$WORK/V1.bam", "$WORK/V2.bam"],
    ploidy=2, min_alternate_count=3, min_coverage=5, min_base_quality=20,
    min_mapping_quality=30, genotype_qualities=True, threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/freebayes -f $WORK/reference.fa"), s
assert "--ploidy 2" in s, s
assert "--min-alternate-count 3" in s and "--min-coverage 5" in s, s
assert "--min-base-quality 20" in s and "--min-mapping-quality 30" in s, s
assert "--genotype-qualities" in s, s
assert s.rstrip().endswith("$WORK/V1.bam $WORK/V2.bam"), s
print("  OK:", s)
# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(
    ["call", "$WORK/V1.bam", "-f", "$WORK/reference.fa", "-o", "$WORK/variants.vcf",
     "--min-alternate-count", "3", "--min-coverage", "5", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "call" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.bams == ["$WORK/V1.bam"] and ns.min_alternate_count == 3, ns
print("  OK: parser call")
PY

echo "==> [4/5] argv 构造验证 #2：parallel（freebayes-parallel 区域并行）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FreebayesSkill, build_parser
skill = FreebayesSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/freebayes-parallel"
cmd = skill.build_command(
    "parallel", regions="$WORK/regions.bed", reference="$WORK/reference.fa",
    bams=["$WORK/V1.bam"], threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/freebayes-parallel $WORK/regions.bed 8"), s
assert "-f $WORK/reference.fa" in s, s
assert s.rstrip().endswith("$WORK/V1.bam"), s
print("  OK:", s)
# 线程优先级：未给 --threads 时回落 per_subcommand_threads.parallel=8
cmd2 = skill.build_command("parallel", regions="$WORK/regions.bed",
                           reference="$WORK/reference.fa", bams=["$WORK/V1.bam"])
assert "regions.bed 8" in " ".join(cmd2), cmd2
print("  OK: default threads -> 8")
ns = build_parser().parse_args(["parallel", "$WORK/regions.bed", "$WORK/V1.bam",
                                "-f", "$WORK/reference.fa", "--threads", "16"])
assert ns.regions == "$WORK/regions.bed" and ns.threads == 16, ns
print("  OK: parser parallel")
PY

echo "==> [5/5] freebayes 冒烟（若已安装）"
if command -v freebayes >/dev/null 2>&1; then
    freebayes --version 2>&1 | head -n 1 || true
else
    echo "  freebayes 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
