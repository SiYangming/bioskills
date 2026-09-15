#!/usr/bin/env bash
# metaeuk native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - metaeuk【可选】：若已安装（PATH 中有 metaeuk），会额外做 metaeuk version 冒烟；否则跳过。
# 说明：MetaEuk 真实运行需要 MMseqs2 建库 + 同源搜索，合成数据无法覆盖真实计算，
#      因此对 easy_predict/easy_search/taxtocontig/version 采用
#      「python 构造 argv 验证命令构建不崩溃（monkeypatch 二进制解析）」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小 FASTA / TSV 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：easy_predict / easy_search"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MetaeukSkill, build_parser
skill = MetaeukSkill()
skill._resolve_binary = lambda: "/opt/env/bin/metaeuk"

cmd = skill.build_command(
    "easy_predict", contigs="$WORK/contigs.fna", targets="$WORK/proteins.faa",
    out_prefix="$WORK/preds", tmp_dir="$WORK/tmp", threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/metaeuk easy-predict"), s
assert "$WORK/contigs.fna $WORK/proteins.faa $WORK/preds $WORK/tmp" in s, s
assert "--threads 8" in s, s
print("  OK easy_predict:", s)

# tmp_dir 缺省时取 self.tmpdir
skill.tmpdir = "/scratch/tmp"
cmd = skill.build_command(
    "easy_predict", contigs="$WORK/contigs.fna", targets="$WORK/proteins.faa",
    out_prefix="$WORK/preds",
)
assert cmd[5] == "/scratch/tmp", cmd
print("  OK easy_predict(tmpdir 缺省):", " ".join(cmd))

cmd = skill.build_command(
    "easy_search", query="$WORK/query.faa", target="$WORK/target.faa",
    out_file="$WORK/hits.m8", tmp_dir="$WORK/tmp", threads=4,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/metaeuk easy-search"), s
assert "$WORK/query.faa $WORK/target.faa $WORK/hits.m8 $WORK/tmp" in s, s
assert "--threads 4" in s, s
print("  OK easy_search:", s)

# 缺参应报 ValueError
try:
    skill.build_command("easy_predict", contigs="$WORK/contigs.fna")
    raise SystemExit("[FAIL] easy_predict 缺参未报错")
except ValueError:
    print("  OK: 缺参校验触发")

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["easy_predict", "$WORK/contigs.fna", "$WORK/proteins.faa", "$WORK/preds",
     "$WORK/tmp", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "easy_predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser easy_predict")
PY

echo "==> [4/5] argv 构造验证 #2：taxtocontig / version"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MetaeukSkill
skill = MetaeukSkill()
skill._resolve_binary = lambda: "/opt/env/bin/metaeuk"

cmd = skill.build_command(
    "taxtocontig", contigs_db="$WORK/contigsDB", preds_fas="$WORK/preds.fas",
    headers_map="$WORK/headersMap.tsv", tax_target_db="$WORK/seqTaxDb.tsv",
    out_file="$WORK/taxResult", tmp_dir="$WORK/tmp", majority=0.5, threads=2,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/metaeuk taxtocontig"), s
assert "$WORK/contigsDB $WORK/preds.fas $WORK/headersMap.tsv $WORK/seqTaxDb.tsv $WORK/taxResult $WORK/tmp" in s, s
assert "--majority 0.5" in s and "--threads 2" in s, s
print("  OK taxtocontig:", s)

cmd = skill.build_command("version")
assert cmd == ["/opt/env/bin/metaeuk", "version"], cmd
print("  OK version:", " ".join(cmd))
PY

echo "==> [5/5] metaeuk 冒烟（若已安装）"
if command -v metaeuk >/dev/null 2>&1; then
    metaeuk version | head -n 1
else
    echo "  metaeuk 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
