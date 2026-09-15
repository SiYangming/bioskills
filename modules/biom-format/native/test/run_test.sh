#!/usr/bin/env bash
# biom-format native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - biom 二进制【可选】：若已安装（conda activate / PATH 中有 biom），
#     会用经典 OTU 表真实 convert + summarize-table；否则跳过真实执行。
# 说明：BIOM 为二进制/JSON 格式，未安装 biom 时无法真实转换，故对 convert/summarize-table
#      采用「python 构造 argv 验证命令构建不崩溃」的断言方式；并用空 PATH 断言缺二进制约错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（经典 OTU 表 + 占位 BIOM）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^convert'
python "$NATIVE/main.py" --list-commands | grep -q '^summarize-table'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：convert（BIOM -> TSV，带 taxonomy 表头）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BiomFormatSkill, build_parser

skill = BiomFormatSkill()
skill._resolve_binary = lambda: "/opt/env/bin/biom"
cmd = skill.build_command("convert", input="$WORK/feature-table.biom",
                          output="$WORK/feature-table.tsv", to_tsv=True,
                          header_key="taxonomy")
assert cmd == ["/opt/env/bin/biom", "convert", "-i", "$WORK/feature-table.biom",
               "-o", "$WORK/feature-table.tsv", "--to-tsv",
               "--header-key", "taxonomy"], cmd
print("  OK:", " ".join(cmd))

# 经典 OTU 表 -> HDF5
cmd = skill.build_command("convert", input="$WORK/classic_table.tsv",
                          output="$WORK/table.biom", to_hdf5=True,
                          table_type="OTU table")
s = " ".join(cmd)
assert "--to-hdf5" in s and "--table-type OTU table" in s, s
print("  OK:", s)

# 缺格式项 / 多个格式项 -> ValueError
for bad in (dict(), dict(to_tsv=True, to_hdf5=True)):
    try:
        skill.build_command("convert", input="$WORK/x.biom", output="$WORK/y.tsv", **bad)
        raise AssertionError("格式项非法时应收 ValueError: %r" % bad)
    except ValueError:
        pass
print("  OK: convert 格式项校验（恰好一个）")

ns = build_parser().parse_args(["convert", "-i", "$WORK/a.biom", "-o", "$WORK/a.tsv",
                                "--to-tsv", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "convert" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.to_tsv and not ns.to_json, ns
print("  OK: parser convert")
PY

echo "==> [4/6] argv 构造验证 #2：summarize-table"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BiomFormatSkill, build_parser

skill = BiomFormatSkill()
skill._resolve_binary = lambda: "biom"

cmd = skill.build_command("summarize-table", input="$WORK/feature-table.biom")
assert cmd == ["biom", "summarize-table", "-i", "$WORK/feature-table.biom"], cmd
print("  OK:", " ".join(cmd))

cmd = skill.build_command("summarize-table", input="$WORK/feature-table.biom",
                          output="$WORK/summary.txt", qualitative=True, observations=True)
assert cmd == ["biom", "summarize-table", "-i", "$WORK/feature-table.biom",
               "-o", "$WORK/summary.txt", "--qualitative", "--observations"], cmd
print("  OK:", " ".join(cmd))

ns = build_parser().parse_args(["summarize-table", "-i", "$WORK/a.biom",
                                "-o", "$WORK/s.txt", "--qualitative",
                                "--threads", "1", "--tmpdir", "/tmp"])
assert ns.subcommand == "summarize-table" and ns.qualitative and ns.threads == 1, ns
print("  OK: parser summarize-table")
PY

echo "==> [5/6] 缺二进制约错（空 PATH）"
python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import BiomFormatSkill
os.environ["PATH"] = ""
try:
    BiomFormatSkill().build_command("summarize-table", input="$WORK/feature-table.biom")
    raise AssertionError("空 PATH 下应因缺少 biom 抛 RuntimeError")
except RuntimeError:
    pass
print("  OK: 空 PATH 下 biom 缺失正确报错")
PY

echo "==> [6/6] 真实回归（biom 可用时：经典表 -> BIOM -> 统计）"
if command -v biom >/dev/null 2>&1; then
    biom --version
    biom convert -i "$WORK/classic_table.tsv" -o "$WORK/table.biom" \
        --table-type "OTU table" --to-hdf5
    test -s "$WORK/table.biom"
    biom summarize-table -i "$WORK/table.biom" -o "$WORK/summary.txt"
    grep -q "Num samples: 2" "$WORK/summary.txt"
    echo "  OK: biom convert + summarize-table 真实回归通过"
else
    echo "  biom 未安装，跳过真实回归（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
