#!/usr/bin/env bash
# genemarks native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - gms2.pl / gmsn.pl 脚本【可选】：若已安装（PATH 中有），会额外做存在性探测；否则跳过真实执行。
#   - 真实预测还需密钥（~/.gmhmmp2_key），本测试不触发真实预测。
# 说明：GeneMarkS/GeneMarkS-2 真实预测需密钥 + 一定长度基因组，合成数据无法覆盖真实计算，
#      因此对 gms2/gms 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（约 30 kb 合成基因组 + 密钥说明）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：gms2（GeneMarkS-2）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkSSkill, build_parser
skill = GeneMarkSSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/gms2.pl"
cmd = skill.build_command(
    "gms2", input="$WORK/genome.fasta", genome_type="bacteria", gcode=11,
    format="gff", output="$WORK/gms2.gff",
    fnn="$WORK/genes.fasta", faa="$WORK/proteins.fasta",
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/gms2.pl"), s
assert "--seq $WORK/genome.fasta" in s, s
assert "--genome-type bacteria" in s and "--gcode 11" in s, s
assert "--format gff" in s and "--output $WORK/gms2.gff" in s, s
assert "--fnn $WORK/genes.fasta" in s and "--faa $WORK/proteins.fasta" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["gms2", "-i", "$WORK/genome.fasta", "--genome-type", "bacteria",
     "--format", "gff", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "gms2" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser gms2")
PY

echo "==> [4/6] argv 构造验证 #2：gms（旧版 GeneMarkS，位置参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkSSkill
skill = GeneMarkSSkill()
skill._resolve_binary = lambda *a, **k: "gmsn.pl"
cmd = skill.build_command("gms", input="$WORK/genome.fasta", format="GFF",
                          fnn=True, faa=True, pdf=True)
s = " ".join(cmd)
assert s.startswith("gmsn.pl"), s
assert "--prok" in s and "--format GFF" in s, s
assert "--fnn" in s and "--faa" in s and "--pdf" in s, s
assert s.endswith("$WORK/genome.fasta"), s
print("  OK:", s)
PY

echo "==> [5/6] argv 错误处理：缺 input 应报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneMarkSSkill
skill = GeneMarkSSkill()
skill._resolve_binary = lambda *a, **k: "gms2.pl"
try:
    skill.build_command("gms2", genome_type="bacteria")
    raise SystemExit("  [FAIL] gms2 缺 input 未报错")
except ValueError:
    print("  OK: gms2 缺 input 正确报错")
PY

echo "==> [6/6] genemarks 脚本存在性冒烟（若已安装）"
if command -v gms2.pl >/dev/null 2>&1; then
    echo "  已安装：$(command -v gms2.pl)"
else
    echo "  gms2.pl 未安装（未申请密钥/未部署），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
