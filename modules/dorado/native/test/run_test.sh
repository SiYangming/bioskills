#!/usr/bin/env bash
# dorado native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - dorado 二进制【可选】：若已安装（官方二进制 / PATH 中有 dorado），
#     会额外做 dorado --version 冒烟；否则跳过真实执行。
# 说明：dorado basecaller 需要真实 POD5/FAST5 信号 + 模型，合成数据无法覆盖真实计算，
#      因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：basecall（nanoseq 默认 RNA 模型 + --emit-fastq）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DoradoSkill, build_parser
skill = DoradoSkill()
skill._resolve_binary = lambda: "/opt/dorado/bin/dorado"
cmd = skill.build_command(
    "basecall", model="rna004_130bps_sup@v5.1.0", reads="$WORK/pod5",
    output="$WORK/out", emit_fastq=True, threads=8,
)
s = " ".join(cmd)
assert "/opt/dorado/bin/dorado basecaller" in s, s
assert "rna004_130bps_sup@v5.1.0" in s and "$WORK/pod5" in s, s
assert "--emit-fastq" in s, s
assert "--output-dir $WORK/out" in s, s
assert "--num-workers 8" in s, s
print("  OK:", s)
# 默认模型：未显式给出 model 时使用 nanoseq config 的 rna004_130bps_sup@v5.1.0
cmd2 = skill.build_command("basecall", reads="$WORK/pod5", threads=4)
s2 = " ".join(cmd2)
assert "rna004_130bps_sup@v5.1.0" in s2, s2
print("  OK:", s2)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["basecall", "rna004_130bps_sup@v5.1.0", "$WORK/pod5",
     "--output-dir", "$WORK/out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "basecall" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser basecall")
PY

echo "==> [4/5] argv 构造验证 #2：demux"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DoradoSkill
skill = DoradoSkill()
skill._resolve_binary = lambda: "dorado"
cmd = skill.build_command(
    "demux", reads="$WORK/reads.fastq", kit_name="SQK-RNA004-24",
    output="$WORK/demux_out", threads=4,
)
s = " ".join(cmd)
assert "dorado demux" in s, s
assert "$WORK/reads.fastq" in s, s
assert "--kit-name SQK-RNA004-24" in s, s
assert "--output-dir $WORK/demux_out" in s, s
print("  OK:", s)
PY

echo "==> [5/5] dorado 冒烟（若已安装）"
if command -v dorado >/dev/null 2>&1; then
    dorado --version | head -n 1
else
    echo "  dorado 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
