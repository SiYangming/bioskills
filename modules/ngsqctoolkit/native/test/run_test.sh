#!/usr/bin/env bash
# ngsqctoolkit native 最小回归测试（argv 构造 + 自省；软件已淘汰 → 不做真实 perl 回归）
#
# 前置：python3 + pyyaml（base.py 依赖）。perl 可选：CLI dry_run 测试不需要 perl
# 可执行，argv 构造直接断言字符串。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（合成 FASTQ + fake-toolkit 骨架）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/r1.fq" && test -f "$WORK/r2.fq" && test -f "$WORK/single.fq"
test -f "$WORK/fake-toolkit/QC/IlluQC_PRLL.pl"
test -f "$WORK/fake-toolkit/Trimming/TrimmingReads.pl"
test -f "$WORK/fake-toolkit/Trimming/AmbiguityFiltering.pl"

echo "==> [2/7] 自省：--list-commands 列出 qc/trim/ambig 且含弃用提示"
python "$NATIVE/main.py" --list-commands | grep -q '^qc'
python "$NATIVE/main.py" --list-commands | grep -q '^trim'
python "$NATIVE/main.py" --list-commands | grep -q '^ambig'
python "$NATIVE/main.py" --list-commands | grep -q 'trimmomatic'

echo "==> [3/7] 自省：--schema 输出合法 JSON"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "ngsqctoolkit" in d["title"], d' "$WORK/schema.json"

echo "==> [4/7] argv 构造：qc（PE 全参数 / SE）"
python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import NgsQCToolkitSkill, DEPRECATED_WARNING

assert "trimmomatic" in DEPRECATED_WARNING and "fastp" in DEPRECATED_WARNING, DEPRECATED_WARNING

def skill():
    s = NgsQCToolkitSkill()
    s._resolve_binary = lambda: "/usr/bin/perl"
    s.tmpdir = "$WORK"
    return s

TK = "$WORK/fake-toolkit"
# PE：-pe R1 R2 接头库 N 变体 A + -l 70 -s 20 -c 4 -o outdir
cmd = skill().build_command("qc", r1="$WORK/r1.fq", r2="$WORK/r2.fq",
                            toolkit_dir=TK, adapter="N", phred="A",
                            qual_cut=20, len_cut=70, threads=4,
                            outdir="$WORK/qc_out")
s = " ".join(cmd)
assert cmd[0] == "/usr/bin/perl" and cmd[1].endswith("QC/IlluQC_PRLL.pl"), s
assert "-pe" in cmd and "$WORK/r1.fq" in s and "$WORK/r2.fq" in s, s
assert "N" in cmd and "A" in cmd, s
assert "-l" in cmd and "70" in cmd and "-s" in cmd and "20" in cmd, s
assert "-c" in cmd and "4" in cmd and "-o" in cmd and "$WORK/qc_out" in s, s
print("  OK PE:", s)

# SE：-se input 接头库 1 变体 5（Sanger/Illumina1.8+ Phred+33）
cmd = skill().build_command("qc", input="$WORK/single.fq", toolkit_dir=TK,
                            adapter="1", phred="5", qual_cut=25, len_cut=80,
                            threads=2, outdir="$WORK/qc_se", gzip=True)
s = " ".join(cmd)
assert "-se" in cmd and "$WORK/single.fq" in s, s
assert "-z" in cmd and "g" in cmd, s
print("  OK SE+gzip:", s)

# 默认值：adapter=N / phred=A / qual 20 / len 70 / cpus 1
cmd = skill().build_command("qc", r1="$WORK/r1.fq", r2="$WORK/r2.fq",
                            toolkit_dir=TK, outdir="$WORK/o")
s = " ".join(cmd)
assert " N A " in s and "-l 70" in s and "-s 20" in s and "-c 1" in s, s
print("  OK 默认值:", s)

# 运行时校验：缺输入 / 缺 outdir / PE 与 SE 混给 / 未知子命令 / 缺 toolkit_dir
for kw in (dict(toolkit_dir=TK, outdir="$WORK/o"),                       # 缺 r1/r2/input
           dict(toolkit_dir=TK, r1="$WORK/r1.fq", r2="$WORK/r2.fq"),     # 缺 outdir
           dict(toolkit_dir=TK, r1="$WORK/r1.fq", r2="$WORK/r2.fq",
                input="$WORK/single.fq", outdir="$WORK/o")):             # PE+SE 混给
    try:
        skill().build_command("qc", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % (kw,))
    except RuntimeError:
        pass
try:
    skill().build_command("stats", input="$WORK/single.fq", toolkit_dir=TK)
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
old = os.environ.pop("NGSQCTOOLKIT_ROOT", None)
try:
    skill().build_command("qc", r1="$WORK/r1.fq", r2="$WORK/r2.fq", outdir="$WORK/o")
    raise AssertionError("缺 toolkit_dir/环境变量应报错")
except RuntimeError:
    pass
finally:
    if old is not None:
        os.environ["NGSQCTOOLKIT_ROOT"] = old
print("  OK: 运行时参数校验")
PY

echo "==> [5/7] argv 构造：trim（-i/-irev + -q/-n）与 ambig（-c/-p/-t 互斥）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NgsQCToolkitSkill, build_parser

def skill():
    s = NgsQCToolkitSkill()
    s._resolve_binary = lambda: "perl"
    s.tmpdir = "$WORK"
    return s

TK = "$WORK/fake-toolkit"
# trim：-i R1 -irev R2 -q 20 -n 70 -o out
cmd = skill().build_command("trim", input="$WORK/r1.fq", r2="$WORK/r2.fq",
                            toolkit_dir=TK, qual_cut=20, len_cut=70,
                            outdir="$WORK/trim_out.fq")
s = " ".join(cmd)
assert cmd[1].endswith("Trimming/TrimmingReads.pl"), s
assert "-i" in cmd and "$WORK/r1.fq" in s and "-irev" in cmd, s
assert "-q 20" in s and "-n 70" in s and "-o" in cmd and "trim_out.fq" in s, s
print("  OK trim:", s)

# trim 固定截短：-l/-r
cmd = skill().build_command("trim", input="$WORK/single.fq", toolkit_dir=TK,
                            left_trim=5, right_trim=10, outdir="$WORK/o.fq")
s = " ".join(cmd)
assert "-l 5" in s and "-r 10" in s, s
print("  OK trim 固定截短:", s)

# ambig 默认 -c 0
cmd = skill().build_command("ambig", input="$WORK/single.fq", toolkit_dir=TK,
                            max_n=0, len_cut=70, outdir="$WORK/o.fq")
s = " ".join(cmd)
assert cmd[1].endswith("AmbiguityFiltering.pl"), s
assert "-c 0" in s and "-n 70" in s, s
print("  OK ambig -c:", s)

# ambig -p 5（百分比模式）
cmd = skill().build_command("ambig", input="$WORK/single.fq", toolkit_dir=TK,
                            percent_n=5, outdir="$WORK/o.fq")
s = " ".join(cmd)
assert "-p 5" in s and "-c" not in s, s
print("  OK ambig -p:", s)

# ambig -t5/-t3（N 端修剪）
cmd = skill().build_command("ambig", input="$WORK/single.fq", toolkit_dir=TK,
                            trim5=True, outdir="$WORK/o.fq")
assert "-t5" in cmd, cmd
print("  OK ambig -t5:", " ".join(cmd))

# argparse：--max-n 与 --percent-n 互斥被拒；缺 --input 在 build_command 层被拒
try:
    build_parser().parse_args(["ambig", "--input", "$WORK/single.fq",
                               "--max-n", "1", "--percent-n", "5"])
    raise AssertionError("ambig --max-n 与 --percent-n 互斥应被 argparse 拒绝")
except SystemExit:
    pass
try:
    skill().build_command("trim", toolkit_dir=TK)
    raise AssertionError("trim 缺 --input 应报错")
except RuntimeError:
    pass
print("  OK: argparse 互斥组 / 必填校验")
PY

echo "==> [6/7] CLI dry_run 端到端（env NGSQCTOOLKIT_ROOT + 弃用提示；不真实执行）"
export NGSQCTOOLKIT_ROOT="$WORK/fake-toolkit"
python "$NATIVE/main.py" qc --r1 "$WORK/r1.fq" --r2 "$WORK/r2.fq" \
    --outdir "$WORK/qc_out" --threads 2 > "$WORK/qc.out" 2> "$WORK/qc.err"
grep -q 'IlluQC_PRLL.pl' "$WORK/qc.out"
grep -q 'dry_run' "$WORK/qc.err"
grep -q 'trimmomatic' "$WORK/qc.err"
python "$NATIVE/main.py" trim --input "$WORK/r1.fq" --qual-cut 20 --len-cut 70 \
    --outdir "$WORK/t.fq" > "$WORK/trim.out" 2>/dev/null
grep -q 'TrimmingReads.pl' "$WORK/trim.out"
python "$NATIVE/main.py" ambig --input "$WORK/single.fq" --max-n 2 \
    > "$WORK/ambig.out" 2>/dev/null
grep -q 'AmbiguityFiltering.pl' "$WORK/ambig.out"
unset NGSQCTOOLKIT_ROOT
echo "  OK: CLI dry_run 三子命令打印命令行 + 弃用提示"

echo "==> [7/7] 缺 toolkit_dir 时 CLI 报错退出码非 0"
python "$NATIVE/main.py" qc --r1 "$WORK/r1.fq" --r2 "$WORK/r2.fq" \
    --outdir "$WORK/o" >/dev/null 2>&1 && { echo "应失败"; exit 1; } || true
echo "  OK: 缺 toolkit_dir 报错"

echo "ALL TESTS PASSED"
