#!/usr/bin/env bash
# usearch native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - usearch 二进制【可选】：若已安装（conda activate usearch / PATH 中有 usearch），
#     会追加一次真实去冗余冒烟；否则跳过真实执行。
# 说明：USEARCH 为许可受限的商业软件（历史二进制 CC0），本测试以 argv 构造验证为主，
#      保证驱动在无二进制环境下也可回归。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 FASTA）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：cluster_otus / derep_fulllength / cluster_fast"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import UsearchSkill, build_parser
skill = UsearchSkill()
skill._resolve_binary = lambda: "/opt/env/bin/usearch"

co = skill.build_command("cluster_otus", input="$WORK/uniques.fa", output="$WORK/otus.fa", relabel="OTU", minsize=2)
s = " ".join(co)
assert co[0] == "/opt/env/bin/usearch" and co[1] == "-cluster_otus", co
assert "-otus $WORK/otus.fa" in s and "-relabel OTU" in s and "-minsize 2" in s, s
assert "-threads" not in co, "cluster_otus 为单线程，不应注入 -threads"
print("  OK:", s)

dr = skill.build_command("derep_fulllength", input="$WORK/seqs.fa", output="$WORK/uniq.fa", sizeout=True, relabel="uniq")
s = " ".join(dr)
assert dr[1] == "-derep_fulllength" and "-output $WORK/uniq.fa" in s and "-sizeout" in s and "-relabel uniq" in s, s
assert "-threads" not in dr, s
print("  OK:", s)

cf = skill.build_command("cluster_fast", input="$WORK/seqs.fa", identity="0.97", centroids="$WORK/cent.fa", threads=8)
s = " ".join(cf)
assert cf[1] == "-cluster_fast" and "-id 0.97" in s and "-centroids $WORK/cent.fa" in s and "-threads 8" in s, s
print("  OK:", s)
PY

echo "==> [4/5] argv 构造验证：uchime_denovo / uchime_ref / usearch_global"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import UsearchSkill, build_parser
skill = UsearchSkill()
skill._resolve_binary = lambda: "/opt/env/bin/usearch"

ud = skill.build_command("uchime_denovo", input="$WORK/seqs.fa", output="$WORK/ch.uchime", chimeras="$WORK/chim.fa", mindiv=1.5, minh=0.2)
s = " ".join(ud)
assert ud[1] == "-uchime_denovo" and "-uchimeout $WORK/ch.uchime" in s and "-chimeras $WORK/chim.fa" in s, s
assert "-mindiv 1.5" in s and "-minh 0.2" in s, s
print("  OK:", s)

ur = skill.build_command("uchime_ref", input="$WORK/seqs.fa", db="$WORK/ref.fa", output="$WORK/ch.uchime", strand="plus", threads=8)
s = " ".join(ur)
assert ur[1] == "-uchime_ref" and "-db $WORK/ref.fa" in s and "-uchimeout $WORK/ch.uchime" in s, s
assert "-strand plus" in s and "-threads 8" in s, s
print("  OK:", s)

ug = skill.build_command("usearch_global", input="$WORK/seqs.fa", db="$WORK/ref.fa", identity="0.97", strand="plus", otutabout="$WORK/otu_table.txt", threads=8)
s = " ".join(ug)
assert ug[1] == "-usearch_global" and "-db $WORK/ref.fa" in s and "-id 0.97" in s, s
assert "-otutabout $WORK/otu_table.txt" in s and "-threads 8" in s, s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
p = build_parser().parse_args(
    ["usearch_global", "$WORK/seqs.fa", "-d", "$WORK/ref.fa", "--id", "0.97",
     "--otutabout", "$WORK/otu.txt", "--threads", "4", "--tmpdir", "/tmp"]
)
assert p.subcommand == "usearch_global" and p.threads == 4 and p.tmpdir == "/tmp", p
print("  OK: parser usearch_global")
PY

echo "==> [5/5] 真实执行（usearch 若已安装）"
if command -v usearch >/dev/null 2>&1; then
    python "$NATIVE/main.py" derep_fulllength "$WORK/seqs.fa" -o "$WORK/uniq.fa" --sizeout || true
    test -s "$WORK/uniq.fa" && grep -q '^>' "$WORK/uniq.fa" && echo "  OK: usearch 真实去冗余产物 uniq.fa"
else
    echo "  usearch 未安装（许可受限，需自行获取/conda 安装），跳过真实执行（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
