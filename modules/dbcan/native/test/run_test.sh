#!/usr/bin/env bash
# dbcan native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - hmmpress / makeblastdb / diamond / hmmscan-parser.sh【可选】：若已安装会额外冒烟；
#     否则跳过真实执行。
# 说明：dbCAN V9 注释依赖真实数据库（数百 MB）与建库产物，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证各子命令二进制/参数构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTA / HMM 占位 / domtbl 占位）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/proteins.fasta"
test -f "$WORK/dbCAN-fam-HMMs.txt"
test -f "$WORK/CAZyDB.07312020.fa"
test -f "$WORK/hmmscan.domtbl"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：建库三步（hmmpress / makeblastdb / diamond makedb）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DbcanSkill, build_parser
skill = DbcanSkill()
skill._resolve_binary = lambda name=None: "/env/bin/" + (name or "hmmscan-parser.sh")

# build_hmm -> hmmpress
c1 = " ".join(skill.build_command("build_hmm", hmm_db="$WORK/dbCAN-fam-HMMs.txt"))
assert c1 == "/env/bin/hmmpress $WORK/dbCAN-fam-HMMs.txt", c1
print("  OK:", c1)

# build_blastdb -> makeblastdb
c2 = " ".join(skill.build_command(
    "build_blastdb", fasta="$WORK/CAZyDB.07312020.fa",
    blast_db="$WORK/CAZyDB.07312020", title="CAZyDB.07312020", threads=4,
))
assert c2.startswith("/env/bin/makeblastdb -in $WORK/CAZyDB.07312020.fa -dbtype prot"), c2
assert "-title CAZyDB.07312020 -parse_seqids -out $WORK/CAZyDB.07312020" in c2, c2
assert "-logfile $WORK/CAZyDB.07312020.makeblastdb.log" in c2, c2
print("  OK:", c2)

# build_diamond -> diamond makedb
c3 = " ".join(skill.build_command(
    "build_diamond", fasta="$WORK/CAZyDB.07312020.fa", db="$WORK/CAZyDB.07312020", threads=4,
))
assert c3 == "/env/bin/diamond makedb --in $WORK/CAZyDB.07312020.fa --db $WORK/CAZyDB.07312020", c3
print("  OK:", c3)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["hmmscan", "--hmm_db", "$WORK/dbCAN-fam-HMMs.txt", "--fasta", "$WORK/proteins.fasta",
     "--domtblout", "$WORK/out.domtbl", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "hmmscan" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK: parser hmmscan")
PY

echo "==> [4/5] argv 构造验证 #2：hmmscan / diamond_blastp / parse_hmmscan"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DbcanSkill
skill = DbcanSkill()
skill._resolve_binary = lambda name=None: "/env/bin/" + (name or "hmmscan-parser.sh")

# hmmscan：--cpu 注入 + -E/--domE
c1 = " ".join(skill.build_command(
    "hmmscan", hmm_db="$WORK/dbCAN-fam-HMMs.txt", fasta="$WORK/proteins.fasta",
    domtblout="$WORK/hmmscan.domtbl", evalue=1e-3, dom_evalue=1e-3, threads=8,
))
assert c1.startswith("/env/bin/hmmscan --cpu 8"), c1
assert "-E 0.001" in c1 and "--domE 0.001" in c1, c1
assert "--domtblout $WORK/hmmscan.domtbl $WORK/dbCAN-fam-HMMs.txt $WORK/proteins.fasta" in c1, c1
print("  OK:", c1)

# diamond_blastp：--threads 注入 + 关键参数
c2 = " ".join(skill.build_command(
    "diamond_blastp", db="$WORK/CAZyDB.07312020", fasta="$WORK/proteins.fasta",
    output="$WORK/diamond.xml", outfmt=5, sensitive=True, max_target_seqs=500,
    evalue=1e-5, min_id=20, index_chunks=1, threads=8,
))
assert c2.startswith("/env/bin/diamond blastp --db $WORK/CAZyDB.07312020 --query $WORK/proteins.fasta"), c2
assert "--out $WORK/diamond.xml" in c2 and "--outfmt 5" in c2 and "--sensitive" in c2, c2
assert "--max-target-seqs 500" in c2 and "--evalue 1e-05" in c2 and "--id 20" in c2, c2
assert "--index-chunks 1" in c2 and "--threads 8" in c2, c2
print("  OK:", c2)

# parse_hmmscan -> hmmscan-parser.sh
c3 = " ".join(skill.build_command("parse_hmmscan", domtblout="$WORK/hmmscan.domtbl", threads=1))
assert c3 == "/env/bin/hmmscan-parser.sh $WORK/hmmscan.domtbl", c3
print("  OK:", c3)

# 缺参保护
for sub, kw in (("build_hmm", {}), ("build_blastdb", {"fasta": "x"}), ("hmmscan", {"hmm_db": "x"}),
                ("diamond_blastp", {"db": "x"}), ("parse_hmmscan", {})):
    try:
        skill.build_command(sub, **kw)
    except ValueError as e:
        print(f"  OK: {sub} 缺参抛错 ->", e)
    else:
        raise SystemExit(f"{sub} 缺必填参数时应抛 ValueError")
PY

echo "==> [5/5] 底层工具冒烟（若已安装）"
for t in hmmpress makeblastdb diamond hmmscan; do
    if command -v "$t" >/dev/null 2>&1; then
        echo "  已安装: ${t}"
    else
        echo "  未安装: ${t} (跳过该工具冒烟)"
    fi
done

echo "ALL TESTS PASSED"
