#!/usr/bin/env bash
# gapcloser native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - GapCloser 二进制【可选】：若已安装（conda activate gapcloser / PATH 中有
#     GapCloser），会额外做 GapCloser help 冒烟；否则跳过真实执行。
# 说明：GapCloser 真正补洞需要真实配对 reads 比对，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在仓库内产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（迷你 scaffold + config + 占位 reads）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa" && test -s "$WORK/config.txt"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^fill'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（fill）+ --schema"

echo "==> [3/5] argv 构造验证：fill（GapCloser 默认参数 + 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GapcloserSkill, build_parser

skill = GapcloserSkill()
skill._resolve_binary = lambda: "/opt/env/bin/GapCloser"
cmd = skill.build_command(
    "fill", scaffold="$WORK/genome.fa", config="$WORK/config.txt",
    output="$WORK/gapcloser.fa", max_read_len=120, overlap=25, threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/GapCloser" in s, s
assert "-a $WORK/genome.fa" in s, s
assert "-b $WORK/config.txt" in s, s
assert "-o $WORK/gapcloser.fa" in s, s
assert "-l 120" in s and "-p 25" in s and "-t 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式；-a/--scaffold 别名）
ns = build_parser().parse_args(
    ["fill", "-a", "$WORK/genome.fa", "-b", "$WORK/config.txt",
     "-o", "$WORK/out.fa", "-l", "120", "-p", "31", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "fill" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.scaffold_opt == "$WORK/genome.fa" and ns.overlap == 31, ns
print("  OK: parser fill")
PY

echo "==> [4/5] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GapcloserSkill

skill = GapcloserSkill()
skill._resolve_binary = lambda: "GapCloser"

# 缺 scaffold
try:
    skill.build_command("fill", config="$WORK/config.txt")
    raise AssertionError("缺 scaffold 应抛 ValueError")
except ValueError:
    pass
# 缺 config
try:
    skill.build_command("fill", scaffold="$WORK/genome.fa")
    raise AssertionError("缺 config 应抛 ValueError")
except ValueError:
    pass
# 未知子命令
try:
    skill.build_command("close", scaffold="a.fa", config="c.txt")
    raise AssertionError("未知子命令应报错")
except ValueError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [5/5] GapCloser 冒烟（若已安装）"
if command -v GapCloser >/dev/null 2>&1; then
    GapCloser 2>&1 | grep -q "input scaffold file name" && echo "  OK: GapCloser 可执行（help 输出校验通过）"
else
    echo "  GapCloser 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
