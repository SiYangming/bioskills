#!/usr/bin/env bash
# kallisto native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - kallisto 二进制【可选】：本测试以 monkeypatch 方式构造 argv，不依赖已安装的 kallisto，
#     若 PATH 中存在 kallisto 会额外做一次 version 冒烟。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__（仓库禁止）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTA / FASTQ）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/cmds.txt"
for c in index quant inspect; do
    grep -q "^$c " "$WORK/cmds.txt" || { echo "  [FAIL] --list-commands 缺少 $c" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: 自省命令通过"

echo "==> [3/5] argv 构造验证：index"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import KallistoSkill, build_parser
skill = KallistoSkill()
skill._resolve_binary = lambda: "/opt/env/bin/kallisto"

cmd = skill.build_command("index", index="$WORK/kallisto_index", transcripts="$WORK/transcripts.fa", threads=4)
s = " ".join(cmd)
assert "/opt/env/bin/kallisto index" in s, s
assert "-i $WORK/kallisto_index" in s, s
assert "-t 4" in s and s.rstrip().endswith("$WORK/transcripts.fa"), s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["index", "$WORK/transcripts.fa", "-i", "$WORK/idx", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "index" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser index")
PY

echo "==> [4/5] argv 构造验证：quant（双端 & 单端）与 inspect"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import KallistoSkill, build_parser
skill = KallistoSkill()
skill._resolve_binary = lambda: "kallisto"

cmd = skill.build_command(
    "quant", index="$WORK/kallisto_index", output="$WORK/kallisto_out/A1",
    left="$WORK/A1.1.fastq", right="$WORK/A1.2.fastq", bootstrap=100, threads=8,
)
s = " ".join(cmd)
assert "kallisto quant" in s, s
assert "-i $WORK/kallisto_index" in s and "-o $WORK/kallisto_out/A1" in s, s
assert "-b 100" in s and "-t 8" in s, s
assert s.rstrip().endswith("$WORK/A1.1.fastq $WORK/A1.2.fastq"), s
print("  OK:", s)

cmd = skill.build_command(
    "quant", index="$WORK/kallisto_index", output="$WORK/kallisto_out/A1",
    single=True, fragment_length=180, fragment_sd=20, reads="$WORK/A1.1.fastq", threads=4,
)
s = " ".join(cmd)
assert "--single" in s and "-l 180" in s and "-s 20" in s, s
assert s.rstrip().endswith("$WORK/A1.1.fastq"), s
print("  OK:", s)

cmd = skill.build_command("inspect", index="$WORK/kallisto_index")
assert cmd == ["kallisto", "inspect", "$WORK/kallisto_index"], cmd
print("  OK:", " ".join(cmd))

# parser 单端模式：位置参数 left 复用为 reads
ns = build_parser().parse_args(
    ["quant", "-i", "idx", "-o", "out", "--single", "-l", "180", "-s", "20", "reads.fq"]
)
assert ns.single and ns.left == "reads.fq", ns
print("  OK: parser quant --single")
PY

echo "==> [5/5] kallisto 冒烟（若已安装）"
if command -v kallisto >/dev/null 2>&1; then
    kallisto version | head -n 1
else
    echo "  kallisto 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
