#!/usr/bin/env bash
# seqkit native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - seqkit 二进制【可选】：若已安装（conda activate seqkit-native / PATH 中有 seqkit），
#     会额外做真实冒烟（stats/grep/sample/translate/fq2fa）；否则全部子命令退化为
#     「python 构造 argv 验证命令构建不崩溃 + parser 断言」。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/9] 生成测试数据（合成 FASTA/FASTQ/ID 列表）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/test.fa" && test -s "$WORK/test.fq" && test -s "$WORK/ids.txt"

echo "==> [2/9] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q stats
python "$NATIVE/main.py" --list-commands | grep -q translate
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "import json; d=json.load(open('$WORK/schema.json')); assert d['title']=='seqkit', d['title']"

echo "==> [3/9] argv 构造验证 #1：stats / fx2tab / fq2fa"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeqkitSkill, build_parser
skill = SeqkitSkill()
skill._resolve_binary = lambda: "/opt/env/bin/seqkit"

cmd = skill.build_command("stats", files=["$WORK/test.fq"], all_stats=True, tabular=True, n50_like="50,90", threads=4)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/seqkit stats"), s
assert "-a" in s and "-T" in s and "-N 50,90" in s and "-j 4" in s, s
assert "$WORK/test.fq" in s, s
print("  OK:", s)

cmd = skill.build_command("fx2tab", files=["$WORK/test.fa"], only_name=True, length_col=True, gc_col=True, only_id=True, header_line=True)
s = " ".join(cmd)
assert "seqkit fx2tab" in s and "-n" in s and "-l" in s and "-g" in s and "-i" in s and "-H" in s, s
print("  OK:", s)

cmd = skill.build_command("fq2fa", files=["$WORK/test.fq"], out_file="$WORK/test.fa.gz")
s = " ".join(cmd)
assert "seqkit fq2fa" in s and "-o $WORK/test.fa.gz" in s, s
print("  OK:", s)
PY

echo "==> [4/9] argv 构造验证 #2：grep（-p 多值 / -f 文件 / -v 反向）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeqkitSkill
skill = SeqkitSkill()
skill._resolve_binary = lambda: "seqkit"
cmd = skill.build_command(
    "grep", files=["$WORK/test.fa"], pattern=["gene001", "seq10"],
    invert_match=True, by_name=True, threads=2,
)
s = " ".join(cmd)
assert "seqkit grep" in s, s
assert "-p gene001 -p seq10" in s, s
assert "-v" in s and "-n" in s and "-j 2" in s, s
print("  OK:", s)
cmd = skill.build_command("grep", files=["$WORK/test.fa"], pattern_file="$WORK/ids.txt", out_file="$WORK/out.fa")
s = " ".join(cmd)
assert "seqkit grep" in s and "-f $WORK/ids.txt" in s and "-o $WORK/out.fa" in s, s
print("  OK:", s)
PY

echo "==> [5/9] argv 构造验证 #3：sample / rmdup / sort"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeqkitSkill
skill = SeqkitSkill()
skill._resolve_binary = lambda: "seqkit"

cmd = skill.build_command("sample", files=["$WORK/test.fa"], number=2, rand_seed=42)
s = " ".join(cmd)
assert "seqkit sample" in s and "-n 2" in s and "-s 42" in s, s
print("  OK:", s)

cmd = skill.build_command("sample", files=["$WORK/test.fq"], proportion=0.1)
s = " ".join(cmd)
assert "seqkit sample" in s and "-p 0.1" in s, s
print("  OK:", s)

cmd = skill.build_command("rmdup", files=["$WORK/test.fa"], by_seq=True, dup_seqs_file="$WORK/dup.fa")
s = " ".join(cmd)
assert "seqkit rmdup" in s and "-s" in s and "-d $WORK/dup.fa" in s, s
print("  OK:", s)

cmd = skill.build_command("sort", files=["$WORK/test.fa"], by_length=True, reverse=True)
s = " ".join(cmd)
assert "seqkit sort" in s and "-l" in s and "-r" in s, s
print("  OK:", s)
PY

echo "==> [6/9] argv 构造验证 #4：split / translate"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeqkitSkill
skill = SeqkitSkill()
skill._resolve_binary = lambda: "seqkit"

cmd = skill.build_command("split", files=["$WORK/test.fa"], by_size=2, out_dir="$WORK/split_out", force_split=True)
s = " ".join(cmd)
assert "seqkit split" in s and "-s 2" in s and "-O $WORK/split_out" in s and "-f" in s, s
print("  OK:", s)

cmd = skill.build_command("split", files=["$WORK/test.fa"], by_part=3)
s = " ".join(cmd)
assert "seqkit split" in s and "-p 3" in s, s
print("  OK:", s)

cmd = skill.build_command("translate", files=["$WORK/test.fa"], frame="6", transl_table=1, trim_translation=True, init_codon_as_m=True)
s = " ".join(cmd)
assert "seqkit translate" in s and "-f 6" in s and "-T 1" in s and "--trim" in s and "-M" in s, s
print("  OK:", s)
PY

echo "==> [7/9] parser 断言：子命令后 --threads/--tmpdir/--dry-run 模式"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
# --dry-run 预扫描剥离：stats 后跟 --threads/--tmpdir/--dry-run 均可解析
p = build_parser()
ns = p.parse_args(["stats", "$WORK/test.fq", "-a", "-T", "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "stats" and ns.threads == 8 and ns.tmpdir == "/tmp" and ns.all_stats and ns.tabular, ns
p2 = build_parser()
ns2 = p2.parse_args(["translate", "$WORK/test.fa", "-f", "6", "--trim"])
assert ns2.subcommand == "translate" and ns2.frame == "6" and ns2.trim_translation, ns2
p3 = build_parser()
ns3 = p3.parse_args(["sample", "$WORK/test.fq", "-p", "0.1", "-s", "11"])
assert ns3.subcommand == "sample" and abs(ns3.proportion - 0.1) < 1e-9 and ns3.rand_seed == 11, ns3
print("  OK: parser stats/translate/sample")
# dry-run：应打印 CMD 且不执行
from main import main as skill_main
rc = skill_main(["stats", "$WORK/test.fq", "-a", "--dry-run"])
assert rc == 0, rc
print("  OK: --dry-run 打印命令并返回 0")
PY

echo "==> [8/9] seqkit 真实冒烟（若已安装）"
if command -v seqkit >/dev/null 2>&1; then
    seqkit version
    seqkit stats -a -T "$WORK/test.fq"
    seqkit grep -f "$WORK/ids.txt" "$WORK/test.fa" | seqkit seq -n
    seqkit sample -p 0.5 -s 11 "$WORK/test.fa"
    seqkit rmdup -s "$WORK/test.fa"
    seqkit sort -l -r "$WORK/test.fa"
    seqkit translate "$WORK/test.fa"
    seqkit fq2fa "$WORK/test.fq"
    echo "  seqkit 真实冒烟通过"
else
    echo "  seqkit 未安装，跳过真实冒烟（argv 构造验证已覆盖 9 子命令）"
fi

echo "==> [9/9] 收尾清理 + 汇总"
echo "ALL TESTS PASSED"
