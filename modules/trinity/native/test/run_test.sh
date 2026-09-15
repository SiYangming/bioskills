#!/usr/bin/env bash
# trinity native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - Trinity 二进制【可选】：本测试以 monkeypatch 方式构造 argv，不依赖已安装的 Trinity，
#     若 PATH 中存在 Trinity 会额外做一次 --version 冒烟。
# 说明：Trinity 组装需要真实 RNA-seq reads（分钟级计算），合成数据无法覆盖真实计算，
#      因此全部子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__（仓库禁止）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（FASTQ / Trinity.fasta / genes.results）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/cmds.txt"
for c in denovo genome_guided stats longest_isoforms align_estimate abundance_matrix; do
    grep -q "^$c " "$WORK/cmds.txt" || { echo "  [FAIL] --list-commands 缺少 $c" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: 自省命令通过"

echo "==> [3/6] argv 构造验证：denovo / genome_guided（monkeypatch 二进制）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TrinitySkill, build_parser
skill = TrinitySkill()
skill._resolve_binary = lambda: "/opt/trinity/Trinity"

cmd = skill.build_command(
    "denovo", left="$WORK/sample_left.fastq", right="$WORK/sample_right.fastq",
    seqtype="fq", max_memory="2G", jaccard_clip=True, normalize_reads=True,
    output="$WORK/trinity_denovo", threads=8,
)
s = " ".join(cmd)
assert "/opt/trinity/Trinity" in s, s
assert "--seqType fq" in s and "--max_memory 2G" in s, s
assert "--left $WORK/sample_left.fastq" in s, s
assert "--right $WORK/sample_right.fastq" in s, s
assert "--CPU 8" in s, s
assert "--jaccard_clip" in s and "--normalize_reads" in s and "--bflyCalculateCPU" in s, s
assert "--output $WORK/trinity_denovo" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "genome_guided", bam="$WORK/merged.sort.bam",
    genome_guided_max_intron=4000, output="$WORK/trinity_genomeGuided", threads=8,
)
s = " ".join(cmd)
assert "--genome_guided_bam $WORK/merged.sort.bam" in s, s
assert "--genome_guided_max_intron 4000" in s, s
assert "--CPU 8" in s and "--output $WORK/trinity_genomeGuided" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["denovo", "--left", "a.fq", "--right", "b.fq",
     "--output", "$WORK/out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "denovo" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser denovo")
PY

echo "==> [4/6] argv 构造验证：stats / longest_isoforms（util 脚本）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TrinitySkill
skill = TrinitySkill()
skill._resolve_util = lambda name: f"/opt/trinity/util/{name}"

cmd = skill.build_command("stats", fasta="$WORK/Trinity.fasta")
assert cmd == ["/opt/trinity/util/TrinityStats.pl", "$WORK/Trinity.fasta"], cmd
print("  OK:", " ".join(cmd))

cmd = skill.build_command("longest_isoforms", fasta="$WORK/Trinity.fasta")
assert cmd == ["/opt/trinity/util/extract_longest_isoforms_from_TrinityFasta.pl", "$WORK/Trinity.fasta"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [5/6] argv 构造验证：align_estimate / abundance_matrix"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TrinitySkill
skill = TrinitySkill()
skill._resolve_util = lambda name: f"/opt/trinity/util/{name}"

cmd = skill.build_command(
    "align_estimate", transcripts="$WORK/Trinity.fasta",
    left="$WORK/sample_left.fastq", right="$WORK/sample_right.fastq",
    est_method="RSEM", aln_method="bowtie2", output_dir="$WORK/exp", threads=4,
)
s = " ".join(cmd)
assert "align_and_estimate_abundance.pl" in s, s
assert "--transcripts $WORK/Trinity.fasta" in s, s
assert "--est_method RSEM" in s and "--aln_method bowtie2" in s, s
assert "--threads 4" in s and "--output_dir $WORK/exp" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "abundance_matrix", results=["$WORK/sample.genes.results"],
    est_method="RSEM", out_prefix="genes", threads=4,
)
s = " ".join(cmd)
assert "abundance_estimates_to_matrix.pl" in s, s
assert "--est_method RSEM" in s and "--out_prefix genes" in s, s
assert s.rstrip().endswith("$WORK/sample.genes.results"), s
print("  OK:", s)
PY

echo "==> [6/6] Trinity 冒烟（若已安装）"
if command -v Trinity >/dev/null 2>&1; then
    Trinity --version | head -n 1
else
    echo "  Trinity 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
