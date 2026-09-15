#!/usr/bin/env bash
# subread native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - subread（featureCounts/subread-align/subjunc）二进制【可选】：若已安装
#     （conda activate <env> / PATH 中有 featureCounts），会额外做 featureCounts -v 冒烟；
#     否则跳过真实执行。
# 说明：featureCounts 需真实比对 BAM、subread-align/subjunc 需真实索引 + reads 才能产出结果，
#      合成数据无法覆盖真实计算，因此统一采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（GTF + BAM/索引/reads 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q '^featureCounts' "$WORK/commands.txt"
grep -q '^subread-align' "$WORK/commands.txt"
grep -q '^subjunc' "$WORK/commands.txt"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：featureCounts（文档 7.5 示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SubreadSkill, build_parser
skill = SubreadSkill()
skill._resolve_binary = lambda name=None: "/opt/env/bin/" + (name or "featureCounts")
cmd = skill.build_command(
    "featureCounts",
    bam=["$WORK/sample1.bam", "$WORK/sample2.bam"],
    gtf="$WORK/genome.gtf", output="$WORK/gene_counts.txt",
    feature_type="exon", group_attribute="gene_id",
    paired=True, stranded=0, min_mapq=10, threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/featureCounts", s
assert "-T 8" in s, s
assert "-p" in s, s
assert "-t exon" in s and "-g gene_id" in s, s
assert "-s 0" in s and "-Q 10" in s, s
assert "-a $WORK/genome.gtf" in s and "-o $WORK/gene_counts.txt" in s, s
assert "$WORK/sample1.bam" in s and "$WORK/sample2.bam" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["featureCounts", "$WORK/sample1.bam", "-a", "$WORK/genome.gtf",
     "-o", "$WORK/out.txt", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "featureCounts" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.bam == ["$WORK/sample1.bam"], ns
print("  OK: parser featureCounts")
PY

echo "==> [4/5] argv 构造验证 #2：subread-align 与 subjunc"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SubreadSkill
skill = SubreadSkill()
skill._resolve_binary = lambda name=None: "/opt/env/bin/" + (name or "featureCounts")

cmd = skill.build_command(
    "subread-align", index="$WORK/subread_index",
    reads="$WORK/reads_1.fq", reads2="$WORK/reads_2.fq",
    output="$WORK/aln.bam", read_type=0, threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/subread-align", s
assert "-i $WORK/subread_index" in s, s
assert "-r $WORK/reads_1.fq" in s and "-R $WORK/reads_2.fq" in s, s
assert "-o $WORK/aln.bam" in s and "-T 8" in s and "-t 0" in s, s
print("  OK:", s)

cmd2 = skill.build_command(
    "subjunc", index="$WORK/subread_index", reads="$WORK/reads_1.fq",
    output="$WORK/junction.bam", threads=4,
)
s2 = " ".join(cmd2)
assert cmd2[0] == "/opt/env/bin/subjunc", s2
assert "-i $WORK/subread_index" in s2 and "-r $WORK/reads_1.fq" in s2, s2
assert "-o $WORK/junction.bam" in s2 and "-T 4" in s2, s2
assert " -t " not in s2, s2  # subjunc 无 -t 数据类型参数
print("  OK:", s2)

# 必填校验
for kw in (dict(output="$WORK/o.txt", bam=["$WORK/sample1.bam"]),
           dict(gtf="$WORK/genome.gtf", bam=["$WORK/sample1.bam"]),
           dict(gtf="$WORK/genome.gtf", output="$WORK/o.txt")):
    try:
        skill.build_command("featureCounts", **kw)
        raise SystemExit("featureCounts 缺必填参数时应报错")
    except ValueError as e:
        print("  OK: featureCounts 必填校验 ->", e)
try:
    skill.build_command("subread-align", reads="$WORK/reads_1.fq", output="$WORK/o.bam")
    raise SystemExit("subread-align 缺 index 时应报错")
except ValueError as e:
    print("  OK: subread-align 必填校验 ->", e)
PY

echo "==> [5/5] featureCounts 冒烟（若已安装）"
if command -v featureCounts >/dev/null 2>&1; then
    featureCounts -v 2>&1 | head -n 1
else
    echo "  featureCounts 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
