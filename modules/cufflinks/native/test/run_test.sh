#!/usr/bin/env bash
# cufflinks native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - cufflinks 二进制【可选】：若已安装（conda activate cufflinks / PATH 中有 cufflinks），
#     会额外做 cufflinks --version 冒烟；否则跳过真实执行。
# 说明：⚠️ Cufflinks 为淘汰技术；且组装/定量需真实 BAM，合成数据无法覆盖真实计算，
#      因此对六个子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（占位 BAM / GTF / 列表 / 样本）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：cufflinks / cuffmerge / cuffcompare（线程注入 -p）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CufflinksSkill, build_parser
# cufflinks
skill = CufflinksSkill()
skill._resolve_binary = lambda: "/opt/env/bin/cufflinks"
cmd = skill.build_command("cufflinks", alignment="$WORK/sample.sorted.bam",
                          output="$WORK/sample", reference_gtf="$WORK/sample.gtf",
                          bias_fasta="$WORK/genome.fasta", multi_read_correct=True,
                          labels="sample", threads=8)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/cufflinks $WORK/sample.sorted.bam "), s
assert "-o $WORK/sample" in s and "-p 8" in s, s
assert "-G $WORK/sample.gtf" in s and "-b $WORK/genome.fasta" in s, s
assert "-u" in s and "-L sample" in s, s
print("  OK:", s)
# cuffmerge
skill2 = CufflinksSkill()
skill2._resolve_binary = lambda: "cuffmerge"
cmd2 = skill2.build_command("cuffmerge", gtf_list="$WORK/gtf_list.txt",
                            output="$WORK/cuffmerge", genome_fasta="$WORK/genome.fasta", threads=4)
s2 = " ".join(cmd2)
assert s2.startswith("cuffmerge -o $WORK/cuffmerge -p 4 -s $WORK/genome.fasta "), s2
assert s2.endswith("$WORK/gtf_list.txt"), s2
print("  OK:", s2)
# cuffcompare
skill3 = CufflinksSkill()
skill3._resolve_binary = lambda: "cuffcompare"
cmd3 = skill3.build_command("cuffcompare", gtf="$WORK/sample.gtf", ref_gtf="$WORK/sample.gtf",
                            genome_fasta="$WORK/genome.fasta", output="$WORK/cmp")
s3 = " ".join(cmd3)
assert s3.startswith("cuffcompare -o $WORK/cmp -r $WORK/sample.gtf -s $WORK/genome.fasta "), s3
assert s3.endswith("$WORK/sample.gtf"), s3
print("  OK:", s3)
ns = build_parser().parse_args(
    ["cufflinks", "$WORK/sample.sorted.bam", "-o", "$WORK/o", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "cufflinks" and ns.output == "$WORK/o" and ns.threads == 4, ns
print("  OK: parser cufflinks")
PY

echo "==> [4/4] argv 构造验证：cuffdiff / cuffquant / cuffnorm"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CufflinksSkill
# cuffdiff
skill = CufflinksSkill()
skill._resolve_binary = lambda: "cuffdiff"
cmd = skill.build_command("cuffdiff", samples="$WORK/samples.txt", output="$WORK/cdiff",
                          labels="ctrl,treat", bias_fasta="$WORK/genome.fasta",
                          gui_gtf="$WORK/sample.gtf", no_update_check=True, threads=8)
s = " ".join(cmd)
assert s.startswith("cuffdiff --no-update-check -o $WORK/cdiff -p 8 "), s
assert "-L ctrl,treat" in s and "-b $WORK/genome.fasta" in s and "-u $WORK/sample.gtf" in s, s
assert s.endswith("$WORK/samples.txt"), s
print("  OK:", s)
# cuffquant
skill2 = CufflinksSkill()
skill2._resolve_binary = lambda: "cuffquant"
cmd2 = skill2.build_command("cuffquant", alignment="$WORK/sample.sorted.bam",
                            output="$WORK/cq", gui_gtf="$WORK/sample.gtf", threads=8)
s2 = " ".join(cmd2)
assert s2.startswith("cuffquant -o $WORK/cq -p 8 -u $WORK/sample.gtf "), s2
assert s2.endswith("$WORK/sample.sorted.bam"), s2
print("  OK:", s2)
# cuffnorm
skill3 = CufflinksSkill()
skill3._resolve_binary = lambda: "cuffnorm"
cmd3 = skill3.build_command("cuffnorm", samples="$WORK/samples.txt", output="$WORK/cn",
                            labels="ctrl,treat", threads=4)
s3 = " ".join(cmd3)
assert s3 == "cuffnorm -o $WORK/cn -p 4 -L ctrl,treat $WORK/samples.txt", s3
print("  OK:", s3)
PY

echo "==> 冒烟（若已安装 cufflinks）"
if command -v cufflinks >/dev/null 2>&1; then
    cufflinks --version 2>&1 | head -n 1
else
    echo "  cufflinks 未安装（淘汰技术），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
