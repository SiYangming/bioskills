#!/usr/bin/env bash
# diamond native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - diamond 二进制【可选】：本测试以 monkeypatch 方式构造 argv，不依赖已安装的 diamond，
#     若 PATH 中存在 diamond 会额外做一次 version 冒烟。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__（仓库禁止）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（蛋白库 / 查询 FASTA）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/cmds.txt"
for c in makedb blastp blastx; do
    grep -q "^$c " "$WORK/cmds.txt" || { echo "  [FAIL] --list-commands 缺少 $c" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: 自省命令通过"

echo "==> [3/5] argv 构造验证：makedb"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiamondSkill, build_parser
skill = DiamondSkill()
skill._resolve_binary = lambda: "/opt/env/bin/diamond"

cmd = skill.build_command("makedb", db="$WORK/uniprot_sprot", input="$WORK/uniprot_sprot.fasta", threads=8)
s = " ".join(cmd)
assert "/opt/env/bin/diamond makedb" in s, s
assert "--threads 8" in s, s
assert "--db $WORK/uniprot_sprot" in s and "--in $WORK/uniprot_sprot.fasta" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["makedb", "--db", "db", "--in", "in.faa", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "makedb" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser makedb")
PY

echo "==> [4/5] argv 构造验证：blastp / blastx"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiamondSkill, build_parser
skill = DiamondSkill()
skill._resolve_binary = lambda: "diamond"
skill.tmpdir = "/dev/shm"

cmd = skill.build_command(
    "blastp", db="$WORK/uniprot_sprot", query="$WORK/longest_orfs.pep",
    output="$WORK/blast.xml", outfmt=5, sensitive=True, max_target_seqs=20,
    evalue=1e-5, min_id=20, index_chunks=1, threads=8,
)
s = " ".join(cmd)
assert "diamond blastp" in s, s
assert "--db $WORK/uniprot_sprot" in s and "--query $WORK/longest_orfs.pep" in s, s
assert "--out $WORK/blast.xml" in s and "--outfmt 5" in s, s
assert "--sensitive" in s and "--max-target-seqs 20" in s, s
assert "--evalue 1e-05" in s and "--id 20" in s, s
assert "--tmpdir /dev/shm" in s and "--index-chunks 1" in s and "--threads 8" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "blastx", db="$WORK/uniprot_sprot", query="$WORK/transcripts.fa",
    output="$WORK/blastx.tsv", outfmt=6, threads=4,
)
s = " ".join(cmd)
assert "diamond blastx" in s, s
assert "--out $WORK/blastx.tsv" in s and "--outfmt 6" in s and "--threads 4" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["blastp", "--db", "db", "--query", "q.pep", "-o", "out.xml", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "blastp" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser blastp")
PY

echo "==> [5/5] diamond 冒烟（若已安装）"
if command -v diamond >/dev/null 2>&1; then
    diamond version | head -n 1
else
    echo "  diamond 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
