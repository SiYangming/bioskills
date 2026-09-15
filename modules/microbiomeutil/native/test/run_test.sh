#!/usr/bin/env bash
# microbiomeutil native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
# 说明：ChimeraSlayer / NAST-iEr / WigeoN 的真实运行需要 megablast 参考库与 cdbtools
#      （重依赖，无法用小合成数据端到端跑通），因此本测试对三个子命令采用
#      「python 构造 argv 验证命令构建不崩溃 + parser 可解析」的断言方式，
#      并在 PATH 中已存在脚本时追加一次帮助/自省冒烟。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（合成 FASTA / NAST）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：chimeraslayer / nastier / wigeon"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MicrobiomeutilSkill, build_parser, SCRIPT_BY_SUBCOMMAND
skill = MicrobiomeutilSkill()
skill._resolve_binary_for = lambda sub: f"/opt/env/bin/{SCRIPT_BY_SUBCOMMAND[sub]}"

cs = skill.build_command(
    "chimeraslayer", query_nast="$WORK/query.NAST", db_nast="$WORK/ref.NAST",
    db_fasta="$WORK/ref.fasta", exec_dir="$WORK", num_db_seqs=15,
    min_div_ratio=1.007, min_pct_id=90, min_bs=90, threads=1,
)
s = " ".join(cs)
assert cs[0] == "/opt/env/bin/ChimeraSlayer.pl", cs
assert "--query_NAST $WORK/query.NAST" in s, s
assert "--db_NAST $WORK/ref.NAST" in s and "--db_FASTA $WORK/ref.fasta" in s, s
assert "--exec_dir $WORK" in s and "-n 15" in s and "-R 1.007" in s and "-P 90" in s, s
assert "--minBS 90" in s, s
print("  OK:", s)

ns = skill.build_command(
    "nastier", query_fasta="$WORK/query.fasta", db_nast="$WORK/ref.NAST",
    db_fasta="$WORK/ref.fasta", num_top_hits=10, evalue="1e-50", threads=1,
)
s = " ".join(ns)
assert ns[0] == "/opt/env/bin/run_NAST-iEr.pl", ns
assert "--query_FASTA $WORK/query.fasta" in s, s
assert "--num_top_hits 10" in s and "--Evalue 1e-50" in s, s
print("  OK:", s)

wg = skill.build_command("wigeon", query_nast="$WORK/query.NAST", num_top_hits=1, plot=True, threads=1)
s = " ".join(wg)
assert wg[0] == "/opt/env/bin/run_WigeoN.pl", wg
assert "--query_NAST $WORK/query.NAST" in s and "--num_top_hits 1" in s and "--plot" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
p = build_parser().parse_args(
    ["chimeraslayer", "--query-nast", "$WORK/query.NAST", "--threads", "2", "--tmpdir", "/tmp"]
)
assert p.subcommand == "chimeraslayer" and p.threads == 2 and p.tmpdir == "/tmp", p
print("  OK: parser chimeraslayer")
PY

echo "==> [4/4] 冒烟（PATH 中已有组件时）"
if command -v ChimeraSlayer.pl >/dev/null 2>&1; then
    echo "  ChimeraSlayer.pl: $(command -v ChimeraSlayer.pl)"
else
    echo "  ChimeraSlayer.pl 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
