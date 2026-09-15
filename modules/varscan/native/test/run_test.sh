#!/usr/bin/env bash
# varscan native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - varscan 二进制【可选】：若已安装（conda activate <env> / PATH 中有 varscan），
#     会额外做 varscan --version 冒烟；否则跳过真实执行。
# 说明：VarScan 需要真实 mpileup 才能产出变异，合成数据无法覆盖真实检测计算，
#      因此全部子命令采用「python 构造 argv 验证命令构建不崩溃」（monkeypatch _resolve_binary）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位 mpileup / VCF / BAM）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/V1.mpileup" && test -f "$WORK/paired.mpileup"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "varscan", d.get("title")
for k in ("input", "tumor", "vcf_file", "min_coverage", "extra_args"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/5] argv 构造验证 #1：mpileup2snp / mpileup2indel / mpileup2cns（文档 8.2）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import VarscanSkill, build_parser
skill = VarscanSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/varscan"
cmd = skill.build_command(
    "mpileup2snp", input="$WORK/V1.mpileup", min_coverage=8, min_reads2=2,
    min_avg_qual=15, min_var_freq=0.1, p_value=0.05, output_vcf=1, threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/varscan mpileup2snp $WORK/V1.mpileup"), s
assert "--min-coverage 8" in s and "--min-reads2 2" in s, s
assert "--min-avg-qual 15" in s and "--min-var-freq 0.1" in s, s
assert "--p-value 0.05" in s and "--output-vcf 1" in s, s
print("  OK:", s)
for sub in ("mpileup2indel", "mpileup2cns"):
    c = " ".join(skill.build_command(sub, input="$WORK/V1.mpileup", min_coverage=5,
                                     min_reads2=2, min_avg_qual=15, p_value=0.05, output_vcf=1))
    assert c.startswith("/opt/env/bin/varscan %s $WORK/V1.mpileup" % sub), c
    assert "--output-vcf 1" in c, c
    print("  OK:", c)
ns = build_parser().parse_args(["mpileup2snp", "$WORK/V1.mpileup", "--min-coverage", "8",
                                "-o", "$WORK/V1.snp.vcf", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "mpileup2snp" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.min_coverage == 8 and ns.output == "$WORK/V1.snp.vcf", ns
print("  OK: parser mpileup2snp")
PY

echo "==> [4/5] argv 构造验证 #2：somatic / copynumber / processSomatic / fpfilter"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import VarscanSkill, build_parser
skill = VarscanSkill()
skill._resolve_binary = lambda *a, **k: "varscan"

# somatic（文档：单 paired mpileup + 前缀，flags 在中间）
s = " ".join(skill.build_command(
    "somatic", input="$WORK/paired.mpileup", output_basename="$WORK/somatic_output",
    min_coverage=8, min_reads2=2, min_var_freq=0.05, somatic_p_value=0.05, output_vcf=1))
assert s.startswith("varscan somatic $WORK/paired.mpileup"), s
assert "--somatic-p-value 0.05" in s and "--output-vcf 1" in s, s
assert s.rstrip().endswith("$WORK/somatic_output"), s
print("  OK:", s)

# somatic（normal + tumor 双文件）
s2 = " ".join(skill.build_command("somatic", input="$WORK/V1.mpileup",
                                  tumor="$WORK/paired.mpileup", output_vcf=1))
assert s2 == "varscan somatic $WORK/V1.mpileup $WORK/paired.mpileup --output-vcf 1", s2
print("  OK:", s2)

# copynumber
c = " ".join(skill.build_command("copynumber", input="$WORK/paired.mpileup",
                                 output_basename="$WORK/cnv", min_coverage=8, output_vcf=1))
assert c.startswith("varscan copynumber $WORK/paired.mpileup"), c
assert c.rstrip().endswith("$WORK/cnv"), c
print("  OK:", c)

# processSomatic
p = " ".join(skill.build_command("processSomatic", input="$WORK/somatic_output",
                                 min_tumor_freq=0.1, max_normal_freq=0.05, p_value=0.05))
assert p.startswith("varscan processSomatic $WORK/somatic_output"), p
assert "--min-tumor-freq 0.1" in p and "--max-normal-freq 0.05" in p, p
print("  OK:", p)

# fpfilter
f = " ".join(skill.build_command("fpfilter", vcf_file="$WORK/variants.vcf",
                                 bam_file="$WORK/tumor.bam", output_file="$WORK/filtered.vcf",
                                 min_depth=10, min_var_count=3))
assert f.startswith("varscan fpfilter --vcf-file $WORK/variants.vcf --bam-file $WORK/tumor.bam"), f
assert "--output-file $WORK/filtered.vcf" in f and "--min-depth 10" in f, f
print("  OK:", f)

# parser：somatic 位置参数（input [output_basename]）
ns = build_parser().parse_args(["somatic", "$WORK/paired.mpileup", "$WORK/somatic_output",
                                "--output-vcf", "1", "--threads", "1"])
assert ns.input == "$WORK/paired.mpileup" and ns.output_basename == "$WORK/somatic_output", ns
print("  OK: parser somatic")
PY

echo "==> [5/5] varscan 冒烟（若已安装）"
if command -v varscan >/dev/null 2>&1; then
    varscan --version 2>&1 | head -n 1 || true
else
    echo "  varscan 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
