#!/usr/bin/env bash
# htseq native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - htseq-count 二进制【可选】：若已安装（conda activate <env> / PATH 中有 htseq-count），
#     会额外做 htseq-count --version 冒烟；否则跳过真实执行。
# 说明：htseq-count 需真实比对 SAM/BAM 才能计数，合成数据无法覆盖真实解析，因此统一采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小 SAM + GTF/GFF）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q '^count' "$WORK/commands.txt"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：count（文档 7.6 示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import HtseqSkill, build_parser
skill = HtseqSkill()
skill._resolve_binary = lambda: "/opt/env/bin/htseq-count"
cmd = skill.build_command(
    "count", samfile="$WORK/accepted_hits.sam", gfffile="$WORK/genome.gtf",
    format="bam", order="pos", stranded="no", minaqual=10,
    featuretype="exon", idattr="gene_id", mode="union",
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/htseq-count", s
assert "-f bam" in s and "-r pos" in s and "-s no" in s, s
assert "-a 10" in s and "-t exon" in s and "-i gene_id" in s and "-m union" in s, s
# 位置参数顺序：alignment_file 在 gff_file 之前
assert s.endswith("$WORK/accepted_hits.sam $WORK/genome.gtf"), s
# htseq-count 单线程：不注入任何线程 flag
assert "-p " not in s and " -T " not in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["count", "$WORK/accepted_hits.sam", "$WORK/genome.gtf",
     "-f", "bam", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "count" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.samfile == "$WORK/accepted_hits.sam" and ns.gfffile == "$WORK/genome.gtf", ns
print("  OK: parser count")
PY

echo "==> [4/5] argv 构造验证 #2：-o samout / -m 模式 / 必填校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import HtseqSkill
skill = HtseqSkill()
skill._resolve_binary = lambda: "htseq-count"

cmd = skill.build_command(
    "count", samfile="$WORK/accepted_hits.sam", gfffile="$WORK/genome.gff",
    format="sam", order="pos", stranded="reverse", minaqual=0,
    featuretype="exon", idattr="transcript_id", mode="intersection-strict",
    samout="$WORK/annotated.sam",
)
s = " ".join(cmd)
assert "-o $WORK/annotated.sam" in s, s
assert "-s reverse" in s and "-i transcript_id" in s, s
assert "-m intersection-strict" in s, s
print("  OK:", s)

# 必填校验
for kw in (dict(gfffile="$WORK/genome.gtf"), dict(samfile="$WORK/accepted_hits.sam")):
    try:
        skill.build_command("count", **kw)
        raise SystemExit("count 缺必填参数时应报错")
    except ValueError as e:
        print("  OK: count 必填校验 ->", e)
PY

echo "==> [5/5] htseq-count 冒烟（若已安装）"
if command -v htseq-count >/dev/null 2>&1; then
    htseq-count --version 2>&1 | head -n 1
else
    echo "  htseq-count 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
