#!/usr/bin/env bash
# prottest native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - java【可选】：ProtTest3 模型选择计算量极大（约 1472 分钟），本测试不做真实计算；
#     对 run/hpc 采用「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch 二进制/jar 解析）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（蛋白比对 + 起始树占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^run' "$WORK/commands.txt"
grep -q '^hpc' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run（序列版模型选择）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ProttestSkill, build_parser
skill = ProttestSkill()
skill._resolve_binary = lambda: "/opt/jdk/bin/java"
skill._resolve_jar = lambda: "/opt/prottest-3.4.2/prottest-3.4.2.jar"
cmd = skill.build_command(
    "run", input="$WORK/aln.phy", tree="$WORK/tree.nwk",
    output="$WORK/prottest.out", tc=0.5, threads=4,
)
s = " ".join(cmd)
assert "/opt/jdk/bin/java" in s, s
assert "-Xmx6g" in s, s                       # JAVA_OPTS 透传
assert "-jar /opt/prottest-3.4.2/prottest-3.4.2.jar" in s, s
assert "-i $WORK/aln.phy" in s, s
assert "-t $WORK/tree.nwk" in s, s
assert "-all-distributions" in s and "-F" in s and "-AIC" in s and "-BIC" in s, s
assert "-tc 0.5" in s, s
assert "-o $WORK/prottest.out" in s, s
assert "-threads 4" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "$WORK/aln.phy", "-t", "$WORK/tree.nwk", "-o", "$WORK/out",
     "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证 #2：hpc（MPJ 并行，runProtTestHPC.sh）"
mkdir -p "$WORK/fakehome"
touch "$WORK/fakehome/prottest-3.4.2.jar"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakehome/runProtTestHPC.sh"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import ProttestSkill
skill = ProttestSkill()
skill._resolve_binary = lambda: "java"
skill._resolve_jar = lambda: "$WORK/fakehome/prottest-3.4.2.jar"
cmd = skill.build_command(
    "hpc", input="$WORK/aln.phy", processes=4, tc=0.5, threads=4,
)
s = " ".join(cmd)
assert s.startswith("bash $WORK/fakehome/runProtTestHPC.sh 4"), s
assert "-i $WORK/aln.phy" in s, s
assert "-all-distributions" in s and "-F" in s and "-AIC" in s and "-BIC" in s, s
assert "-tc 0.5" in s, s
assert "-threads" not in s, s                 # hpc 用进程数，不注入 -threads
print("  OK:", s)
PY

echo "==> [5/5] java 冒烟（若已安装；不执行真实模型选择）"
if command -v java >/dev/null 2>&1; then
    java -version 2>&1 | head -n 1
else
    echo "  java 未安装，跳过（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
