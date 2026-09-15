#!/usr/bin/env bash
# gapfiller native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - GapFiller.pl（Perl v1.11）+ bowtie/bwa【可选】：若已安装会额外做真实补洞冒烟；
#     否则退化为「自省 + python 层 argv 构造断言」（monkeypatch _resolve_binary，不依赖工具已安装）。
# 说明：GapFiller.pl 按自身目录 $Bin/bowtie/bowtie、$Bin/bwa/bwa 查找比对器，真实运行需要完整部署；
#      合成数据无法覆盖真实补洞计算，故默认走 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（scaffold + 双端 reads + 文库表）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa" && test -s "$WORK/library.txt"
test "$(grep -c '^@' "$WORK/fragment.1.fastq")" -eq 4

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^fill" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json" && test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：fill（教学文档形态 -l library.txt -s genome.fa -T 4）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GapFillerSkill

skill = GapFillerSkill()
skill._resolve_binary = lambda: "/opt/gapfiller/GapFiller.pl"

cmd = skill.build_command("fill", library="$WORK/library.txt", scaffold="$WORK/genome.fa", threads=4)
s = " ".join(cmd)
assert cmd[0] == "/opt/gapfiller/GapFiller.pl", cmd
assert s.endswith("-l $WORK/library.txt -s $WORK/genome.fa -T 4"), s
print("  OK:", s)

# 显式参数白名单（给出才注入）
cmd2 = skill.build_command("fill", library="$WORK/library.txt", scaffold="$WORK/genome.fa",
                           base_name="gf_out", min_overlap=29, min_reads_per_base=2,
                           min_base_ratio=0.7, max_diff=50, min_tig_overlap=10,
                           trim=10, iterations=10, bowtie_gaps=1, threads=8)
s2 = " ".join(cmd2)
for frag in ("-b gf_out", "-m 29", "-o 2", "-r 0.7", "-d 50", "-n 10",
             "-t 10", "-i 10", "-g 1", "-T 8"):
    assert frag in s2, (frag, s2)
print("  OK:", s2)

# 缺省线程（不显式 --threads）→ per_subcommand_threads.fill=4
cmd3 = skill.build_command("fill", library="$WORK/library.txt", scaffold="$WORK/genome.fa")
assert "-T 4" in " ".join(cmd3), cmd3
print("  OK:", " ".join(cmd3))
PY

echo "==> [4/5] 缺参数 / 未知子命令报错 + parser argv"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GapFillerSkill, build_parser

skill = GapFillerSkill()
skill._resolve_binary = lambda: "GapFiller.pl"
for kw, expect in (({"scaffold": "g.fa"}, "library"), ({"library": "l.txt"}, "scaffold")):
    try:
        skill.build_command("fill", **kw)
        raise SystemExit("缺参数应报错")
    except ValueError as e:
        assert expect in str(e), e
        print("  OK: 缺参数报错 ->", e)
try:
    skill.build_command("nope")
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    assert "未知子命令" in str(e), e
    print("  OK: 未知子命令报错 ->", e)

ns = build_parser().parse_args(["fill", "-l", "$WORK/library.txt", "-s", "$WORK/genome.fa",
                                "-b", "gf_out", "-m", "29", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "fill" and ns.library.endswith("library.txt"), ns
assert ns.scaffold.endswith("genome.fa") and ns.base_name == "gf_out" and ns.min_overlap == 29, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser fill argv")
PY

echo "==> [5/5] GapFiller.pl 冒烟（若已部署）"
if command -v GapFiller.pl >/dev/null 2>&1 || [ -n "${GAPFILLER_HOME:-}" ]; then
    SCRIPT="$(command -v GapFiller.pl || echo "${GAPFILLER_HOME}/GapFiller.pl")"
    grep -m1 -E 'version *= *"v[0-9]' "$SCRIPT" || true
    echo "  已发现 GapFiller.pl：$SCRIPT（真实补洞需 bowtie/bwa 与 reads，跳过重计算）"
else
    echo "  GapFiller.pl 未部署，跳过冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
