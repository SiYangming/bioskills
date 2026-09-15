#!/usr/bin/env bash
# nanopolish native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - nanopolish 二进制【可选】：若已安装（conda 环境 / PATH），会额外做 `nanopolish --version`
#     冒烟；否则跳过真实执行。
# 说明：index/variants 等需真实 fast5 信号与比对 BAM，合成数据无法覆盖真实计算，因此全部子命令
#      采用「python 层 argv 构造断言」（monkeypatch _resolve_binary，不依赖工具已安装）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（参考 + reads + 占位 BAM + 最小 VCF）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/draft.fasta" && test -s "$WORK/nanopore_reads.fastq"
test "$(grep -c '^@' "$WORK/nanopore_reads.fastq")" -eq 4

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
for sc in index variants vcf2fasta methylation eventalign phase-reads; do
    grep -q "^$sc" "$WORK/commands.txt"
done
grep -q '"title"' "$WORK/schema.json" && test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：index / variants / vcf2fasta"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NanopolishSkill

skill = NanopolishSkill()
skill._resolve_binary = lambda: "/opt/env/bin/nanopolish"

# index（教学文档形态：-d fast5/ nanopore_reads.fastq）
c = skill.build_command("index", fast5_dir=["fast5/"], reads=["$WORK/nanopore_reads.fastq"])
s = " ".join(c)
assert c[0] == "/opt/env/bin/nanopolish" and c[1] == "index", c
assert "-d fast5/" in s, s
assert s.endswith("$WORK/nanopore_reads.fastq"), s
print("  OK:", s)

# variants（教学文档形态：--consensus -o -w -r -b -g -t）
c = skill.build_command("variants", consensus=True, output="$WORK/variants.vcf",
                        window="tig00000001:1-100000", reads="$WORK/nanopore_reads.fastq",
                        bam="$WORK/reads.sorted.bam", genome="$WORK/draft.fasta",
                        methylation_aware="dcm,dam", threads=8)
s = " ".join(c)
assert c[1] == "variants", c
for frag in ("--consensus", "-o $WORK/variants.vcf", "-w tig00000001:1-100000",
             "-r $WORK/nanopore_reads.fastq", "-b $WORK/reads.sorted.bam",
             "-g $WORK/draft.fasta", "--methylation-aware=dcm,dam", "-t 8"):
    assert frag in s, (frag, s)
print("  OK:", s)

# vcf2fasta（教学文档形态：-g draft.fasta variants.vcf）
c = skill.build_command("vcf2fasta", genome="$WORK/draft.fasta", vcf="$WORK/variants.vcf")
s = " ".join(c)
assert c[1] == "vcf2fasta" and "-g $WORK/draft.fasta" in s, s
assert s.endswith("$WORK/variants.vcf"), s
assert "-t" not in s, s   # vcf2fasta 不注入线程
print("  OK:", s)
PY

echo "==> [4/6] argv 构造验证 #2：methylation / eventalign / phase-reads"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NanopolishSkill

skill = NanopolishSkill()
skill._resolve_binary = lambda: "nanopolish"

# methylation
c = skill.build_command("methylation", reads="$WORK/nanopore_reads.fastq",
                        bam="$WORK/reads.sorted.bam", genome="$WORK/draft.fasta",
                        window="tig00000001:1-100000", threads=8)
s = " ".join(c)
assert c[1] == "methylation", c
for frag in ("-r $WORK/nanopore_reads.fastq", "-b $WORK/reads.sorted.bam",
             "-g $WORK/draft.fasta", "-w tig00000001:1-100000", "-t 8"):
    assert frag in s, (frag, s)
print("  OK:", s)

# eventalign（--scale-events）
c = skill.build_command("eventalign", reads="$WORK/nanopore_reads.fastq",
                        bam="$WORK/reads.sorted.bam", genome="$WORK/draft.fasta",
                        scale_events=True, threads=4)
s = " ".join(c)
assert c[1] == "eventalign" and "--scale-events" in s, s
assert "-t 4" in s, s
print("  OK:", s)

# phase-reads（位置参数 bam vcf）
c = skill.build_command("phase-reads", bam="$WORK/reads.sorted.bam",
                        vcf="$WORK/variants.vcf", threads=4)
s = " ".join(c)
assert c[1] == "phase-reads", c
assert s.endswith("$WORK/reads.sorted.bam $WORK/variants.vcf -t 4"), s
print("  OK:", s)

# 缺参数报错
for sub, kw in (("index", {}), ("vcf2fasta", {}), ("phase-reads", {"bam": "x.bam"}), ("nope", {})):
    try:
        skill.build_command(sub, **kw)
        raise SystemExit(f"{sub} 应报错")
    except ValueError as e:
        print(f"  OK: {sub} 报错 ->", e)
PY

echo "==> [5/6] parser argv（子命令后 --threads/--tmpdir）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser

ns = build_parser().parse_args(
    ["variants", "--consensus", "-o", "out.vcf", "-w", "tig:1-100",
     "-r", "$WORK/nanopore_reads.fastq", "-b", "$WORK/reads.sorted.bam",
     "-g", "$WORK/draft.fasta", "--methylation-aware", "dcm,dam",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "variants" and ns.consensus is True, ns
assert ns.methylation_aware == "dcm,dam" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser variants argv")

ns2 = build_parser().parse_args(["phase-reads", "a.bam", "a.vcf", "--threads", "4"])
assert ns2.bam == "a.bam" and ns2.vcf == "a.vcf", ns2
ns3 = build_parser().parse_args(["index", "-d", "fast5/", "reads.fastq"])
assert ns3.fast5_dir == ["fast5/"] and ns3.reads == ["reads.fastq"], ns3
print("  OK: parser phase-reads / index argv")
PY

echo "==> [6/6] nanopolish 冒烟（若已安装）"
if command -v nanopolish >/dev/null 2>&1; then
    nanopolish --version 2>&1 | head -n 1
else
    echo "  nanopolish 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
