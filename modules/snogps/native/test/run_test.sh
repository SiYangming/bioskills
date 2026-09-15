#!/usr/bin/env bash
# snogps native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - snoGPS 二进制【可选】：若已安装（install.sh / 自建容器），会额外做 snoGPS -h 冒烟；
#     否则跳过真实执行。
# 说明：snoGPS 需要在真实基因组 + descriptor/target 上搜索才能产出候选，合成数据无法覆盖
#      真实计算，因此对 search/sort 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 sequence / descriptor / target / hits）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：search（-T/-t/-S/-F/-q 与两个位置参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnogpsSkill, build_parser
skill = SnogpsSkill()
skill._resolve_binary = lambda: "/opt/env/bin/snoGPS"
cmd = skill.build_command(
    "search", sequence="$WORK/sequence.fa", descriptor="$WORK/descriptor.desc",
    target="$WORK/target.targ", target_count=135, score_cutoff=5.0,
    fasta_out="$WORK/hits.fa", quiet=True, threads=1,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/snoGPS "), s
assert "-T $WORK/target.targ" in s, s
assert "-t 135" in s and "-S 5.0" in s, s
assert "-F $WORK/hits.fa" in s and "-q" in s, s
assert s.endswith("$WORK/sequence.fa $WORK/descriptor.desc"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["search", "$WORK/sequence.fa", "$WORK/descriptor.desc",
     "-T", "$WORK/target.targ", "-W", "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "search" and ns.watson_only and ns.threads == 1 and ns.tmpdir == "/tmp", ns
print("  OK: parser search")
PY

echo "==> [4/5] argv 构造验证 #2：sort"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnogpsSkill
skill = SnogpsSkill()
skill._resolve_binary = lambda: "/opt/env/bin/sortHits.pl"
cmd = skill.build_command("sort", hits="$WORK/hits.txt")
s = " ".join(cmd)
assert s == "/opt/env/bin/sortHits.pl $WORK/hits.txt", s
print("  OK:", s)
PY

echo "==> [5/5] snoGPS 冒烟（若已安装）"
if command -v snoGPS >/dev/null 2>&1; then
    snoGPS -h 2>&1 | head -n 3
else
    echo "  snoGPS 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
