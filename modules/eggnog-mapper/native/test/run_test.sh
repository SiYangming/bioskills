#!/usr/bin/env bash
# eggnog-mapper native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - emapper.py 二进制【可选】：若已安装（conda activate eggnog-mapper / PATH 中有 emapper.py），
#     会额外做冒烟；否则跳过真实执行。
# 说明：真实注释依赖 emapperdb-4.5.1（数十 GB），合成数据无法覆盖，因此采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（蛋白 FASTA + 命中表占位）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/proteins.fasta"
test -f "$WORK/hits.tsv"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：annotate（DIAMOND 路线）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EggnogMapperSkill, build_parser
skill = EggnogMapperSkill()
skill._resolve_binary = lambda name=None: "/opt/env/bin/" + (name or "emapper.py")
cmd = skill.build_command(
    "annotate", input="$WORK/proteins.fasta", output="eggNOG",
    method="diamond", data_dir="$WORK/emapperdb-4.5.1",
    tax_scope="Fungi", target_orthologs="one2one", go_evidence="non-electronic",
    no_file_comments=True, threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/emapper.py"), s
assert "-i $WORK/proteins.fasta" in s, s
assert "-o eggNOG" in s, s
assert "-m diamond" in s and "--cpu 8" in s, s
assert "--data_dir $WORK/emapperdb-4.5.1" in s, s
assert "--tax_scope Fungi" in s and "--target_orthologs one2one" in s, s
assert "--go_evidence non-electronic" in s and "--no_file_comments" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["annotate", "-i", "$WORK/proteins.fasta", "-o", "out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "annotate" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser annotate")
PY

echo "==> [4/5] argv 构造验证 #2：annotate_hits / download_db"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EggnogMapperSkill
skill = EggnogMapperSkill()
skill._resolve_binary = lambda name=None: "/opt/env/bin/" + (name or "emapper.py")

# annotate_hits：--annotate_hits_table
c1 = " ".join(skill.build_command(
    "annotate_hits", hits_table="$WORK/hits.tsv", output="eggNOG",
    data_dir="$WORK/emapperdb-4.5.1", no_file_comments=True, threads=4,
))
assert "/opt/env/bin/emapper.py" in c1, c1
assert "--annotate_hits_table $WORK/hits.tsv" in c1, c1
assert "-o eggNOG" in c1 and "--cpu 4" in c1, c1
print("  OK:", c1)

# download_db：换用 download_eggnog_data.py，注入 -y -f
c2 = " ".join(skill.build_command("download_db", data_dir="$WORK/db", db="eggnog.db", threads=1))
assert "/opt/env/bin/download_eggnog_data.py" in c2, c2
assert "--data_dir $WORK/db" in c2 and "-y" in c2 and "-f" in c2, c2
assert "-P eggnog.db" in c2, c2
print("  OK:", c2)

# 缺参保护
for sub, kw in (("annotate", {}), ("annotate_hits", {})):
    try:
        skill.build_command(sub, **kw)
    except ValueError as e:
        print(f"  OK: {sub} 缺参抛错 ->", e)
    else:
        raise SystemExit(f"{sub} 缺必填参数时应抛 ValueError")
PY

echo "==> [5/5] emapper.py 冒烟（若已安装）"
if command -v emapper.py >/dev/null 2>&1; then
    { emapper.py --version || emapper.py -v; } 2>&1 | head -n 1
else
    echo "  emapper.py 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
