#!/usr/bin/env bash
# sepp native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - run_sepp.py / run_upp.py 二进制【可选】：若已安装（conda activate <env> / PATH 中有），
#     会额外做 run_sepp.py -v 冒烟；否则跳过真实执行。
# 说明：SEPP 真实放置需参考树/比对/片段并调用 HMMER/RAxML，合成数据无法覆盖真实计算，
#      因此对 run/upp 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小树/比对/片段占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run（SEPP 放置，自动注入 -x/-p）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeppSkill, build_parser
skill = SeppSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/run_sepp.py"
cmd = skill.build_command(
    "run", tree="$WORK/ref.tree", alignment="$WORK/ref_aln.fasta",
    fragment="$WORK/fragments.fasta", raxml_info="$WORK/ref.RAxML_info",
    output_prefix="placements", outdir="$WORK/out", alignment_size=10, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/run_sepp.py" in s, s
assert "-t $WORK/ref.tree" in s and "-a $WORK/ref_aln.fasta" in s, s
assert "-f $WORK/fragments.fasta" in s and "-r $WORK/ref.RAxML_info" in s, s
assert "-A 10" in s and "-o placements" in s and "-d $WORK/out" in s, s
assert "-x 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "-t", "$WORK/ref.tree", "-a", "$WORK/ref_aln.fasta",
     "-f", "$WORK/fragments.fasta", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证 #2：upp（UPP 比对）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SeppSkill
skill = SeppSkill()
skill._resolve_binary = lambda *a, **k: "run_upp.py"
cmd = skill.build_command(
    "upp", sequence_file="$WORK/seqs.fasta", output_prefix="upp_out",
    outdir="$WORK/upp", alignment_size=10, threads=8,
)
s = " ".join(cmd)
assert s.startswith("run_upp.py"), s
assert "-s $WORK/seqs.fasta" in s, s
assert "-A 10" in s and "-o upp_out" in s and "-d $WORK/upp" in s, s
assert "-x 8" in s, s
print("  OK:", s)
PY

echo "==> [5/5] sepp 冒烟（若已安装：run_sepp.py -v）"
if command -v run_sepp.py >/dev/null 2>&1; then
    run_sepp.py -v 2>&1 | head -n 1 || true
else
    echo "  run_sepp.py 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
