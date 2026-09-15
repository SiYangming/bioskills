#!/usr/bin/env bash
# braker native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - braker.pl/gtf2gff3.pl（可选）：BRAKER2 真实运行需大量依赖与真实 BAM，测试不依赖真实安装；
#     若有 braker.pl 则额外做 --version 冒烟。
# 说明：所有子命令以「python 构造 argv（monkeypatch 二进制路径）验证命令构建」为主。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：run（BRAKER2，RNA-seq + 同源蛋白 ET 模式）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BrakerSkill
skill = BrakerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'braker.pl'}"

c = " ".join(skill.build_command(
    "run", genome="$WORK/genome.softmask.fasta", bam="$WORK/rnaseq.sort.bam",
    prot_seq="$WORK/homolog.fasta", species="malassezia_sympodialis_braker",
    cores=8, etpmode=True, softmasking=True, threads=8))
expect = (" /opt/env/bin/braker.pl --species=malassezia_sympodialis_braker "
          f"--genome=$WORK/genome.softmask.fasta --bam=$WORK/rnaseq.sort.bam "
          f"--prot_seq=$WORK/homolog.fasta --cores 8 --etpmode --softmasking").strip()
assert c == expect, f"\n got: {c}\nwant: {expect}"
print("  OK:", c)
PY

echo "==> [4/6] argv 构造验证 #2：run_rnaseq（BRAKER1，仅 RNA-seq）+ gtf2gff3"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BrakerSkill
skill = BrakerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'braker.pl'}"

c = " ".join(skill.build_command(
    "run_rnaseq", genome="$WORK/genome.softmask.fasta", bam="$WORK/rnaseq.sort.bam",
    prot_seq="$WORK/homolog.fasta", species="my_species", etpmode=True,
    threads=8, softmasking=True))
expect = (" /opt/env/bin/braker.pl --species=my_species "
          f"--genome=$WORK/genome.softmask.fasta --bam=$WORK/rnaseq.sort.bam "
          "--cores 8 --softmasking").strip()
assert c == expect, f"\n got: {c}\nwant: {expect}"
print("  OK:", c)

c = " ".join(skill.build_command("gtf2gff3", gtf="$WORK/braker.gtf"))
assert c == f"/opt/env/bin/gtf2gff3.pl $WORK/braker.gtf", c
print("  OK:", c)
PY

echo "==> [5/6] parser + 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BrakerSkill, build_parser
skill = BrakerSkill()
assert skill._effective_threads("run", 16) == 16
assert skill._effective_threads("run", None) == 8
assert skill._effective_threads("gtf2gff3", None) == 2
print("  OK: threads priority (explicit=16, run=8, gtf2gff3=2)")
ns = build_parser().parse_args(
    ["run", "--genome", "$WORK/genome.softmask.fasta", "--bam", "$WORK/rnaseq.sort.bam",
     "--prot_seq", "$WORK/homolog.fasta", "--etpmode",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.etpmode and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.prot_seq.endswith("homolog.fasta"), ns
print("  OK: parser run")

ns2 = build_parser().parse_args(
    ["gtf2gff3", "$WORK/braker.gtf", "-o", "$WORK/braker.gff3"])
assert ns2.subcommand == "gtf2gff3" and ns2.output.endswith("braker.gff3"), ns2
print("  OK: parser gtf2gff3")
PY

echo "==> [6/6] braker 冒烟（若已安装）"
if command -v braker.pl >/dev/null 2>&1; then
    braker.pl --version 2>&1 | head -n 1 || true
else
    echo "  braker.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
