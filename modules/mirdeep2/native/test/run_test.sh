#!/usr/bin/env bash
# mirdeep2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - miRDeep2 脚本【可选】：若已安装（conda activate mirdeep2 / PATH 中有 miRDeep2.pl），
#     会额外做 miRDeep2.pl -h 冒烟；否则跳过真实执行。
# 说明：miRDeep2 需要真实深度测序 reads + 基因组 + miRBase 参考才能产出预测，合成数据无法
#      覆盖真实计算，因此对 mapper/mirdeep/quantifier 采用「python 构造 argv 验证命令构建不崩溃」
#      的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 reads / genome / miRBase 参考）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：mapper（上游教程命令）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Mirdeep2Skill, build_parser
skill = Mirdeep2Skill()
skill._resolve_binary = lambda: "/opt/env/bin/mapper.pl"
cmd = skill.build_command(
    "mapper", reads="$WORK/reads.fa", input_fasta=True, remove_noncanonical=True,
    clip_adapter="TCGTATGCCGTCTTCTGCTTGT", min_length=18, collapse=True,
    genome_index="cel_cluster", collapsed_reads_out="$WORK/reads_collapsed.fa",
    arf_out="$WORK/reads_collapsed_vs_genome.arf", verbose=True, threads=4,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/mapper.pl $WORK/reads.fa "), s
assert "-c" in s and "-j" in s and "-m" in s and "-v" in s, s
assert "-k TCGTATGCCGTCTTCTGCTTGT" in s, s
assert "-l 18" in s, s
assert "-p cel_cluster" in s, s
assert "-s $WORK/reads_collapsed.fa" in s, s
assert "-t $WORK/reads_collapsed_vs_genome.arf" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["mapper", "$WORK/reads.fa", "-c", "-m", "-l", "18",
     "-p", "cel_cluster", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "mapper" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser mapper")
PY

echo "==> [4/5] argv 构造验证 #2：quantifier / mirdeep"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Mirdeep2Skill
# quantifier
skill = Mirdeep2Skill()
skill._resolve_binary = lambda: "quantifier.pl"
cmd = skill.build_command(
    "quantifier", hairpin="$WORK/precursors_ref_this_species.fa",
    mature="$WORK/mature_ref_this_species.fa", reads_quant="$WORK/reads_collapsed.fa",
    species_code="cel", mature_length="16_19",
)
s = " ".join(cmd)
assert "-p $WORK/precursors_ref_this_species.fa" in s, s
assert "-m $WORK/mature_ref_this_species.fa" in s, s
assert "-r $WORK/reads_collapsed.fa" in s, s
assert "-t cel" in s and "-y 16_19" in s, s
print("  OK:", s)
# mirdeep：6 个位置参数顺序
skill2 = Mirdeep2Skill()
skill2._resolve_binary = lambda: "miRDeep2.pl"
cmd2 = skill2.build_command(
    "mirdeep", reads="$WORK/reads_collapsed.fa", genome="$WORK/cel_cluster.fa",
    arf="$WORK/reads_collapsed_vs_genome.arf",
    mature_ref="$WORK/mature_ref_this_species.fa",
    other_mature_ref="$WORK/mature_ref_other_species.fa",
    hairpin_ref="$WORK/precursors_ref_this_species.fa", species="C.elegans",
)
s2 = " ".join(cmd2)
expect = ("miRDeep2.pl $WORK/reads_collapsed.fa $WORK/cel_cluster.fa "
          "$WORK/reads_collapsed_vs_genome.arf $WORK/mature_ref_this_species.fa "
          "$WORK/mature_ref_other_species.fa $WORK/precursors_ref_this_species.fa -t C.elegans")
assert s2 == expect, s2
print("  OK:", s2)
PY

echo "==> [5/5] miRDeep2 冒烟（若已安装）"
if command -v miRDeep2.pl >/dev/null 2>&1; then
    miRDeep2.pl -h 2>&1 | head -n 3 || true
else
    echo "  miRDeep2.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
