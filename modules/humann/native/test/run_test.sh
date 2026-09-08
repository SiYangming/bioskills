#!/usr/bin/env bash
# humann native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - humann【可选】：若本机已安装 humann（conda env / pip / PATH），
#     会额外做 humann --version 冒烟 + 辅助脚本存在性检查；否则跳过真实执行。
# 说明：humann run 需要联网下载 ChocoPhlAn / UniRef / MetaPhlAn 数据库，合成数据无法
#      覆盖真实计算；因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃」
#      的断言方式（等价于真实 run 的前置 argv 校验）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证 #1：run（直驱 humann 主流程）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import HumannSkill, build_parser
skill = HumannSkill()
skill._resolve_binary = lambda: "/opt/humann/bin/humann"
cmd = skill.build_command(
    "run", input="$WORK/reads.fastq", output="$WORK/out",
    threads=8, bypass_prescreen=True, input_format="fastq",
    memory_use="normal", verbose=True,
)
s = " ".join(cmd)
assert s.startswith("/opt/humann/bin/humann"), s
assert "--input $WORK/reads.fastq" in s and "--output $WORK/out" in s, s
assert "--threads 8" in s, s
assert "--bypass-prescreen" in s, s
assert "--input-format fastq" in s and "--memory-use normal" in s, s
print("  OK:", s)
# 缺必填 input 应报错
try:
    skill.build_command("run", output="$WORK/out", threads=4)
    raise SystemExit("run 缺 input 未抛错")
except ValueError as exc:
    print("  OK: run 缺 input 抛错 ->", exc)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "--input", "$WORK/reads.fastq", "--output", "$WORK/out",
     "--bypass-prescreen", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.bypass_prescreen is True, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser run")
PY

echo "==> [4/7] argv 构造验证 #2：renorm + regroup"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import HumannSkill
skill = HumannSkill()
skill._resolve_tool_binary = lambda sub: f"/opt/humann/bin/{sub}"
cmd = skill.build_command(
    "renorm", input="$WORK/sample1_genefamilies.tsv",
    output="$WORK/sample1_cpm.tsv", units="cpm", threads=2,
)
s = " ".join(cmd)
assert s.startswith("/opt/humann/bin/renorm"), s
assert "--units cpm" in s and "--output $WORK/sample1_cpm.tsv" in s, s
print("  OK:", s)
cmd = skill.build_command(
    "regroup", input="$WORK/sample1_genefamilies.tsv",
    output="$WORK/sample1_ec.tsv", groups="ec",
)
s = " ".join(cmd)
assert s.startswith("/opt/humann/bin/regroup"), s
assert "--groups ec" in s, s
print("  OK:", s)
# regroup 缺 groups/custom 应报错
try:
    skill.build_command("regroup", input="$WORK/sample1_genefamilies.tsv", output="$WORK/x.tsv")
    raise SystemExit("regroup 缺 groups/custom 未抛错")
except ValueError as exc:
    print("  OK: regroup 缺 groups/custom 抛错 ->", exc)
PY

echo "==> [5/7] argv 构造验证 #3：join + databases"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import HumannSkill
skill = HumannSkill()
skill._resolve_tool_binary = lambda sub: f"/opt/humann/bin/{sub}"
cmd = skill.build_command(
    "join", input="$WORK", output="$WORK/all_genefamilies.tsv",
    file_name="genefamilies.tsv", threads=2,
)
s = " ".join(cmd)
assert s.startswith("/opt/humann/bin/join"), s
assert "--input $WORK" in s, s
assert "--file_name genefamilies.tsv" in s, s
print("  OK:", s)
cmd = skill.build_command(
    "databases", database="chocophlan", build="full", location="$WORK/dbs",
)
s = " ".join(cmd)
assert s.startswith("/opt/humann/bin/databases"), s
assert "--download chocophlan full $WORK/dbs" in s, s
print("  OK:", s)
cmd = skill.build_command("databases", available=True)
s = " ".join(cmd)
assert s == "/opt/humann/bin/databases --available", s
print("  OK:", s)
PY

echo "==> [6/7] parser 覆盖：join 子命令后 --threads/--tmpdir"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
ns = build_parser().parse_args(
    ["join", "--input", "$WORK", "--output", "$WORK/all.tsv",
     "--threads", "8", "--tmpdir", "/tmp/foo"]
)
assert ns.subcommand == "join" and ns.threads == 8 and ns.tmpdir == "/tmp/foo", ns
print("  OK: parser join")
PY

echo "==> [7/7] humann 冒烟（若已安装）"
if command -v humann >/dev/null 2>&1; then
    humann --version | head -n 1
    for t in humann_renorm_table humann_join_tables humann_regroup_table humann_databases; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "  辅助脚本可用: $t"
        else
            echo "  警告：辅助脚本 $t 不在 PATH（部分安装方式不提供）"
        fi
    done
else
    echo "  humann 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README / bash native/install.sh）"
fi

echo "ALL TESTS PASSED"
