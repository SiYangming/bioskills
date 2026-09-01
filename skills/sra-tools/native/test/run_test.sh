#!/usr/bin/env bash
# sra-tools native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - sra-tools 二进制【可选】：若已安装（conda activate sra-tools-native / PATH 中有 prefetch），
#     会额外做 prefetch --version 冒烟；否则跳过真实执行。
# 说明：prefetch/fasterq-dump/fastq-dump 需要真实 SRA 文件 + NCBI 网络，合成数据无法覆盖
#      真实下载/转换，因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"
# 产物：$WORK/SRR_Acc_List.txt $WORK/sra/SRR12345678/SRR12345678.sra

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：prefetch（nanoseq 默认 -f yes -t http）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SraToolsSkill, build_parser
skill = SraToolsSkill()
skill._resolve_subcommand_bin = lambda sc: "/opt/env/bin/prefetch"
cmd = skill.build_command(
    "prefetch", srr_id="SRR12345678", output_dir="$WORK/sra",
    prefetch_options="-f yes -t http", threads=2,
)
s = " ".join(cmd)
assert "/opt/env/bin/prefetch" in s, s
assert "-f yes -t http" in s, s
assert "-O $WORK/sra" in s, s
assert "SRR12345678" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["prefetch", "SRR12345678", "-O", "$WORK/sra", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "prefetch" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser prefetch")
PY

echo "==> [4/6] argv 构造验证 #2：fasterq-dump（-e 线程 / -t 临时目录）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SraToolsSkill
skill = SraToolsSkill()
skill._resolve_subcommand_bin = lambda sc: "/opt/env/bin/fasterq-dump"
cmd = skill.build_command(
    "fasterq-dump", sra_file="$WORK/sra/SRR12345678/SRR12345678.sra",
    output_dir="$WORK/fastq", threads=8,
)
s = " ".join(cmd)
assert "/opt/env/bin/fasterq-dump" in s, s
assert "$WORK/sra/SRR12345678/SRR12345678.sra" in s, s
assert "--split-3" in s and "--gzip" in s, s
assert "-O $WORK/fastq" in s, s
assert "-e 8" in s, s
assert "-t /tmp" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：fastq-dump（nanoseq 脚本原用法）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SraToolsSkill
skill = SraToolsSkill()
skill._resolve_subcommand_bin = lambda sc: "/opt/env/bin/fastq-dump"
cmd = skill.build_command(
    "fastq-dump", sra_file="$WORK/sra/SRR12345678/SRR12345678.sra",
    output_dir="$WORK/fastq", split_3=True, gzip=True,
)
s = " ".join(cmd)
assert "/opt/env/bin/fastq-dump" in s, s
assert "--split-3" in s and "--gzip" in s, s
assert "-O $WORK/fastq" in s, s
assert "$WORK/sra/SRR12345678/SRR12345678.sra" in s, s
print("  OK:", s)
PY

echo "==> [6/6] sra-tools 冒烟（若已安装）"
if command -v prefetch >/dev/null 2>&1; then
    prefetch --version | head -n 1
else
    echo "  sra-tools 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
