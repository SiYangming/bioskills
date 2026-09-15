#!/usr/bin/env bash
# kent native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - kent 工具【可选】：若 PATH 中有 faToTwoBit / twoBitToFa，会额外做 FASTA↔2bit 往返断言；
#     否则跳过真实执行，仅做 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免测试导入 main.py 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：faToTwoBit / twoBitToFa / twoBitInfo"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import KentSkill, build_parser
skill = KentSkill()
skill._resolve_tool = lambda name: "/opt/kent/bin/" + name
fy = skill.build_command("faToTwoBit", input="$WORK/genome.fa", output="$WORK/genome.2bit")
assert fy == ["/opt/kent/bin/faToTwoBit", "$WORK/genome.fa", "$WORK/genome.2bit"], fy
bf = skill.build_command("twoBitToFa", input="$WORK/genome.2bit", output="$WORK/back.fa")
assert bf == ["/opt/kent/bin/twoBitToFa", "$WORK/genome.2bit", "$WORK/back.fa"], bf
ti = skill.build_command("twoBitInfo", input="$WORK/genome.2bit", output="$WORK/info.tab")
assert ti == ["/opt/kent/bin/twoBitInfo", "$WORK/genome.2bit", "$WORK/info.tab"], ti
print("  OK:", " ".join(fy))
print("  OK:", " ".join(bf))
print("  OK:", " ".join(ti))
# parser 可解析子命令后 --threads/--tmpdir
ns = build_parser().parse_args(
    ["faToTwoBit", "$WORK/genome.fa", "$WORK/genome.2bit", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "faToTwoBit" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser faToTwoBit")
PY

echo "==> [4/5] argv 构造验证 #2：blat（线程注入） / bedToBigBed"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import KentSkill
skill = KentSkill()
skill._resolve_tool = lambda name: "/opt/kent/bin/" + name
bl = skill.build_command("blat", db="$WORK/genome.2bit", query="$WORK/query.fa",
                         output="$WORK/out.psl", threads=8)
s = " ".join(bl)
assert bl[0] == "/opt/kent/bin/blat", s
assert "$WORK/genome.2bit $WORK/query.fa $WORK/out.psl" in s, s
assert "-threads=8" in s, s
# 线程优先级：显式 > 子命令建议(blat=8) > 全局默认(4)
assert skill._effective_threads("blat", None) == 8, skill._effective_threads("blat", None)
assert skill._effective_threads("blat", 2) == 2
assert skill._effective_threads("twoBitInfo", None) == 4
bb = skill.build_command("bedToBigBed", input="$WORK/regions.bed",
                         chrom_sizes="$WORK/chrom.sizes",
                         output="$WORK/regions.bigBed", type="bed6")
s2 = " ".join(bb)
assert bb[0] == "/opt/kent/bin/bedToBigBed", s2
assert "$WORK/regions.bed $WORK/chrom.sizes $WORK/regions.bigBed" in s2, s2
assert "-type=bed6" in s2, s2
print("  OK:", s)
print("  OK:", s2)
PY

echo "==> [5/5] kent 冒烟（若已安装）：FASTA -> 2bit -> FASTA 往返"
if command -v faToTwoBit >/dev/null 2>&1 && command -v twoBitToFa >/dev/null 2>&1; then
    faToTwoBit "$WORK/genome.fa" "$WORK/genome.2bit"
    test -s "$WORK/genome.2bit"
    twoBitToFa "$WORK/genome.2bit" "$WORK/back.fa"
    test -s "$WORK/back.fa"
    # 序列内容应一致（仅比较非头行）
    grep -v '^>' "$WORK/genome.fa" > "$WORK/orig.seq"
    grep -v '^>' "$WORK/back.fa" > "$WORK/back.seq"
    diff -q "$WORK/orig.seq" "$WORK/back.seq" >/dev/null || { echo '  [FAIL] 往返序列不一致' >&2; exit 1; }
    echo "  OK: faToTwoBit/twoBitToFa 往返一致"
else
    echo "  kent 工具未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
