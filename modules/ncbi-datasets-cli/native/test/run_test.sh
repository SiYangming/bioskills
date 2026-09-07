#!/usr/bin/env bash
# ncbi-datasets-cli native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - datasets / dataformat 二进制【可选】：若已安装（PATH 中有），额外做冒烟；
#     否则跳过真实执行。
# 说明：datasets download/summary 与 dataformat 需联网访问 NCBI 且真实下载不可行，因此对
#      datasets（download/summary）与 dataformat 采用「python 构造 argv 验证命令构建不崩溃」的
#      断言方式 + --list-commands/--schema/help 自省 + install.sh bash -n 语法检查。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/8] 生成测试占位数据"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/accessions.txt"

echo "==> [2/8] 自省：--list-commands / --schema / help"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^datasets " "$WORK/commands.txt"
grep -q "^dataformat " "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json; json.load(open('$WORK/schema.json')); print('  schema JSON 合法')"
python "$NATIVE/main.py" help | tee "$WORK/help.txt"
grep -q "dataformat" "$WORK/help.txt"

echo "==> [3/8] argv 构造验证 #1：datasets download（accession 模式，--include genome,gff3 + -o）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NcbiDatasetsCliSkill, build_parser
skill = NcbiDatasetsCliSkill()
skill._resolve_binary = lambda: "/opt/env/bin/datasets"
cmd = skill.build_command(
    "datasets", action="download", accession="GCF_000001405.39", include="genome,gff3",
    output_file="$WORK/ncbi_dataset.zip",
)
s = " ".join(cmd)
assert "/opt/env/bin/datasets download genome accession GCF_000001405.39" in s, s
assert "--include genome,gff3" in s, s
assert "--filename $WORK/ncbi_dataset.zip" in s, s
print("  OK:", s)
# parser 可解析完整 argv（datasets 二级 download，子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["datasets", "download", "GCF_000001405.39", "--include", "genome",
     "-o", "$WORK/out.zip", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "datasets" and ns.action == "download", ns
assert ns.include == "genome" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser datasets download")
PY

echo "==> [4/8] argv 构造验证 #2：datasets download（taxon 模式 + --dehydrated + 多 accession）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NcbiDatasetsCliSkill
skill = NcbiDatasetsCliSkill()
skill._resolve_binary = lambda: "/opt/env/bin/datasets"
cmd = skill.build_command(
    "datasets", action="download", taxon="Homo sapiens", include="gff3,gbff", dehydrated=True,
)
s = " ".join(cmd)
assert "datasets download genome taxon Homo sapiens" in s, s
assert "--include gff3,gbff" in s and "--dehydrated" in s, s
print("  OK:", s)
cmd2 = skill.build_command(
    "datasets", action="download", accession="GCF_000001405.39, GCF_000009045.1", include="genome")
s2 = " ".join(cmd2)
assert "accession GCF_000001405.39 GCF_000009045.1" in s2, s2
print("  OK:", s2)
# datasets 缺 action 应报错
try:
    skill.build_command("datasets", accession="GCF_000001405.39")
    raise SystemExit("datasets 缺 action 未报错")
except ValueError as e:
    print("  OK: datasets 缺 action 报错 ->", e)
PY

echo "==> [5/8] argv 构造验证 #3：datasets summary（accession JSON 行模式 / taxon 模式）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NcbiDatasetsCliSkill, build_parser
skill = NcbiDatasetsCliSkill()
skill._resolve_binary = lambda: "datasets"
cmd = skill.build_command(
    "datasets", action="summary", accession="GCF_000001405.39", json_lines=True, report="assembly_stats",
)
s = " ".join(cmd)
assert "datasets summary genome accession GCF_000001405.39" in s, s
assert "--as-json-lines" in s and "--report assembly_stats" in s, s
print("  OK:", s)
cmd2 = skill.build_command("datasets", action="summary", taxon="Homo sapiens")
s2 = " ".join(cmd2)
assert "datasets summary genome taxon Homo sapiens" in s2, s2
print("  OK:", s2)
ns = build_parser().parse_args(["datasets", "summary", "--taxon", "Homo sapiens", "--threads", "2"])
assert ns.subcommand == "datasets" and ns.action == "summary" and ns.taxon == "Homo sapiens", ns
print("  OK: parser datasets summary")
try:
    skill.build_command("datasets", action="summary", report="assembly_stats")
    raise SystemExit("summary 缺少 selector 未报错")
except ValueError as e:
    print("  OK: summary 缺 selector 报错 ->", e)
PY

echo "==> [6/8] argv 构造验证 #4：dataformat（tsv genome --package / accession selector / 缺 selector 报错）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NcbiDatasetsCliSkill, build_parser
skill = NcbiDatasetsCliSkill()
skill._resolve_dataformat_binary = lambda: "/opt/env/bin/dataformat"
cmd = skill.build_command("dataformat", fmt="tsv", report_type="genome", package="$WORK/ncbi_dataset.zip")
s = " ".join(cmd)
assert "/opt/env/bin/dataformat tsv genome --package $WORK/ncbi_dataset.zip" in s, s
print("  OK:", s)
# 默认 fmt/report_type + accession selector
cmd2 = skill.build_command("dataformat", accession="GCF_000001405.39,GCF_000009045.1")
s2 = " ".join(cmd2)
assert "dataformat tsv genome" in s2 and "--accession GCF_000001405.39 GCF_000009045.1" in s2, s2
print("  OK:", s2)
# 缺 selector 报错
try:
    skill.build_command("dataformat", fields="assmaccn,organism_name")
    raise SystemExit("dataformat 缺 selector 未报错")
except ValueError as e:
    print("  OK: dataformat 缺 selector 报错 ->", e)
# parser：dataformat tsv gene --taxon
ns = build_parser().parse_args(["dataformat", "tsv", "gene", "--taxon", "Homo sapiens", "--fields", "gene_id,symbol"])
assert ns.subcommand == "dataformat" and ns.fmt == "tsv" and ns.report_type == "gene", ns
assert ns.taxon == "Homo sapiens" and ns.fields == "gene_id,symbol", ns
print("  OK: parser dataformat")
PY

echo "==> [7/8] install.sh 语法检查（bash -n）"
bash -n "$NATIVE/install.sh"
echo "  OK: install.sh 语法通过"
bash "$NATIVE/install.sh" --help >/dev/null 2>&1
echo "  OK: install.sh --help 退出码 0"

echo "==> [8/8] 二进制冒烟（若已安装）"
if command -v datasets >/dev/null 2>&1; then
    datasets --version | head -n 1
fi
if command -v dataformat >/dev/null 2>&1; then
    dataformat version | head -n 1
fi
if ! command -v datasets >/dev/null 2>&1 && ! command -v dataformat >/dev/null 2>&1; then
    echo "  datasets/dataformat 未安装，跳过真实冒烟（argv 构造验证已通过；本机实测见 install.sh binary 路线）"
fi

echo "ALL TESTS PASSED"
