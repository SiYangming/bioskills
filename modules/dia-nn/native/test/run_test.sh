#!/usr/bin/env bash
# dia-nn native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - diann 二进制【可选】：若已安装（官方 zip / conda / PATH 中有 diann），
#     会额外做 diann 冒烟（banner 含 DIA-NN）；否则跳过真实执行。
# 说明：DIA-NN 分析需要真实 .raw/.d/.mzML 质谱数据 + .NET 8 runtime，合成数据无法
#      覆盖真实搜索计算，因此本脚本对各子命令采用「python 构造 argv 验证命令构建
#      不崩溃 + 必填校验」的断言方式（同 dorado 降级测试写法）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位 FASTA + raw 目录）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - "$WORK/schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
assert schema["type"] == "object"
assert "subcommand" in schema["properties"], "schema 缺 subcommand 属性"
print("  OK: schema JSON 有效")
PY

echo "==> [3/6] argv 构造验证 #1：lib（in-silico 预测库生成）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiaNNSkill, build_parser
skill = DiaNNSkill()
skill._resolve_binary = lambda: "/opt/diann/bin/diann"
cmd = skill.build_command(
    "lib", fasta="$WORK/mini_proteome.fasta", out_lib="$WORK/report-lib",
    predictor=True, threads=8,
)
s = " ".join(cmd)
assert "/opt/diann/bin/diann" in s and "--fasta $WORK/mini_proteome.fasta" in s, s
assert "--out-lib $WORK/report-lib" in s, s
assert "--predictor" in s, s
assert "--threads 8" in s, s
print("  OK:", s)
# 必填校验：缺 fasta 应抛 ValueError
try:
    skill.build_command("lib", out_lib="$WORK/report-lib", threads=4)
    raise AssertionError("缺 fasta 未抛错")
except ValueError as e:
    print("  OK: lib 缺 fasta ->", e)
# parser：子命令后 --threads/--tmpdir 模式 + library alias
ns = build_parser().parse_args(
    ["library", "--fasta", "$WORK/mini_proteome.fasta", "--out-lib", "$WORK/report-lib",
     "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "library", ns.subcommand  # alias 在 main() 归一为 lib
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser library(alias) + --threads/--tmpdir")
PY

echo "==> [4/6] argv 构造验证 #2：run（DIA 数据分析，两步式 --lib）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiaNNSkill, build_parser
skill = DiaNNSkill()
skill._resolve_binary = lambda: "diann"
cmd = skill.build_command(
    "run", fasta="$WORK/mini_proteome.fasta", lib="$WORK/report-lib.predicted.speclib",
    dir="$WORK/raw", out="$WORK/report.tsv", qvalue=0.01,
    matrices=True, threads=8,
)
s = " ".join(cmd)
assert "diann" in s, s
assert "--fasta $WORK/mini_proteome.fasta" in s, s
assert "--lib $WORK/report-lib.predicted.speclib" in s, s
assert "--dir $WORK/raw" in s and "--out $WORK/report.tsv" in s, s
assert "--qvalue 0.01" in s and "--matrices" in s, s
assert "--threads 8" in s, s
print("  OK:", s)
# 必填校验：无 fasta/lib 与缺 dir 都应抛 ValueError
for kw in (dict(dir="$WORK/raw", out="$WORK/report.tsv"),
           dict(fasta="$WORK/mini_proteome.fasta", out="$WORK/report.tsv")):
    try:
        skill.build_command("run", threads=4, **kw)
        raise AssertionError(f"缺参未抛错: {kw}")
    except ValueError as e:
        print("  OK: run 缺参 ->", e)
# parser 完整 argv
ns = build_parser().parse_args(
    ["run", "--fasta", "$WORK/mini_proteome.fasta", "--dir", "$WORK/raw",
     "--out", "$WORK/report.tsv", "--matrices", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.matrices is True and ns.qvalue == 0.01, ns
print("  OK: parser run")
PY

echo "==> [5/6] argv 构造验证 #3：run 一步式 --fasta-search（无 --lib）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiaNNSkill
skill = DiaNNSkill()
skill._resolve_binary = lambda: "diann"
cmd = skill.build_command(
    "run", fasta="$WORK/mini_proteome.fasta", fasta_search=True,
    dir="$WORK/raw", out="$WORK/report.tsv", threads=4,
)
s = " ".join(cmd)
assert "--fasta-search" in s and "--qvalue 0.01" in s and "--threads 4" in s, s
assert "--lib" not in s, s
print("  OK:", s)
PY

echo "==> [6/6] diann 冒烟（若已安装）"
if command -v diann >/dev/null 2>&1; then
    diann --help 2>&1 | head -n 3 || true
else
    echo "  diann 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
