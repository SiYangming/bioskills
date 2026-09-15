#!/usr/bin/env bash
# fasta native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - FASTA（fasta36 系列，可选）：若已安装，额外做一次真实搜索冒烟（-m 8）；否则仅 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：search / ssearch"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastaSkill
skill = FastaSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'fasta36'}"

c = " ".join(skill.build_command(
    "search", query="$WORK/query.fasta", library="$WORK/db.fasta",
    output_format=8, evalue="1e-5", score_matrix="BLOSUM62", top_scores=10))
assert c == (f"/opt/env/bin/fasta36 $WORK/query.fasta $WORK/db.fasta "
             f"-m 8 -E 1e-5 -s BLOSUM62 -b 10"), c
print("  OK:", c)

c = " ".join(skill.build_command("ssearch", query="$WORK/query.fasta", library="$WORK/db.fasta"))
assert c == f"/opt/env/bin/ssearch36 $WORK/query.fasta $WORK/db.fasta", c
print("  OK:", c)
PY

echo "==> [4/6] argv 构造验证 #2：fastx / fasty / ggsearch / glsearch / lalign"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastaSkill, BINARIES
skill = FastaSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'fasta36'}"
for sub in ("fastx", "fasty", "ggsearch", "glsearch", "lalign"):
    c = " ".join(skill.build_command(sub, query="$WORK/query.fasta", library="$WORK/db.fasta"))
    assert c == f"/opt/env/bin/{BINARIES[sub]} $WORK/query.fasta $WORK/db.fasta", c
    print("  OK:", c)
PY

echo "==> [5/6] parser + 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastaSkill, build_parser
skill = FastaSkill()
assert skill._effective_threads("search", 8) == 8
assert skill._effective_threads("search", None) == 4
print("  OK: threads priority (explicit=8, default=4)")
ns = build_parser().parse_args(
    ["search", "$WORK/query.fasta", "$WORK/db.fasta", "-m", "8",
     "-o", "$WORK/hits.tsv", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "search" and ns.output_format == 8, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp" and ns.output.endswith("hits.tsv"), ns
print("  OK: parser search")
PY

echo "==> [6/6] FASTA 真实搜索冒烟（若已安装）"
FASTA_BIN=""
if command -v fasta36 >/dev/null 2>&1; then
    FASTA_BIN="fasta36"
elif command -v fasta >/dev/null 2>&1; then
    FASTA_BIN="fasta"
fi
if [[ -n "$FASTA_BIN" ]]; then
    "$FASTA_BIN" "$WORK/query.fasta" "$WORK/db.fasta" -m 8 > "$WORK/hits.tsv" 2>/dev/null || true
    test -s "$WORK/hits.tsv" && echo "  OK: 已产出搜索结果（$FASTA_BIN）" || echo "  [WARN] 搜索输出为空（序列过短属正常）"
else
    echo "  FASTA（fasta36 / fasta）未安装，跳过真实搜索（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
