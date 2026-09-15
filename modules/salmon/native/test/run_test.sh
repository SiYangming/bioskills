#!/usr/bin/env bash
# salmon native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - salmon 二进制【可选】：本测试以 monkeypatch 方式构造 argv，不依赖已安装的 salmon，
#     若 PATH 中存在 salmon 会额外做一次 --version 冒烟。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__（仓库禁止）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTA / FASTQ / 定量目录占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/cmds.txt"
for c in index quant quantmerge; do
    grep -q "^$c " "$WORK/cmds.txt" || { echo "  [FAIL] --list-commands 缺少 $c" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: 自省命令通过"

echo "==> [3/5] argv 构造验证：index / quant（双端 & 单端）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SalmonSkill, build_parser
skill = SalmonSkill()
skill._resolve_binary = lambda: "/opt/env/bin/salmon"

cmd = skill.build_command(
    "index", transcripts="$WORK/transcripts.fa", index="$WORK/salmon_index",
    kmer=31, threads=4,
)
s = " ".join(cmd)
assert "/opt/env/bin/salmon index" in s, s
assert "-t $WORK/transcripts.fa" in s and "-i $WORK/salmon_index" in s, s
assert "--type quasi" in s and "-k 31" in s and "-p 4" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "quant", index="$WORK/salmon_index", left="$WORK/A1.1.fastq", right="$WORK/A1.2.fastq",
    libtype="A", output="$WORK/quant_out/A1", threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/salmon quant" in s, s
assert "-i $WORK/salmon_index" in s and "-l A" in s, s
assert "-1 $WORK/A1.1.fastq" in s and "-2 $WORK/A1.2.fastq" in s, s
assert "-p 8" in s and "--validateMappings" in s, s
assert "-o $WORK/quant_out/A1" in s, s
print("  OK:", s)

cmd = skill.build_command("quant", index="$WORK/salmon_index", reads="$WORK/A1.1.fastq", threads=4)
s = " ".join(cmd)
assert "-r $WORK/A1.1.fastq" in s and "-p 4" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["quant", "-i", "idx", "-1", "a.fq", "-2", "b.fq", "-o", "out",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "quant" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser quant")
PY

echo "==> [4/5] argv 构造验证：quantmerge"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SalmonSkill
skill = SalmonSkill()
skill._resolve_binary = lambda: "salmon"
cmd = skill.build_command(
    "quantmerge", quants=["$WORK/quantdir_A1", "$WORK/quantdir_A2"],
    output="$WORK/merged/quant",
)
s = " ".join(cmd)
assert "salmon quantmerge" in s, s
assert "--quants $WORK/quantdir_A1 $WORK/quantdir_A2" in s, s
assert "-o $WORK/merged/quant" in s, s
print("  OK:", s)
PY

echo "==> [5/5] salmon 冒烟（若已安装）"
if command -v salmon >/dev/null 2>&1; then
    salmon --version | head -n 1
else
    echo "  salmon 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
