#!/usr/bin/env bash
# pilon native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - java + pilon jar / pilon 封装【可选】：若已安装（conda 环境 / brew pilon / PILON_JAR），
#     会额外做 `pilon --version`（或 java -jar … --version）冒烟；否则跳过真实执行。
# 说明：pilon correct 需要真实比对 BAM 才能产出修正序列，合成数据无法覆盖真实计算，
#      因此对 correct 采用「python 层 argv 构造断言」（monkeypatch _resolve_binary / _resolve_jar，
#      不依赖工具已安装）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（参考组装 + 占位 BAM/tracks）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fasta"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^correct" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：correct（--fix all --changes --output，教学文档形态）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PilonSkill

skill = PilonSkill()
skill._resolve_binary = lambda: "/usr/bin/java"
skill._resolve_jar = lambda: "/opt/pilon/pilon-1.23.jar"

cmd = skill.build_command(
    "correct", genome="$WORK/genome.fasta", frags="$WORK/frags.sorted.bam",
    fix="all", changes=True, output="pilon01", threads=8,
)
assert cmd[0] == "/usr/bin/java", cmd
assert cmd[1] == "-jar", cmd
assert cmd[2] == "/opt/pilon/pilon-1.23.jar", cmd
s = " ".join(cmd)
assert "--genome $WORK/genome.fasta" in s, s
assert "--frags $WORK/frags.sorted.bam" in s, s
assert "--fix all" in s and "--changes" in s, s
assert "--output pilon01" in s, s
assert "--threads 8" in s, s
print("  OK:", s)

# variant 模式（--variant --vcf；未给 changes 的语义由 parser 默认 True，此处显式关掉）
cmd2 = skill.build_command(
    "correct", genome="$WORK/genome.fasta", frags="$WORK/frags.sorted.bam",
    variant=True, vcf=True, changes=False, outdir="$WORK", threads=4,
)
s2 = " ".join(cmd2)
assert "--variant" in s2 and "--vcf" in s2, s2
assert "--changes" not in s2, s2
assert "--outdir $WORK" in s2 and "--threads 4" in s2, s2
print("  OK:", s2)

# 缺省线程（不显式 --threads）→ 取 optimization.per_subcommand_threads.correct=4
cmd3 = skill.build_command("correct", genome="$WORK/genome.fasta",
                           frags="$WORK/frags.sorted.bam", fix="all", changes=True)
assert "--threads 4" in " ".join(cmd3), cmd3
print("  OK:", " ".join(cmd3))
PY

echo "==> [4/6] argv 构造验证 #2：缺 genome / 未知子命令报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PilonSkill
skill = PilonSkill()
skill._resolve_binary = lambda: "/usr/bin/java"
skill._resolve_jar = lambda: "/opt/pilon/pilon-1.23.jar"
try:
    skill.build_command("correct", frags="a.bam")
    raise SystemExit("缺 genome 应报错")
except ValueError as e:
    assert "genome" in str(e), e
    print("  OK: 缺 genome 报错 ->", e)
try:
    skill.build_command("nope", genome="g.fa")
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    assert "未知子命令" in str(e), e
    print("  OK: 未知子命令报错 ->", e)
PY

echo "==> [5/6] parser argv（子命令后 --threads/--tmpdir）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
ns = build_parser().parse_args(
    ["correct", "--genome", "$WORK/genome.fasta", "--frags", "$WORK/frags.sorted.bam",
     "--fix", "all", "--output", "pilon01", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "correct" and ns.genome.endswith("genome.fasta"), ns
assert ns.frags.endswith("frags.sorted.bam") and ns.fix == "all", ns
assert ns.changes is True and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser correct argv")
PY

echo "==> [6/6] pilon 冒烟（若已安装：java + jar 或 pilon 封装）"
if command -v java >/dev/null 2>&1 && [ -n "${PILON_JAR:-}" ] && [ -f "${PILON_JAR}" ]; then
    java -jar "$PILON_JAR" --version 2>&1 | head -n 3
elif command -v pilon >/dev/null 2>&1; then
    pilon --version 2>&1 | head -n 3
else
    echo "  java+pilon jar / pilon 封装未就绪，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
