#!/usr/bin/env bash
# pbccs native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ccs 二进制【可选】：若已安装（conda activate pbccs-native / PATH 中有 ccs），
#     会额外做 ccs --version 冒烟；否则跳过真实执行。
# 说明：ccs 需要真实 PacBio subreads BAM 才能产出结果，合成数据无法覆盖真实计算，
#      因此本脚本对 ccs 子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（subreads 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：ccs chunk 1/2（默认阈值）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PbccsSkill
skill = PbccsSkill()
skill._resolve_binary = lambda: "/opt/env/bin/ccs"  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "ccs", subreads="$WORK/subreads.bam", outdir="$WORK/out1",
    chunk_num=1, chunk_total=2, threads=4,
)
s = " ".join(cmd)
assert "/opt/env/bin/ccs" in s, s
assert "--chunk 1/2" in s, s
assert "-j 4" in s, s
assert "--report-file" in s and "--report-json" in s and "--metrics-json" in s, s
# 默认阈值不注入（用户未显式给出）
assert "--min-rq" not in s, s
print("  OK:", s)
PY

echo "==> [4/5] argv 构造验证 #2：ccs chunk 2/2（显式阈值 / 自定义输出）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import PbccsSkill, build_parser
skill = PbccsSkill()
skill._resolve_binary = lambda: "ccs"
cmd = skill.build_command(
    "ccs", subreads="$WORK/subreads.bam", output="$WORK/out2/custom.bam",
    chunk_num=2, chunk_total=2, min_rq=0.95, min_passes=5, top_passes=80, threads=2,
)
s = " ".join(cmd)
assert "--chunk 2/2" in s, s
assert "--min-rq 0.95" in s, s
assert "--min-passes 5" in s, s
assert "--top-passes 80" in s, s
assert "-j 2" in s, s
assert "$WORK/out2/custom.bam" in s, s
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["ccs", "--subreads", "$WORK/subreads.bam", "--outdir", "$WORK/out3",
     "--chunk-num", "2", "--chunk-total", "2", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "ccs" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK:", s)
PY

echo "==> [5/5] ccs 冒烟（若已安装）"
if command -v ccs >/dev/null 2>&1; then
    ccs --version | head -n 1
else
    echo "  ccs 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
