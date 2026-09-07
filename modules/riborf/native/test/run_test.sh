#!/usr/bin/env bash
# riborf native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - perl + RibORF 脚本【可选】：若 PATH/$RIBORF_HOME 中可解析 removeAdapter.pl，
#     会真实运行 remove_adapter（纯 perl 文本处理）并断言产物；其余子命令退化为 argv 构造验证。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q 'remove_adapter'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证：remove_adapter / orfannotate"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RiborfSkill, build_parser

skill = RiborfSkill()
skill._resolve_binary = lambda: "/usr/bin/perl"
skill._resolve_script = lambda sub: f"/opt/riborf/{sub}.pl"

cmd = skill.build_command("remove_adapter", fastq="$WORK/reads.fastq",
                          adapter="CTGTAGGCAC", output="$WORK/trimmed.fastq", threads=2)
s = " ".join(cmd)
assert s == "/usr/bin/perl /opt/riborf/remove_adapter.pl -f $WORK/reads.fastq -a CTGTAGGCAC -o $WORK/trimmed.fastq", s
print("  OK:", s)

cmd2 = skill.build_command("orfannotate", genome="$WORK/genome.fa", genepred="$WORK/transcripts.genePred",
                           output="$WORK/orf_out", start_codons="ATG/CTG", orf_min_length=30)
s2 = " ".join(cmd2)
assert "-g $WORK/genome.fa" in s2 and "-t $WORK/transcripts.genePred" in s2, s2
assert "-o $WORK/orf_out" in s2 and "-s ATG/CTG" in s2 and "-l 30" in s2, s2
print("  OK:", s2)

ns = build_parser().parse_args(
    ["read_dist", "-f", "$WORK/reads.sam", "-g", "$WORK/transcripts.genePred",
     "-o", "$WORK/rd", "-d", "28,29,30", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "read_dist" and ns.read_lengths == "28,29,30" and ns.tmpdir == "/tmp", ns
print("  OK: parser read_dist")
PY

echo "==> [4/6] argv 构造验证：offset_correct / riborf / merge_orf"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RiborfSkill
skill = RiborfSkill()
skill._resolve_binary = lambda: "perl"
skill._resolve_script = lambda sub: f"/opt/riborf/{sub}.pl"

c1 = " ".join(skill.build_command("offset_correct", input_sam="$WORK/s.sam",
                                  offset_params="$WORK/offset.params.txt", output="$WORK/s.corr.sam"))
assert "-r $WORK/s.sam" in c1 and "-p $WORK/offset.params.txt" in c1 and "-o $WORK/s.corr.sam" in c1, c1
print("  OK:", c1)

c2 = " ".join(skill.build_command("riborf", input_sam="$WORK/s.corr.sam",
                                  candidate_orf="$WORK/candidateORF.genepred.txt", output="$WORK/pred",
                                  orf_read_cutoff=5, predict_pvalue_cutoff=0.5))
assert "-f $WORK/s.corr.sam" in c2 and "-c $WORK/candidateORF.genepred.txt" in c2, c2
assert "-o $WORK/pred" in c2 and "-r 5" in c2 and "-p 0.5" in c2, c2
print("  OK:", c2)

c3 = " ".join(skill.build_command("merge_orf", input_sam="$WORK/s.corr.sam",
                                  predicted_orfs="$WORK/a.txt~$WORK/b.txt", output="$WORK/merge"))
assert "-c $WORK/a.txt~$WORK/b.txt" in c3 and "-o $WORK/merge" in c3, c3
print("  OK:", c3)
PY

echo "==> [5/6] 脚本解析：-s/--start-codons 与 -d 缺省用例"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
ns = build_parser().parse_args(["orfannotate", "-g", "g.fa", "-t", "t.gp", "-o", "out",
                                "-s", "ATG/TTG", "-l", "9"])
assert ns.orf_min_length == 9 and ns.start_codons == "ATG/TTG", ns
print("  OK: orfannotate 短选项别名")
PY

echo "==> [6/6] 真实回归（perl + removeAdapter.pl 可用时）"
if command -v perl >/dev/null 2>&1; then
    SCRIPT=""
    if command -v removeAdapter.pl >/dev/null 2>&1; then
        SCRIPT="$(command -v removeAdapter.pl)"
    elif [ -n "${RIBORF_HOME:-}" ] && [ -f "$RIBORF_HOME/removeAdapter.pl" ]; then
        SCRIPT="$RIBORF_HOME/removeAdapter.pl"
    fi
    if [ -n "$SCRIPT" ]; then
        perl "$SCRIPT" -f "$WORK/reads.fastq" -a CTGTAGGCAC -o "$WORK/trimmed.fastq" -l 15 >/dev/null
        test -s "$WORK/trimmed.fastq"
        # 去接头后所有 read 长度应 <= 28nt（原始 28nt 碱基 + 10nt 接头被裁掉）
        if awk 'NR%4==2 && length($0) > 28 {bad++} END {exit bad>0 ? 1 : 0}' "$WORK/trimmed.fastq"; then
            echo "  OK: remove_adapter 真实回归通过（read 长度 <= 28nt）"
        else
            echo "  [FAIL] remove_adapter 输出仍含 >28nt read" >&2; exit 1
        fi
    else
        echo "  RibORF 脚本未安装，跳过真实回归（argv 构造验证已通过）"
    fi
else
    echo "  perl 未安装，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
