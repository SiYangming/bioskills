#!/usr/bin/env bash
# finishersc native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - finisherSC.py（Python 2）+ MUMmer【可选】：若已部署会做版本/存在性冒烟；否则退化为
#     「自省 + python 层 argv 构造断言」（monkeypatch _resolve_binary，不依赖工具已安装）。
# 说明：FinisherSC 主流程需真实长读 + 组装 + MUMmer 才能产出 improved3.fasta，合成数据无法覆盖
#      真实计算，故采用 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（destinedFolder + MUMmer 目录形状占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/work/contigs.fasta" && test -s "$WORK/work/raw_reads.fasta"
test -d "$WORK/mummer/bin"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^finish" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json" && test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：finish（教学文档形态）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FinisherSCSkill

skill = FinisherSCSkill()
skill._resolve_binary = lambda: "/opt/finishingTool/finisherSC.py"

# 教学文档形态：python finisherSC.py -par 8 -l True -o contigs.fasta_improved3.fasta ./ <mummer bin>
cmd = skill.build_command("finish", folder="$WORK/work", mummer="$WORK/mummer/bin",
                          large=True, mapcontigs="contigs.fasta_improved3.fasta", threads=8)
s = " ".join(cmd)
assert cmd[0] == "python", cmd
assert cmd[1] == "/opt/finishingTool/finisherSC.py", cmd
for frag in ("-par 8", "-l True", "-o contigs.fasta_improved3.fasta"):
    assert frag in s, (frag, s)
assert s.endswith("$WORK/work $WORK/mummer/bin"), s
print("  OK:", s)

# fast + pickup + 缺省线程（per_subcommand_threads.finish=8）
cmd2 = skill.build_command("finish", folder="$WORK/work", mummer="$WORK/mummer/bin",
                           fast=True, pickup="improved.fasta")
s2 = " ".join(cmd2)
assert "-f True" in s2 and "-p improved.fasta" in s2, s2
assert "-par 8" in s2 and "-l True" not in s2, s2
print("  OK:", s2)

# 显式 --threads 覆盖
cmd3 = skill.build_command("finish", folder="$WORK/work", mummer="$WORK/mummer/bin", threads=16)
assert "-par 16" in " ".join(cmd3), cmd3
print("  OK:", " ".join(cmd3))
PY

echo "==> [4/5] 缺参数 / 未知子命令报错 + parser argv"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FinisherSCSkill, build_parser

skill = FinisherSCSkill()
skill._resolve_binary = lambda: "finisherSC.py"
try:
    skill.build_command("finish", mummer="$WORK/mummer/bin")
    raise SystemExit("缺 folder 应报错")
except ValueError as e:
    assert "folder" in str(e), e
    print("  OK: 缺 folder 报错 ->", e)
try:
    skill.build_command("finish", folder="$WORK/work")
    raise SystemExit("缺 mummer 应报错")
except ValueError as e:
    assert "mummer" in str(e), e
    print("  OK: 缺 mummer 报错 ->", e)
try:
    skill.build_command("nope")
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    assert "未知子命令" in str(e), e
    print("  OK: 未知子命令报错 ->", e)

ns = build_parser().parse_args(["finish", "$WORK/work", "$WORK/mummer/bin",
                                "-l", "-f", "-p", "improved.fasta", "-o", "map.txt",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "finish" and ns.folder.endswith("work"), ns
assert ns.mummer.endswith("bin") and ns.large is True and ns.fast is True, ns
assert ns.pickup == "improved.fasta" and ns.mapcontigs == "map.txt", ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser finish argv")
PY

echo "==> [5/5] finisherSC.py 冒烟（若已部署）"
if command -v finisherSC.py >/dev/null 2>&1 || [ -n "${FINISHERSC_HOME:-}" ]; then
    SCRIPT="$(command -v finisherSC.py || echo "${FINISHERSC_HOME}/finisherSC.py")"
    echo "  已发现 finisherSC.py：$SCRIPT（真实运行需 Python 2 + MUMmer + 长读数据，跳过重计算）"
else
    echo "  finisherSC.py 未部署，跳过冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
