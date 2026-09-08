#!/usr/bin/env bash
# longreadsum native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - longreadsum 二进制【可选】：若已安装（conda wglab / native/Dockerfile / install.sh），
#     会额外做 fa 子命令真跑冒烟（合成 FASTA -> HTML 产物断言）；否则退化为
#     「argv 构造验证命令构建不崩溃」（longreadsum 需真实长读数据，合成数据仅覆盖确定性路径）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^bam" "$WORK/commands.txt"
grep -q "^fa" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [2/6] 生成合成测试数据（FASTA / FASTQ / BAM / sequencing_summary）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.fa"
test -s "$WORK/reads.fastq"
test -s "$WORK/reads.bam"
test -s "$WORK/reads.summary"

echo "==> [3/6] argv 构造验证 #1：bam（WGS 默认 + TIN 可选参数 + 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LongreadsumSkill, build_parser
skill = LongreadsumSkill()
skill._resolve_binary = lambda: "/usr/local/bin/longreadsum"
cmd = skill.build_command("bam", input="$WORK/reads.bam", output="$WORK/out",
                          threads=8, prefix="QC_", sample="s1")
s = " ".join(cmd)
assert "/usr/local/bin/longreadsum bam" in s, s
assert "-i $WORK/reads.bam" in s, s
assert "-o $WORK/out" in s, s
assert "-t 8" in s, s
assert "-Q QC_" in s and "-s s1" in s, s
print("  OK:", s)
# bam + TIN（--genebed/--sample-size/--min-coverage）与 --mod/--modprob/--ref
cmd2 = skill.build_command("bam", input="$WORK/reads.bam", output="$WORK/tin",
                           genebed="$WORK/genes.bed", sample_size=50, min_coverage=5)
s2 = " ".join(cmd2)
assert "--genebed $WORK/genes.bed" in s2 and "--sample-size 50" in s2 and "--min-coverage 5" in s2, s2
print("  OK:", s2)
cmd3 = skill.build_command("bam", input="$WORK/reads.bam", output="$WORK/mod",
                           mod=True, modprob=0.8, ref="$WORK/ref.fa")
s3 = " ".join(cmd3)
assert "--mod" in s3 and "--modprob 0.8" in s3 and "--ref $WORK/ref.fa" in s3, s3
print("  OK:", s3)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(["bam", "-i", "$WORK/reads.bam", "-o", "$WORK/out",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "bam" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser bam")
PY

echo "==> [4/6] argv 构造验证 #2：rrms / pod5 / f5s / f5 / seqtxt / fq / fa"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LongreadsumSkill, build_parser
skill = LongreadsumSkill()
skill._resolve_binary = lambda: "longreadsum"
cases = {
    "rrms": dict(input="$WORK/reads.bam", csv="$WORK/d.csv", output="$WORK/rrms"),
    "pod5": dict(input="$WORK/r.pod5", basecalls="$WORK/reads.bam", read_count=5, output="$WORK/p"),
    "f5s":  dict(pattern='$WORK/*.fast5', read_ids="r1,r2", output="$WORK/f5s"),
    "f5":   dict(input="$WORK/r.fast5", output="$WORK/f5"),
    "seqtxt": dict(input="$WORK/reads.summary", output="$WORK/st"),
    "fq":   dict(input="$WORK/reads.fastq", udqual=33, output="$WORK/fq"),
    "fa":   dict(input="$WORK/reads.fa", output="$WORK/fa"),
}
for sub, kw in cases.items():
    cmd = skill.build_command(sub, threads=4, **kw)
    s = " ".join(cmd)
    assert cmd[0] == "longreadsum" and cmd[1] == sub, s
    assert "-t 4" in s, s
    print("  OK:", s)
# rrms 缺 -c csv 时仍可构建（CSV 由调用方提供，构建不强制）；缺全部输入则报错
try:
    skill.build_command("fa", output="$WORK/x")
    raise SystemExit("fa 缺输入应报错")
except ValueError as e:
    assert "需要输入" in str(e), e
    print("  OK: 缺输入报错 ->", e)
# parser 冒烟：fq 的 -u/--udqual
ns = build_parser().parse_args(["fq", "-i", "$WORK/reads.fastq", "-o", "$WORK/fq", "-u", "33"])
assert ns.udqual == 33, ns
print("  OK: parser fq")
PY

echo "==> [5/6] --dry-run 命令构建（main 入口，不执行）"
python "$NATIVE/main.py" fa -i "$WORK/reads.fa" -o "$WORK/dry" --dry-run | grep -q "^CMD:"

echo "==> [6/6] longreadsum 冒烟（若已安装：fa 子命令真跑合成 FASTA -> HTML 产物）"
if command -v longreadsum >/dev/null 2>&1; then
    longreadsum --help | head -n 3
    longreadsum fa -i "$WORK/reads.fa" -o "$WORK/real_out"
    find "$WORK/real_out" -name "*.html" | grep -q .
    echo "  longreadsum fa 真跑通过（HTML 报告已生成）"
else
    echo "  longreadsum 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
