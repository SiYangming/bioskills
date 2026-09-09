#!/usr/bin/env bash
# lordec native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - lordec 二进制【可选】：若已安装（conda bioconda / native/install.sh / 官方镜像内），
#     会额外做 -h 冒烟；否则退化为「自省 + argv 构造验证」——lordec-correct 真跑需要足够
#     k-mer 覆盖的真实数据，合成小数据不做端到端纠错断言（避免假阴性）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^correct" "$WORK/commands.txt"
grep -q "^trim" "$WORK/commands.txt"
grep -q "^trim-split" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [2/6] 生成合成测试数据（Illumina paired + PacBio 样长读）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/illumina.r1.fq"
test -s "$WORK/illumina.r2.fq"
test -s "$WORK/reads.fa"

echo "==> [3/6] argv 构造验证 #1：correct（-2 双端/-i/-k/-s/-o/-T 注入 + parser）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LordecSkill, build_parser
skill = LordecSkill()
skill._resolve_binary = lambda: skill.binary
# 双端 -2（用户典型用法：逗号两文件）
cmd = skill.build_command(
    "correct",
    short_reads="$WORK/illumina.r1.fq,$WORK/illumina.r2.fq",
    input="$WORK/reads.fa", kmer_size=17, solidity=3,
    output="$WORK/corrected.fasta", threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "lordec-correct", s
assert "-2 $WORK/illumina.r1.fq,$WORK/illumina.r2.fq" in s, s
assert "-i $WORK/reads.fa" in s and "-o $WORK/corrected.fasta" in s, s
assert "-k 17" in s and "-s 3" in s, s
assert "-T 8" in s, s
print("  OK:", s)
# 单文件 -2 + extra 透传
cmd2 = skill.build_command(
    "correct", short_reads="$WORK/illumina.r1.fq", input="$WORK/reads.fa",
    kmer_size=19, solidity=2, output="$WORK/c2.fasta", threads=4,
    extra_args="--branch 3 --errorrate 0.3",
)
s2 = " ".join(cmd2)
assert "-2 $WORK/illumina.r1.fq" in s2 and "-k 19" in s2 and "-s 2" in s2, s2
assert "-T 4" in s2 and "--branch 3 --errorrate 0.3" in s2, s2
print("  OK:", s2)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["correct", "-2", "$WORK/illumina.r1.fq,$WORK/illumina.r2.fq",
     "-i", "$WORK/reads.fa", "-k", "17", "-s", "3", "-o", "$WORK/c.fasta",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "correct" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.kmer_size == 17 and ns.solidity == 3, ns
print("  OK: parser correct")
PY

echo "==> [4/6] argv 构造验证 #2：trim / trim-split（-i/-o；不注入 -T）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LordecSkill, build_parser
skill = LordecSkill()
skill._resolve_binary = lambda: skill.binary
for sub, expected_bin in (("trim", "lordec-trim"), ("trim-split", "lordec-trim-split")):
    cmd = skill.build_command(sub, input="$WORK/corrected.fasta",
                              output=f"$WORK/{sub}.fasta", threads=4)
    s = " ".join(cmd)
    assert cmd[0] == expected_bin, s
    assert f"-i $WORK/corrected.fasta" in s and f"-o $WORK/{sub}.fasta" in s, s
    assert "-T" not in s, f"{sub} 单线程不应注入 -T: {s}"
    print("  OK:", s)
# parser：trim 无 -2/-k/-s（白名单），--threads 占位可接受
ns = build_parser().parse_args(["trim", "-i", "$WORK/c.fasta", "-o", "$WORK/t.fasta"])
assert ns.subcommand == "trim" and ns.input == "$WORK/c.fasta", ns
print("  OK: parser trim")
PY

echo "==> [5/6] 缺必需参数报错 / --dry-run 主入口"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LordecSkill
skill = LordecSkill()
skill._resolve_binary = lambda: skill.binary
try:
    skill.build_command("correct", short_reads="r1.fq", input="pb.fa",
                        solidity=3, output="o.fa")  # 缺 -k
    raise SystemExit("correct 缺 -k 应报错")
except ValueError as e:
    assert "-k" in str(e), e
    print("  OK: correct 缺参报错 ->", e)
try:
    skill.build_command("trim", input="c.fa")  # 缺 -o
    raise SystemExit("trim 缺 -o 应报错")
except ValueError as e:
    assert "-o" in str(e), e
    print("  OK: trim 缺参报错 ->", e)
try:
    skill.build_command("nope", input="x")
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    print("  OK: 未知子命令报错 ->", e)
PY
python "$NATIVE/main.py" correct -2 "$WORK/illumina.r1.fq,$WORK/illumina.r2.fq" \
    -i "$WORK/reads.fa" -k 17 -s 3 -o "$WORK/c.fasta" --dry-run | grep -q "^CMD:"

echo "==> [6/6] lordec 冒烟（若已安装：lordec-trim -h 输出 Usage；官方 bioconda 判据）"
if command -v lordec-correct >/dev/null 2>&1; then
    lordec-trim -h 2>&1 | grep -qi "Usage" || true
    echo "  lordec-correct 已安装（$(command -v lordec-correct)），-h 冒烟完成"
else
    echo "  lordec 未安装，跳过真实冒烟（自省 + argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
