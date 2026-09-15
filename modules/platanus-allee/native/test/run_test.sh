#!/usr/bin/env bash
# Platanus-allee native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - platanus_allee 二进制【可选】：若已安装（源码编译 / 容器内），会额外做 claudia 版本冒烟
#     （platanus_allee -v 输出 "platanus_allee version: 2.4.0"）；否则仅做 argv 构造断言。
# 说明：assemble/phase/consensus 都需要真实测序数据才能产出结果，合成数据无法覆盖真实计算，
#      因此三个子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch
#      _resolve_binary，不依赖工具已安装）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^assemble' "$WORK/commands.txt"
grep -q '^phase' "$WORK/commands.txt"
grep -q '^consensus' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：assemble"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PlatanusAleeSkill, build_parser
skill = PlatanusAleeSkill()
skill._resolve_binary = lambda: "/opt/env/bin/platanus_allee"
cmd = skill.build_command(
    "assemble", reads=["$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq"],
    output="out", k=32, mem_gb=16, threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/platanus_allee" and cmd[1] == "assemble", s
assert "-t 8" in s, s
assert "-f $WORK/illumina.1.fastq $WORK/illumina.2.fastq" in s, s
assert "-o out" in s and "-k 32" in s and "-m 16" in s, s
assert "-tmp /tmp" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["assemble", "-f", "$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq",
     "--threads", "4", "--tmpdir", "$WORK"]
)
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "$WORK", ns
print("  OK: parser assemble")
PY

echo "==> [4/5] argv 构造验证 #2：phase / consensus"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PlatanusAleeSkill, build_parser
skill = PlatanusAleeSkill()
skill._resolve_binary = lambda: "platanus_allee"

cmd = skill.build_command(
    "phase",
    contigs=["$WORK/out_contig.fa", "$WORK/out_junctionKmer.fa"],
    ip1=["$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq"],
    long_reads=["$WORK/subreads.fasta"], output="out", iterations=2, min_links=3, threads=8,
)
s = " ".join(cmd)
assert cmd[1] == "phase" and "-t 8" in s, s
assert "-c $WORK/out_contig.fa $WORK/out_junctionKmer.fa" in s, s
assert "-IP1 $WORK/illumina.1.fastq $WORK/illumina.2.fastq" in s, s
assert "-p $WORK/subreads.fasta" in s, s
assert "-o out" in s and "-i 2" in s and "-l 3" in s, s
assert "-tmp /tmp" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "consensus",
    contigs=["$WORK/out_primaryBubble.fa", "$WORK/out_nonBubbleHomoCandidate.fa"],
    ip1=["$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq"],
    long_reads=["$WORK/subreads.fasta"], output="out", threads=4,
)
s = " ".join(cmd)
assert cmd[1] == "consensus" and "-t 4" in s, s
assert "-c $WORK/out_primaryBubble.fa $WORK/out_nonBubbleHomoCandidate.fa" in s, s
assert "-IP1 $WORK/illumina.1.fastq $WORK/illumina.2.fastq" in s, s
assert "-p $WORK/subreads.fasta" in s and "-o out" in s, s
print("  OK:", s)

# 线程优先级：用户显式 > per_subcommand_threads
assert skill._effective_threads("assemble", 12) == 12
assert skill._effective_threads("assemble", None) == 8
print("  OK: 线程优先级")
PY

echo "==> [5/5] platanus_allee 版本冒烟（若已安装）"
if command -v platanus_allee >/dev/null 2>&1; then
    platanus_allee -v 2>&1 | tee "$WORK/ver.txt"
    grep -q '2\.4\.0' "$WORK/ver.txt" && echo "  OK: 版本 2.4.0"
else
    echo "  platanus_allee 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
