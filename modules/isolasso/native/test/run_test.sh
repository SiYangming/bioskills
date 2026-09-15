#!/usr/bin/env bash
# isolasso native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - runlasso.py / processsam / isolasso 二进制【可选】：若已安装（编译后 bin/ 在 PATH 中），
#     会额外做存在性探测；否则跳过真实执行。
# 说明：IsoLasso 真实组装需 SAM/BAM + 二次规划求解，合成数据无法覆盖真实计算，
#      因此对 assemble/processsam/isolasso 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（最小 SAM / instance 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：assemble（runlasso.py，-o 前缀）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IsoLasssoSkill, build_parser
skill = IsoLasssoSkill()
skill._resolve_binary = lambda *a, **k: "/opt/env/bin/runlasso.py"
cmd = skill.build_command("assemble", input="$WORK/alignments.sam", output_prefix="sample")
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/runlasso.py"), s
assert "-o sample" in s, s
assert s.endswith("$WORK/alignments.sam"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["assemble", "$WORK/alignments.sam", "-o", "sample", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser assemble")
PY

echo "==> [4/6] argv 构造验证 #2：processsam"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IsoLasssoSkill
skill = IsoLasssoSkill()
skill._resolve_binary = lambda *a, **k: "processsam"
cmd = skill.build_command("processsam", input="$WORK/alignments.sam", output_prefix="sample")
s = " ".join(cmd)
assert s.startswith("processsam"), s
assert "-o sample" in s and s.endswith("$WORK/alignments.sam"), s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：isolasso（instance -> .pred）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IsoLasssoSkill
skill = IsoLasssoSkill()
skill._resolve_binary = lambda *a, **k: "isolasso"
cmd = skill.build_command("isolasso", input="$WORK/sample.instance")
s = " ".join(cmd)
assert s == "isolasso $WORK/sample.instance", s
print("  OK:", s)
# 缺 input 应报错
try:
    skill.build_command("isolasso")
    raise SystemExit("  [FAIL] isolasso 缺 input 未报错")
except ValueError:
    print("  OK: isolasso 缺 input 正确报错")
PY

echo "==> [6/6] isolasso 二进制存在性冒烟（若已安装）"
if command -v runlasso.py >/dev/null 2>&1; then
    echo "  已安装：$(command -v runlasso.py)"
else
    echo "  IsoLasso 未安装（未编译），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
