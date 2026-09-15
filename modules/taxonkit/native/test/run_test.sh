#!/usr/bin/env bash
# taxonkit native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - taxonkit 二进制【可选】：若已安装（conda activate taxonkit / PATH 中有 taxonkit），
#     会额外做 taxonkit version 冒烟；否则跳过真实执行。
# 说明：taxonkit 真实查询依赖完整 NCBI Taxonomy 数据库（~/.taxonkit，数百 MB），合成数据无法
#      覆盖真实计算，因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（TaxID / 名称 / lineage 占位）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/taxids.txt"
test -f "$WORK/names.txt"
test -f "$WORK/lineage.tsv"
test -f "$WORK/sub.fungi.list"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：list（提取真菌界 4751）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TaxonkitSkill, build_parser
skill = TaxonkitSkill()
skill._resolve_binary = lambda: "/opt/env/bin/taxonkit"
cmd = skill.build_command(
    "list", ids="4751", indent="", data_dir="$WORK/.taxonkit",
    output="$WORK/sub.fungi.list", threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/taxonkit list"), s
assert "--ids 4751" in s, s
assert "-j 8" in s, s
assert "--data-dir $WORK/.taxonkit" in s, s
assert "-o $WORK/sub.fungi.list" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["list", "--ids", "4751", "-o", "$WORK/out.list", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "list" and ns.ids == "4751" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK: parser list")
PY

echo "==> [4/5] argv 构造验证 #2：lineage / name2taxid / reformat"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TaxonkitSkill
skill = TaxonkitSkill()
skill._resolve_binary = lambda: "taxonkit"

# lineage：-n -r + data-dir
c1 = " ".join(skill.build_command(
    "lineage", input="$WORK/taxids.txt", show_name=True, show_rank=True,
    data_dir="$WORK/.taxonkit", output="$WORK/lineage.out", threads=4,
))
assert "taxonkit lineage" in c1, c1
assert "$WORK/taxids.txt" in c1 and "-n" in c1 and "-r" in c1, c1
assert "--data-dir $WORK/.taxonkit" in c1 and "-o $WORK/lineage.out" in c1, c1
print("  OK:", c1)

# name2taxid：-j 注入
c2 = " ".join(skill.build_command(
    "name2taxid", input="$WORK/names.txt", data_dir="$WORK/.taxonkit",
    output="$WORK/name2taxid.tsv", threads=8,
))
assert "taxonkit name2taxid" in c2, c2
assert "$WORK/names.txt" in c2 and "-j 8" in c2, c2
print("  OK:", c2)

# reformat：-f 模板 + -i
c3 = " ".join(skill.build_command(
    "reformat", input="$WORK/lineage.tsv", format="{k};{p};{c};{o};{f};{g};{s}",
    data_dir="$WORK/.taxonkit", output="$WORK/taxonomy.tsv", threads=4,
))
assert "taxonkit reformat" in c3, c3
assert "-f {k};{p};{c};{o};{f};{g};{s}" in c3, c3
assert "-i $WORK/lineage.tsv" in c3, c3
print("  OK:", c3)

# version：无需线程/数据目录
c4 = skill.build_command("version", threads=None)
assert c4 == ["taxonkit", "version"], c4
print("  OK:", " ".join(c4))

# 缺参保护
try:
    skill.build_command("list", threads=4)
except ValueError as e:
    print("  OK: 缺 --ids 抛错 ->", e)
else:
    raise SystemExit("list 缺少 --ids 时应抛 ValueError")
PY

echo "==> [5/5] taxonkit 冒烟（若已安装）"
if command -v taxonkit >/dev/null 2>&1; then
    taxonkit version | head -n 1
else
    echo "  taxonkit 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
