#!/usr/bin/env bash
# sspace native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SSPACE STANDARD v3.0 脚本【可选】：若已安装（PATH 中有 SSPACE_Standard_v3.0.pl
#     / sam_bam2tab.pl），会额外做 sam2tab 真实冒烟；否则跳过真实执行。
# 说明：SSPACE 真正 scaffold 需要真实配对 reads 比对，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在仓库内产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你 contigs + 文库文件 + 占位 fastq + sorted SAM）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fasta" && test -s "$WORK/library.txt" && test -s "$WORK/reads.sorted.sam"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^scaffold'
python "$NATIVE/main.py" --list-commands | grep -q '^sam2tab'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（scaffold/sam2tab）+ --schema"

echo "==> [3/6] argv 构造验证：scaffold（SSPACE_Standard_v3.0.pl 主流程 + 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SspaceSkill, build_parser, _BINARIES

assert _BINARIES == {"scaffold": "SSPACE_Standard_v3.0.pl", "sam2tab": "sam_bam2tab.pl"}, _BINARIES

skill = SspaceSkill()
skill._resolve_sub_binary = lambda sub: "/opt/sspace/" + _BINARIES[sub]

cmd = skill.build_command(
    "scaffold", library="$WORK/library.txt", genome="$WORK/genome.fasta",
    base_name="SSPACE_OUT", extend=0, threads=4,
)
s = " ".join(cmd)
assert cmd[0] == "perl", s
assert "/opt/sspace/SSPACE_Standard_v3.0.pl" in s, s
assert "-l $WORK/library.txt" in s, s
assert "-s $WORK/genome.fasta" in s, s
assert "-x 0" in s and "-T 4" in s, s
assert "-b SSPACE_OUT" in s, s
print("  OK:", s)

# 可选 -k 与 -x 1
cmd = skill.build_command(
    "scaffold", library="$WORK/library.txt", genome="$WORK/genome.fasta",
    base_name="OUT", extend=1, min_links=5, threads=8,
)
s = " ".join(cmd)
assert "-x 1" in s and "-k 5" in s and "-T 8" in s, s
print("  OK:", s)

# parser
ns = build_parser().parse_args(
    ["scaffold", "-l", "$WORK/library.txt", "-s", "$WORK/genome.fasta",
     "-b", "OUT", "-x", "0", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "scaffold" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.library == "$WORK/library.txt" and ns.genome == "$WORK/genome.fasta", ns
print("  OK: parser scaffold")
PY

echo "==> [4/6] argv 构造验证：sam2tab（SAM -> TAB 配对信息）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SspaceSkill, build_parser, _BINARIES

skill = SspaceSkill()
skill._resolve_sub_binary = lambda sub: "/opt/sspace/" + _BINARIES[sub]

cmd = skill.build_command(
    "sam2tab", input="$WORK/reads.sorted.sam", output="$WORK/fragment.tab",
    postfix1="/1", postfix2="/2",
)
s = " ".join(cmd)
assert cmd[0] == "perl", s
assert "/opt/sspace/sam_bam2tab.pl" in s, s
assert "$WORK/reads.sorted.sam" in s, s
assert "/1 /2" in s, s
assert "$WORK/fragment.tab" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["sam2tab", "-i", "$WORK/reads.sorted.sam", "-o", "$WORK/fragment.tab",
     "--postfix1", "/1", "--postfix2", "/2"])
assert ns.subcommand == "sam2tab"
assert (ns.input_opt or ns.input) == "$WORK/reads.sorted.sam"
assert ns.output == "$WORK/fragment.tab" and ns.postfix1 == "/1" and ns.postfix2 == "/2", ns
print("  OK: parser sam2tab")
PY

echo "==> [5/6] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SspaceSkill

skill = SspaceSkill()
skill._resolve_sub_binary = lambda sub: "SSPACE_Standard_v3.0.pl"

for kw in (dict(genome="$WORK/genome.fasta"),        # 缺 library
           dict(library="$WORK/library.txt")):       # 缺 genome
    try:
        skill.build_command("scaffold", **kw)
        raise AssertionError("应抛 ValueError: %r" % kw)
    except ValueError:
        pass
for kw in (dict(output="$WORK/f.tab"),               # 缺 input
           dict(input="$WORK/reads.sorted.sam")):    # 缺 output
    try:
        skill.build_command("sam2tab", **kw)
        raise AssertionError("应抛 ValueError: %r" % kw)
    except ValueError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except (ValueError, RuntimeError):
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] SSPACE 冒烟（若已安装）"
if command -v sam_bam2tab.pl >/dev/null 2>&1 && command -v perl >/dev/null 2>&1; then
    perl "$(command -v sam_bam2tab.pl)" "$WORK/reads.sorted.sam" /1 /2 "$WORK/fragment.tab"
    test -s "$WORK/fragment.tab" && echo "  OK: sam2tab 真实冒烟通过"
else
    echo "  SSPACE 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
