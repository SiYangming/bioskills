#!/usr/bin/env bash
# snoscan native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - snoscan 二进制【可选】：若已安装（conda activate snoscan / PATH 中有 snoscan），
#     会额外做 snoscan -h 冒烟；否则跳过真实执行。
# 说明：snoscan 需要在真实 rRNA + 基因组序列上搜索才能产出候选，合成数据无法覆盖真实计算，
#      因此对 search/yeast/human/archaea/sort 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 rRNA / query / hits）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：search（含 -m/-o/-l 与两个位置参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnoscanSkill, build_parser
skill = SnoscanSkill()
skill._resolve_binary = lambda: "/opt/env/bin/snoscan"
cmd = skill.build_command(
    "search", rrna="$WORK/rRNA.fa", query="$WORK/query.fa",
    methylation="$WORK/meth.sites", output="$WORK/hits.txt",
    min_pairing=9, verbose=True, threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/snoscan "), s
assert "-m $WORK/meth.sites" in s, s
assert "-o $WORK/hits.txt" in s, s
assert "-l 9" in s and "-V" in s, s
assert s.endswith("$WORK/rRNA.fa $WORK/query.fa"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["search", "$WORK/rRNA.fa", "$WORK/query.fa", "-m", "$WORK/meth.sites",
     "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "search" and ns.threads == 1 and ns.tmpdir == "/tmp", ns
print("  OK: parser search")
PY

echo "==> [4/5] argv 构造验证 #2：物种预设 yeast / sort"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnoscanSkill
# 物种预设走各自的二进制
skill = SnoscanSkill()
skill._resolve_binary = lambda: "/opt/env/bin/snoscanY"
cmd = skill.build_command("yeast", rrna="$WORK/rRNA.fa", query="$WORK/query.fa",
                          output="$WORK/hits.yeast.txt")
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/snoscanY "), s
assert "-o $WORK/hits.yeast.txt" in s, s
assert s.endswith("$WORK/rRNA.fa $WORK/query.fa"), s
print("  OK:", s)
# sort
skill2 = SnoscanSkill()
skill2._resolve_binary = lambda: "sort-snos"
cmd2 = skill2.build_command("sort", hits="$WORK/hits.txt", sort_by_site=True,
                            min_score=5.0, top=50)
s2 = " ".join(cmd2)
assert s2.startswith("sort-snos "), s2
assert "-P" in s2 and "-S 5.0" in s2 and "-T 50" in s2, s2
assert s2.endswith("$WORK/hits.txt"), s2
print("  OK:", s2)
PY

echo "==> [5/5] snoscan 冒烟（若已安装）"
if command -v snoscan >/dev/null 2>&1; then
    snoscan -h 2>&1 | head -n 3
else
    echo "  snoscan 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
