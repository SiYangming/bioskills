#!/usr/bin/env bash
# pasa（PASApipeline）native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - PASA 二进制【可选】：若已安装（conda activate / PATH 中有 Launch_PASA_pipeline.pl），
#     会额外做该脚本 -h 冒烟；否则跳过真实执行。
# 说明：PASA 需真实数据 + MySQL 才能跑通，合成数据无法覆盖真实计算，因此对
#      align_assemble / build_comprehensive / asmbls_to_training 采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch 脚本解析，
#      不依赖已安装工具）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 禁止生成 __pycache__（保持仓库干净）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（配置/FASTA 迷你占位）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^align_assemble' "$WORK/commands.txt"
grep -q '^build_comprehensive' "$WORK/commands.txt"
grep -q '^asmbls_to_training' "$WORK/commands.txt"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：align_assemble（Launch_PASA_pipeline.pl）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PasaSkill, build_parser
skill = PasaSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name
cmd = skill.build_command(
    "align_assemble", config="$WORK/alignAssembly.config", genome="$WORK/genome.fasta",
    transcripts="$WORK/transcripts.fasta.clean", unclean_transcripts="$WORK/transcripts.fasta",
    tdn="$WORK/tdn.accs", aligners="gmap,blat", stringent_alignment_overlap=30.0,
    max_intron_length=20000, transdecoder=True, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/Launch_PASA_pipeline.pl" in s, s
assert "-c $WORK/alignAssembly.config" in s, s
assert "-R" in s and "-T" in s, s
assert "-g $WORK/genome.fasta" in s and "-t $WORK/transcripts.fasta.clean" in s, s
assert "-u $WORK/transcripts.fasta" in s, s
assert "--TDN $WORK/tdn.accs" in s, s
assert "--ALIGNERS gmap,blat" in s and "--CPU 8" in s, s
assert "--stringent_alignment_overlap 30.0" in s and "--MAX_INTRON_LENGTH 20000" in s, s
assert "--TRANSDECODER" in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["align_assemble", "-c", "$WORK/alignAssembly.config", "-g", "$WORK/genome.fasta",
     "-t", "$WORK/transcripts.fasta.clean", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "align_assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser align_assemble")
PY

echo "==> [4/5] argv 构造验证 #2：build_comprehensive / asmbls_to_training"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PasaSkill
skill = PasaSkill()
skill._resolve_tool = lambda name: "/opt/env/bin/" + name

cmd = skill.build_command(
    "build_comprehensive", config="$WORK/alignAssembly.config",
    transcripts="$WORK/transcripts.fasta.clean", threads=2,
)
s = " ".join(cmd)
assert "/opt/env/bin/build_comprehensive_transcriptome.dbi" in s, s
assert "-c $WORK/alignAssembly.config" in s and "-t $WORK/transcripts.fasta.clean" in s, s
print("  OK:", s)

cmd = skill.build_command(
    "asmbls_to_training", transcripts_fasta="$WORK/DB.assemblies.fasta",
    transcripts_gff3="$WORK/DB.pasa_assemblies.gff3", threads=2,
)
s = " ".join(cmd)
assert "/opt/env/bin/pasa_asmbls_to_training_set.dbi" in s, s
assert "--pasa_transcripts_fasta $WORK/DB.assemblies.fasta" in s, s
assert "--pasa_transcripts_gff3 $WORK/DB.pasa_assemblies.gff3" in s, s
print("  OK:", s)
PY

echo "==> [5/5] PASA 冒烟（若已安装）"
if command -v Launch_PASA_pipeline.pl >/dev/null 2>&1; then
    Launch_PASA_pipeline.pl --version 2>&1 | head -n 2 || true
else
    echo "  Launch_PASA_pipeline.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
