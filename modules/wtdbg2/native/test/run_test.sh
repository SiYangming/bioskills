#!/usr/bin/env bash
# wtdbg2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - wtdbg2 / wtpoa-cns 二进制【可选】：若已安装（conda activate / PATH 中有），会额外做冒烟；
#     否则跳过真实执行。
# 说明：wtdbg2 建图/一致性需要真实长读数据，合成数据无法覆盖真实计算，因此对
#      assemble/cns/polish 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位长读 + 布局/草图/比对占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/subreads.fasta"
test -s "$WORK/dbg.ctg.lay.gz"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：assemble（文档 Malassezia 参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Wtdbg2Skill, build_parser
skill = Wtdbg2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"
cmd = skill.build_command(
    "assemble", reads="$WORK/subreads.fasta", output="dbg", threads=8,
    kmer=21, sampling=4, error_rate=0.05, genome_size="8m",
    min_read_len=2000, min_overlap_len=1000,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/wtdbg2"), s
assert "-i $WORK/subreads.fasta" in s and "-o dbg" in s, s
assert "-t 8" in s and "-p 21" in s, s
assert "-S 4" in s and "-s 0.05" in s and "-g 8m" in s, s
assert "-L 2000" in s and "-l 1000" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["assemble", "$WORK/subreads.fasta", "-o", "dbg", "-p", "21", "-g", "8m",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.reads == "$WORK/subreads.fasta" and ns.output == "dbg" and ns.kmer == 21, ns
print("  OK: parser assemble")
PY

echo "==> [4/6] argv 构造验证 #2：cns / polish"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Wtdbg2Skill
skill = Wtdbg2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"

cmd = skill.build_command("cns", layout="$WORK/dbg.ctg.lay.gz",
                          fasta_out="$WORK/dbg.raw.fa", threads=8, min_len=1000)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/wtpoa-cns"), s
assert "-t 8" in s and "-j 1000" in s, s
assert "-i $WORK/dbg.ctg.lay.gz" in s and "-fo $WORK/dbg.raw.fa" in s, s
print("  OK:", s)

# 长读自身打磨（无 -x，input 为 bam）
cmd = skill.build_command("polish", draft="$WORK/dbg.raw.fa",
                          alignment="$WORK/dbg.bam", fasta_out="$WORK/dbg.cns.fa", threads=8)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/wtpoa-cns"), s
assert "-d $WORK/dbg.raw.fa" in s and "-i $WORK/dbg.bam" in s, s
assert "-fo $WORK/dbg.cns.fa" in s and "-x" not in s, s
print("  OK:", s)

# 短读打磨（-x sam-sr，input 为 - 读 stdin）
cmd = skill.build_command("polish", draft="$WORK/dbg.raw.fa", alignment="-",
                          fasta_out="$WORK/dbg.srp.fa", threads=8, preset="sam-sr")
s = " ".join(cmd)
assert "-x sam-sr" in s and "-i -" in s and "-fo $WORK/dbg.srp.fa" in s, s
print("  OK:", s)
PY

echo "==> [5/6] 必填参数缺失应报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Wtdbg2Skill
skill = Wtdbg2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"
for bad in (
    lambda: skill.build_command("assemble", output="dbg"),
    lambda: skill.build_command("assemble", reads="$WORK/subreads.fasta"),
    lambda: skill.build_command("cns", layout="$WORK/dbg.ctg.lay.gz"),
    lambda: skill.build_command("polish", draft="$WORK/dbg.raw.fa"),
):
    try:
        bad()
    except ValueError:
        pass
    else:
        raise AssertionError("缺少必填参数时应抛 ValueError")
print("  OK: 必填参数校验生效")
PY

echo "==> [6/6] wtdbg2 / wtpoa-cns 冒烟（若已安装）"
if command -v wtdbg2 >/dev/null 2>&1; then
    echo "  wtdbg2: $(command -v wtdbg2)"
    wtdbg2 2>&1 | head -n 2 || true
else
    echo "  wtdbg2 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
