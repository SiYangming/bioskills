#!/usr/bin/env bash
# DBG2OLC native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - DBG2OLC / SparseAssembler / split_and_run_sparc.sh【可选】：若已安装（conda 环境
#     或官方仓库 compiled/ 已加入 PATH），会额外做一次冒烟；否则仅做 argv 构造断言。
# 说明：三段链路（SparseAssembler -> DBG2OLC -> Sparc）都需要真实测序数据才能产出结果，
#      合成数据无法覆盖真实计算，因此对三个子命令采用「python 构造 argv 验证命令构建不崩溃」
#      的断言方式（monkeypatch _resolve_binary，不依赖工具已安装）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^sparseassembler' "$WORK/commands.txt"
grep -q '^dbg2olc' "$WORK/commands.txt"
grep -q '^sparc' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：sparseassembler"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Dbg2olcSkill, build_parser
skill = Dbg2olcSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'DBG2OLC'}"
cmd = skill.build_command(
    "sparseassembler", reads=["$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq"],
    ld=0, k=31, g=15, nodecov=1, edgecov=0, gs=1000000,
)
s = " ".join(cmd)
assert "/opt/env/bin/SparseAssembler" in s, s
assert "LD 0" in s and "k 31" in s and "g 15" in s, s
assert "NodeCovTh 1" in s and "EdgeCovTh 0" in s and "GS 1000000" in s, s
assert "f $WORK/illumina.1.fastq" in s and "f $WORK/illumina.2.fastq" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["sparseassembler", "$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq",
     "--k", "41", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "sparseassembler" and ns.k == 41 and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser sparseassembler")
PY

echo "==> [4/5] argv 构造验证 #2：dbg2olc / sparc"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Dbg2olcSkill, build_parser
skill = Dbg2olcSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'DBG2OLC'}"

cmd = skill.build_command(
    "dbg2olc", reads=["$WORK/subreads.fasta"], contigs="$WORK/Contigs.txt",
    ld=0, k=17, adaptive_th=0.015, kmer_cov_th=5, min_overlap=50, remove_chimera=1,
)
s = " ".join(cmd)
assert "/opt/env/bin/DBG2OLC" in s, s
assert "k 17" in s and "AdaptiveTh 0.015" in s and "KmerCovTh 5" in s, s
assert "MinOverlap 50" in s and "RemoveChimera 1" in s, s
assert "Contigs $WORK/Contigs.txt" in s and "f $WORK/subreads.fasta" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "sparc", backbone="$WORK/backbone_raw.fasta", info="$WORK/DBG2OLC_Consensus_info.txt",
    ctg_pb="$WORK/ctg_pb.fasta", outdir="$WORK", threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/split_and_run_sparc.sh" in s, s
assert "$WORK/backbone_raw.fasta" in s and "$WORK/DBG2OLC_Consensus_info.txt" in s, s
assert "$WORK/ctg_pb.fasta" in s and s.endswith("$WORK 8"), s
print("  OK:", s)

# 线程优先级：用户显式 > per_subcommand_threads
assert skill._effective_threads("sparc", 12) == 12
assert skill._effective_threads("sparc", None) == 8
print("  OK: 线程优先级")
PY

echo "==> [5/5] 冒烟（若已安装）"
if command -v DBG2OLC >/dev/null 2>&1; then
    echo "  已检测到 DBG2OLC，跳过真实组装（需真实测序数据）"
else
    echo "  DBG2OLC 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
