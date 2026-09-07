#!/usr/bin/env bash
# riboss native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - riboss 环境【可选】：若当前解释器可 import riboss.orfs，会真实回归 translate（ATGGTCTGA→MV）；
#     否则退化为 argv 构造验证（orf_finder/transcriptome_assembly 还需 UCSC 工具等，仅 argv 级）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q 'orf_finder'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证：translate / orf_finder"
python3 - <<PY
import sys, os
sys.path.insert(0, "$NATIVE")
from main import RibossSkill, build_parser

skill = RibossSkill()
c1 = skill.build_command("translate", seq="ATGGTCTGA")
s = " ".join(c1)
assert s.endswith("run_riboss.py translate ATGGTCTGA"), s
assert c1[0] == sys.executable, c1
print("  OK:", s)

c2 = skill.build_command("orf_finder", annotation="$WORK/ann.gtf", tx="$WORK/tx.fa",
                         outdir="$WORK/orf_out", start_codons="ATG,GTG")
s2 = " ".join(c2)
assert "--annotation $WORK/ann.gtf" in s2 and "--tx $WORK/tx.fa" in s2, s2
assert "--outdir $WORK/orf_out" in s2 and "--start-codons ATG,GTG" in s2, s2
print("  OK:", s2)

ns = build_parser().parse_args(
    ["orf_finder", "--annotation", "$WORK/ann.gtf", "--tx", "$WORK/tx.fa",
     "--outdir", "$WORK/o", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "orf_finder" and ns.tmpdir == "/tmp", ns
print("  OK: parser orf_finder")
PY

echo "==> [4/6] argv 构造验证：transcriptome_assembly"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RibossSkill
skill = RibossSkill()
c = skill.build_command(
    "transcriptome_assembly", superkingdom="Eukaryota", genome="$WORK/genome.fa",
    long_reads="$WORK/long.bam", short_reads="$WORK/short.bam", strandness="rf",
    annotation="$WORK/ann.gtf", outdir="$WORK/asm", threads=8)
s = " ".join(c)
for token in ("--superkingdom Eukaryota", "--genome $WORK/genome.fa",
              "--long-reads $WORK/long.bam", "--short-reads $WORK/short.bam",
              "--strandness rf", "--annotation $WORK/ann.gtf",
              "--threads 8", "--outdir $WORK/asm"):
    assert token in s, (token, s)
print("  OK:", s)
PY

echo "==> [5/6] run_riboss.py 帮助 / 参数解析"
python "$NATIVE/run_riboss.py" --help | grep -q 'orf_finder'
python3 - <<PY
import subprocess, sys
out = subprocess.run([sys.executable, "$NATIVE/run_riboss.py", "translate", "--help"],
                     capture_output=True, text=True)
assert out.returncode == 0 and "seq" in out.stdout, out
print("  OK: run_riboss.py translate --help")
PY

echo "==> [6/6] 真实回归（riboss 环境可用时）"
if python3 -c 'import riboss.orfs' >/dev/null 2>&1; then
    out="$(python "$NATIVE/main.py" translate ATGGTCTGA)"
    [[ "$out" == "MV" ]] || { echo "  [FAIL] translate 期望 MV，实际: $out" >&2; exit 1; }
    echo "  OK: translate 真实回归通过（ATGGTCTGA -> $out）"
else
    echo "  riboss 未安装，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
