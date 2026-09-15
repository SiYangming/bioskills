#!/usr/bin/env bash
# clustalw native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - clustalw 二进制【可选】：未安装时全部退化为「python 构造 argv 验证命令构建」断言
#     （monkeypatch 二进制解析），不实际运行比对（合成数据无法覆盖真实计算）。
# 覆盖：align（含 --quicktree/gap 罚分）/ tree（NJ + bootstrap）/ profile / help / parser
#      / 线程占位 / 缺二进制报错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（小型 FASTA / 比对占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/seqs.fasta"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^align'
python "$NATIVE/main.py" --list-commands | grep -q '^tree'
python "$NATIVE/main.py" --list-commands | grep -q '^profile'
python "$NATIVE/main.py" --list-commands | grep -q '^help'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证：align（多序列比对，含 --quicktree/gap 罚分）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClustalwSkill

skill = ClustalwSkill()
skill._resolve_binary = lambda: "/opt/clustalw/bin/clustalw"

cmd = skill.build_command(
    "align", infile="$WORK/seqs.fasta", outfile="$WORK/aln.fasta",
    output_format="FASTA", seqtype="PROTEIN", quiet=True,
)
s = " ".join(cmd)
assert s.startswith("/opt/clustalw/bin/clustalw "), s
assert "-infile=$WORK/seqs.fasta" in s, s
assert "-outfile=$WORK/aln.fasta" in s, s
assert "-output=FASTA" in s and "-type=PROTEIN" in s, s
assert "-quiet" in s and s.endswith("-align"), s
print("  OK:", s)

cmd = skill.build_command(
    "align", infile="$WORK/seqs.fasta", outfile="$WORK/aln2.fasta",
    output_format="PHYLIP", quicktree=True, matrix="BLOSUM",
    gapopen=10.0, gapext=0.2, outorder="ALIGNED", stats="$WORK/stats.txt",
)
s = " ".join(cmd)
for frag in ("-quicktree", "-matrix=BLOSUM", "-gapopen=10.0", "-gapext=0.2",
             "-outorder=ALIGNED", "-stats=$WORK/stats.txt", "-output=PHYLIP"):
    assert frag in s, (frag, s)
print("  OK:", s)

# 默认（无 output/type）→ 只有 -infile 与 -align
cmd = skill.build_command("align", infile="$WORK/seqs.fasta")
assert cmd == ["/opt/clustalw/bin/clustalw", "-infile=$WORK/seqs.fasta", "-align"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [4/7] argv 构造验证：tree（NJ / bootstrap / outputtree）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClustalwSkill

skill = ClustalwSkill()
skill._resolve_binary = lambda: "clustalw"

cmd = skill.build_command("tree", infile="$WORK/aln.fasta", outfile="$WORK/tree.ph",
                          outputtree="phylip", clustering="NJ")
s = " ".join(cmd)
assert "-infile=$WORK/aln.fasta" in s, s
assert "-tree" in s, s
assert "-outfile=$WORK/tree.ph" in s, s
assert "-outputtree=phylip" in s and "-clustering=NJ" in s, s
print("  OK:", s)

# bootstrap：用 -bootstrap=n 动词替代 -tree
cmd = skill.build_command("tree", infile="$WORK/aln.fasta", outfile="$WORK/boot.ph",
                          bootstrap=1000, newtree="$WORK/newtree.dnd")
s = " ".join(cmd)
assert "-bootstrap=1000" in s, s
assert "-tree" not in s, s
assert "-newtree=$WORK/newtree.dnd" in s, s
print("  OK:", s)

# 非法 outputtree
try:
    skill.build_command("tree", infile="a.fasta", outputtree="bogus")
    raise AssertionError("非法 outputtree 应报错")
except RuntimeError:
    pass
# 非法 clustering
try:
    skill.build_command("tree", infile="a.fasta", clustering="BOGUS")
    raise AssertionError("非法 clustering 应报错")
except RuntimeError:
    pass
print("  OK: 非法 tree 参数报错")
PY

echo "==> [5/7] argv 构造验证：profile（两比对合并）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClustalwSkill

skill = ClustalwSkill()
skill._resolve_binary = lambda: "clustalw"

cmd = skill.build_command("profile", profile1="$WORK/aln.fasta", profile2="$WORK/aln2.fasta",
                          outfile="$WORK/merged.aln", output_format="CLUSTAL",
                          usetree1="$WORK/t1.dnd", usetree2="$WORK/t2.dnd")
s = " ".join(cmd)
assert "-profile1=$WORK/aln.fasta" in s and "-profile2=$WORK/aln2.fasta" in s, s
assert "-outfile=$WORK/merged.aln" in s and "-output=CLUSTAL" in s, s
assert "-usetree1=$WORK/t1.dnd" in s and "-usetree2=$WORK/t2.dnd" in s, s
assert s.endswith("-profile"), s
print("  OK:", s)

assert skill.build_command("help") == ["clustalw", "-help"]
print("  OK: help")
PY

echo "==> [6/7] parser 解析 + 线程占位 + 运行时校验（缺必填 / 未知子命令 / 缺二进制）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ClustalwSkill, build_parser

ns = build_parser().parse_args(
    ["align", "$WORK/seqs.fasta", "--outfile", "$WORK/o.fasta",
     "--output-format", "FASTA", "--type", "PROTEIN", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "align"
assert (ns.infile or ns.input) == "$WORK/seqs.fasta"
assert ns.outfile == "$WORK/o.fasta" and ns.output_format == "FASTA"
assert ns.seqtype == "PROTEIN" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser align（子命令后 --threads/--tmpdir）")

skill = ClustalwSkill()
# 线程优先级：用户显式 > per_subcommand > 全局默认（ClustalW 不注入 argv）
assert skill._effective_threads("align", 8) == 8
assert skill._effective_threads("align", None) >= 1
print("  OK: 线程优先级（占位）")

skill._resolve_binary = lambda: "clustalw"
for sub, kw in (("align", dict()),                 # 缺 infile
                ("tree", dict()),                  # 缺 infile
                ("profile", dict(profile1="a"))):  # 缺 profile2
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("应抛 RuntimeError: %s" % sub)
    except RuntimeError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
# 真实缺二进制（无 monkeypatch）→ 明确报错
clean = ClustalwSkill()
try:
    clean.build_command("align", infile="x.fasta")
    raise AssertionError("缺 clustalw 二进制应抛 RuntimeError")
except RuntimeError as e:
    assert "未找到可执行文件" in str(e), e
print("  OK: 运行时参数校验")
PY

echo "==> [7/7] clustalw 冒烟（若已安装）"
if command -v clustalw >/dev/null 2>&1; then
    clustalw -help 2>&1 | head -n 1 || true
else
    echo "  clustalw 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
