#!/usr/bin/env bash
# fasttree native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - FastTree【可选】：已安装（conda activate fasttree-native / PATH 中有 FastTree）时额外做
#     一次真实极小规模建树；否则退化为「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（蛋白/核酸小比对）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^protein' "$WORK/commands.txt"
grep -q '^nucleotide' "$WORK/commands.txt"
grep -q '^boot' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：protein（默认 JTT+CAT）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FasttreeSkill, build_parser
skill = FasttreeSkill()
skill._resolve_binary = lambda: "/opt/env/bin/FastTree"
cmd = skill.build_command("protein", input="$WORK/aln.prot.fasta", output="$WORK/tree.nwk")
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/FastTree"), s
assert "-out $WORK/tree.nwk" in s, s
assert "-nt" not in s, s                       # 蛋白模式不加 -nt
assert s.endswith("$WORK/aln.prot.fasta"), s    # 比对文件在最后（FastTree 要求选项在前）
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["protein", "$WORK/aln.prot.fasta", "-out", "$WORK/t.nwk",
     "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "protein" and ns.threads == 1 and ns.tmpdir == "/tmp", ns
print("  OK: parser protein")
PY

echo "==> [4/6] argv 构造验证 #2：nucleotide（-nt / -gtr）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FasttreeSkill
skill = FasttreeSkill()
skill._resolve_binary = lambda: "FastTree"
cmd = skill.build_command("nucleotide", input="$WORK/aln.nucl.fasta", output="$WORK/nt.nwk", gtr=True)
s = " ".join(cmd)
assert s.startswith("FastTree -nt -gtr"), s
assert "-out $WORK/nt.nwk" in s, s
assert s.endswith("$WORK/aln.nucl.fasta"), s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：boot（局部支持度 -boot）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FasttreeSkill
skill = FasttreeSkill()
skill._resolve_binary = lambda: "FastTree"
cmd = skill.build_command("boot", input="$WORK/aln.prot.fasta", bootstrap=1000, output="$WORK/boot.nwk")
s = " ".join(cmd)
assert "-boot 1000" in s, s
assert "-out $WORK/boot.nwk" in s, s
assert s.endswith("$WORK/aln.prot.fasta"), s
print("  OK:", s)
PY

echo "==> [6/6] FastTree 真实冒烟（若已安装）"
if command -v FastTree >/dev/null 2>&1; then
    FastTree -help 2>&1 | head -n 1
    python "$NATIVE/main.py" protein "$WORK/aln.prot.fasta" -out "$WORK/real.nwk"
    test -s "$WORK/real.nwk"
    grep -q '(' "$WORK/real.nwk"
    # 二次运行同一命令（幂等重建）
    python "$NATIVE/main.py" protein "$WORK/aln.prot.fasta" -out "$WORK/real2.nwk"
    test -s "$WORK/real2.nwk"
    echo "  OK: FastTree 真实建树产物校验通过"
else
    echo "  FastTree 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
