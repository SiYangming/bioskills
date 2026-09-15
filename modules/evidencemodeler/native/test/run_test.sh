#!/usr/bin/env bash
# evidencemodeler native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - EVM/ParaFly【可选】：若已安装（PATH 中或设置 EVM_HOME），会额外做 ParaFly 冒烟；否则跳过。
# 说明：EVM 真实运行需要基因组 + 多来源证据 GFF3，合成数据无法覆盖权重整合计算，
#      因此对 partition/write_commands/parallel/recombine/convert_gff3/weights 采用
#      「python 构造 argv 验证命令构建不崩溃（monkeypatch 脚本解析）」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（最小 FASTA/GFF3/权重/分区占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证（覆盖全部 7 个子命令）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EvidenceModelerSkill, SCRIPTS, build_parser

def mk():
    s = EvidenceModelerSkill()
    s._resolve_script = lambda sub: "/opt/env/bin/" + SCRIPTS[sub][0]
    return s

s = mk()
cmd = s.build_command(
    "partition", genome="$WORK/genome.fasta", gene_predictions="$WORK/gene_predictions.gff3",
    protein_alignments="$WORK/protein_alignments.gff3",
    transcript_alignments="$WORK/transcript_alignments.gff3", repeats="$WORK/repeats.gff3",
    segment_size=500000, overlap_size=10000, partition_listing="$WORK/partitions_list.out",
)
line = " ".join(cmd)
assert "/opt/env/bin/partition_EVM_inputs.pl" in line, line
assert "--genome $WORK/genome.fasta" in line, line
assert "--segmentSize 500000" in line and "--overlapSize 10000" in line, line
assert "--partition_listing $WORK/partitions_list.out" in line, line
print("  OK partition:", line)

cmd = s.build_command(
    "write_commands", partitions="$WORK/partitions_list.out", weights="$WORK/weights.txt",
    genome="$WORK/genome.fasta", output_file_name="evm.out",
)
line = " ".join(cmd)
assert "/opt/env/bin/write_EVM_commands.pl" in line, line
assert "--partitions $WORK/partitions_list.out" in line, line
assert "--weights $WORK/weights.txt" in line and "--output_file_name evm.out" in line, line
print("  OK write_commands:", line)

cmd = s.build_command("parallel", commands_file="$WORK/commands.list", threads=8)
line = " ".join(cmd)
assert "/opt/env/bin/ParaFly" in line, line
assert "-c $WORK/commands.list -CPU 8" in line, line
print("  OK parallel:", line)

cmd = s.build_command("recombine", partitions="$WORK/partitions_list.out", output_file_name="evm.out")
line = " ".join(cmd)
assert "/opt/env/bin/recombine_EVM_partial_outputs.pl" in line, line
assert "--partitions $WORK/partitions_list.out --output_file_name evm.out" in line, line
print("  OK recombine:", line)

cmd = s.build_command("convert_gff3", partitions="$WORK/partitions_list.out",
                      output_file_name="evm.out", genome="$WORK/genome.fasta")
line = " ".join(cmd)
assert "/opt/env/bin/convert_EVM_outputs_to_GFF3.pl" in line, line
assert "--genome $WORK/genome.fasta" in line, line
print("  OK convert_gff3:", line)

cmd = s.build_command("weights", ab_initio_progs="AUGUSTUS", protein_progs="GeneWise",
                      transcript_progs="pasa")
line = " ".join(cmd)
assert "/opt/env/bin/create_weights_file.pl" in line, line
assert "-A AUGUSTUS" in line and "-P GeneWise" in line and "-T pasa" in line, line
print("  OK weights:", line)

cmd = s.build_command("evm", genome="$WORK/genome.fasta",
                      gene_predictions="$WORK/gene_predictions.gff3", weights="$WORK/weights.txt")
line = " ".join(cmd)
assert "/opt/env/bin/evidence_modeler.pl" in line, line
assert "--weights $WORK/weights.txt" in line, line
print("  OK evm:", line)

# 缺参应报 ValueError（partition 无 partition_listing）
try:
    s.build_command("partition", genome="$WORK/genome.fasta")
    raise SystemExit("[FAIL] partition 缺参未报错")
except ValueError:
    print("  OK: 缺参校验触发")

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["parallel", "-c", "$WORK/commands.list", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "parallel" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser parallel")
PY

echo "==> [4/4] EVM/ParaFly 冒烟（若已安装）"
if command -v ParaFly >/dev/null 2>&1; then
    ParaFly -h 2>&1 | head -n 2 || true
else
    echo "  ParaFly 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
