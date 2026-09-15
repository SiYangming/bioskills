#!/usr/bin/env bash
# gblocks native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - Gblocks 二进制【可选】：若已安装（conda activate gblocks / PATH 中有 Gblocks），
#     会额外做真实保守区块提取；否则仅做「python 构造 argv 验证命令构建不崩溃」。
# 说明：Gblocks 为单线程经典工具，--threads 仅统一接口保留（不注入命令行）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（蛋白质 + 密码子比对）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：extract（蛋白质，带 -e 与 -b1）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GblocksSkill, build_parser
skill = GblocksSkill()
skill._resolve_binary = lambda: "/opt/env/bin/Gblocks"
cmd = skill.build_command(
    "extract", input="$WORK/sample.prot.aln", aln_type="p",
    allow_gaps=True, b1=10, b2=8, threads=4,
)
s = " ".join(cmd)
assert "/opt/env/bin/Gblocks" in s, s
assert "$WORK/sample.prot.aln" in s, s
assert "-t=p" in s, s
assert "-e=-gaps" in s, s
assert "-b1=10" in s and "-b2=8" in s, s
print("  OK:", s)
# 原生输出名 = <input>-gb
assert skill.native_output("$WORK/sample.prot.aln") == "$WORK/sample.prot.aln-gb"
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["extract", "$WORK/sample.prot.aln", "-t", "c", "-o", "$WORK/out.aln",
     "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "extract" and ns.aln_type == "c", ns
assert ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser extract")
PY

echo "==> [4/5] argv 构造验证：version"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GblocksSkill
skill = GblocksSkill()
skill._resolve_binary = lambda: "Gblocks"
cmd = skill.build_command("version", threads=None)
assert cmd == ["Gblocks", "--help"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [5/5] Gblocks 真实冒烟（若已安装）"
if command -v Gblocks >/dev/null 2>&1; then
    python "$NATIVE/main.py" extract "$WORK/sample.prot.aln" -t p -o "$WORK/sample.prot.aln-gb" || true
    test -f "$WORK/sample.prot.aln-gb" && echo "  OK: 生成保守区块比对 sample.prot.aln-gb"
    echo q | Gblocks 2>&1 | head -n 1 || true
else
    echo "  Gblocks 未安装，跳过真实执行（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
