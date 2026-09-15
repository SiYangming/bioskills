#!/usr/bin/env bash
# maker native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - maker/gff3_merge（可选）：MAKER 真实运行需完整证据集与大量依赖，测试不依赖真实安装；
#     若有 maker 则额外做 maker --version 冒烟。
# 说明：所有子命令以「python 构造 argv（monkeypatch 二进制路径）验证命令构建」为主。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：ctl / run（常规）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MakerSkill
skill = MakerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'maker'}"

c = " ".join(skill.build_command("ctl"))
assert c == "/opt/env/bin/maker -CTL", c
print("  OK:", c)

c = " ".join(skill.build_command(
    "run", genome="$WORK/genome.fasta", est="$WORK/Trinity.fasta",
    protein="$WORK/homolog.fasta", model_org="fungi", rmlib="$WORK/consensi.fa",
    augustus_species="malassezia_sympodialis", snaphmm="$WORK/species.hmm",
    gmhmm="$WORK/gmhmm.mod", est2genome=True, protein2genome=True, trna=True,
    fix_nucleotides=True, base="genome",
))
expect = (" /opt/env/bin/maker -base genome -fix_nucleotides "
          f"$WORK/genome.fasta -est $WORK/Trinity.fasta -protein $WORK/homolog.fasta "
          f"-model_org fungi -rmlib $WORK/consensi.fa "
          f"-augustus_species malassezia_sympodialis -snaphmm $WORK/species.hmm "
          f"-gmhmm $WORK/gmhmm.mod -est2genome -protein2genome -trna").strip()
assert c == expect, f"\n got: {c}\nwant: {expect}"
print("  OK: run")
PY

echo "==> [4/6] argv 构造验证 #2：run --mpi（线程经 mpiexec -n 透传）+ merge + fasta_merge"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MakerSkill
skill = MakerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'maker'}"

c = " ".join(skill.build_command("run", genome="$WORK/genome.fasta", mpi=True, threads=8))
assert c == f"/opt/env/bin/mpiexec -n 8 /opt/env/bin/maker $WORK/genome.fasta", c
print("  OK:", c)

c = " ".join(skill.build_command(
    "merge", datastore_index_log="$WORK/genome_master_datastore_index.log",
    output="$WORK/genome.all.gff"))
assert c == (f"/opt/env/bin/gff3_merge -d $WORK/genome_master_datastore_index.log "
             f"-o $WORK/genome.all.gff"), c
print("  OK:", c)

c = " ".join(skill.build_command(
    "fasta_merge", datastore_index_log="$WORK/genome_master_datastore_index.log"))
assert c == f"/opt/env/bin/fasta_merge -d $WORK/genome_master_datastore_index.log", c
print("  OK:", c)
PY

echo "==> [5/6] parser + 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MakerSkill, build_parser
skill = MakerSkill()
assert skill._effective_threads("run", 16) == 16
assert skill._effective_threads("run", None) == 8
assert skill._effective_threads("merge", None) == 2
print("  OK: threads priority (explicit=16, run=8, merge=2)")
ns = build_parser().parse_args(
    ["run", "$WORK/genome.fasta", "-est", "$WORK/Trinity.fasta", "--mpi",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.mpi and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.est.endswith("Trinity.fasta"), ns
print("  OK: parser run")
PY

echo "==> [6/6] maker 冒烟（若已安装）"
if command -v maker >/dev/null 2>&1; then
    maker --version | head -n 1 || true
else
    echo "  maker 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
