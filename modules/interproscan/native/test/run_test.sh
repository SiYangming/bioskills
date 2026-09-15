#!/usr/bin/env bash
# interproscan native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - interproscan.sh 二进制【可选】：若已安装（conda activate interproscan / PATH 中有 interproscan.sh），
#     会额外做 --version 冒烟；否则跳过真实执行。
# 说明：真实注释依赖发行包分析数据（数十 GB），合成数据无法覆盖，因此采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（蛋白 FASTA）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/proteins.fasta"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run（tsv,gff3,xml + goterms/iprlookup/pa）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import InterproscanSkill, build_parser
skill = InterproscanSkill()
skill._resolve_binary = lambda: "/opt/env/bin/interproscan.sh"
cmd = skill.build_command(
    "run", input="$WORK/proteins.fasta", output="$WORK/interpro_result",
    formats="tsv,gff3,xml", goterms=True, iprlookup=True, pathways=True,
    seqtype="p", threads=8, tmpdir_override="/tmp/ips_tmp",
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/interproscan.sh -i $WORK/proteins.fasta"), s
assert "-o $WORK/interpro_result" in s and "-f tsv,gff3,xml" in s, s
assert "-goterms" in s and "-iprlookup" in s and "-pa" in s, s
assert "-t p" in s and "-cpu 8" in s, s
assert "--tempdir /tmp/ips_tmp" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "-i", "$WORK/proteins.fasta", "-o", "out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证 #2：version + 关闭开关 + JAVA_OPTS 透传"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import InterproscanSkill
skill = InterproscanSkill()
skill._resolve_binary = lambda: "interproscan.sh"

# version 子命令
assert skill.build_command("version", threads=None) == ["interproscan.sh", "--version"]
print("  OK: interproscan.sh --version")

# 布尔关闭：--no-goterms / --no-iprlookup 后不应出现 -goterms/-iprlookup
c = " ".join(skill.build_command(
    "run", input="$WORK/proteins.fasta", goterms=False, iprlookup=False,
    disable_precalc=True, threads=4, tmpdir_override="/tmp",
))
assert "-goterms" not in c and "-iprlookup" not in c, c
assert "-dp" in c and "-cpu 4" in c, c
print("  OK:", c)

# Java 工具：env_vars 必须透传 JAVA_OPTS（-Xmx / -Djava.io.tmpdir）
assert "JAVA_OPTS" in skill.env_vars, skill.env_vars
assert "-Xmx" in skill.env_vars["JAVA_OPTS"], skill.env_vars
assert "-Djava.io.tmpdir" in skill.env_vars["JAVA_OPTS"], skill.env_vars
print("  OK: JAVA_OPTS =", skill.env_vars["JAVA_OPTS"])

# 缺参保护
try:
    skill.build_command("run", threads=4)
except ValueError as e:
    print("  OK: run 缺 -i 抛错 ->", e)
else:
    raise SystemExit("run 缺少 input 时应抛 ValueError")
PY

echo "==> [5/5] interproscan.sh 冒烟（若已安装）"
if command -v interproscan.sh >/dev/null 2>&1; then
    interproscan.sh --version 2>&1 | head -n 2
else
    echo "  interproscan.sh 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
