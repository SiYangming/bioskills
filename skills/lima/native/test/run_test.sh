#!/usr/bin/env bash
# lima native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - lima 二进制【可选】：若已安装（conda activate lima-native / PATH 中有 lima），
#     会对合成最小 BAM 真实执行 lima（空 BAM 无 ZMW，lima 可能报错退出——链路已验证即可）；
#     否则退化为「python 构造 argv 验证命令构建不崩溃」。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小 BAM + primers.fasta）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/reads.bam"
grep -q "NEB_5p" "$WORK/primers.fasta"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：lima 默认参数"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LimaSkill
skill = LimaSkill()
skill._resolve_binary = lambda: "/opt/env/bin/lima"  # 不真实执行，仅验证构建
cmd = skill.build_command(
    "lima", reads="$WORK/reads.bam", primers="$WORK/primers.fasta",
    output="$WORK/out1/demux.bam", threads=4,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/lima"), s
assert "$WORK/reads.bam $WORK/primers.fasta $WORK/out1/demux.bam" in s, s
assert "-j 4" in s, s
print("  OK:", s)
PY

echo "==> [4/5] argv 构造验证 #2：lima --isoseq + 自动输出扩展名"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LimaSkill, build_parser
skill = LimaSkill()
skill._resolve_binary = lambda: "lima"
cmd = skill.build_command(
    "lima", reads="$WORK/reads.bam", primers="$WORK/primers.fasta",
    outdir="$WORK/out2", prefix="demux", isoseq=True, peek_guess=True, threads=2,
)
s = " ".join(cmd)
assert "$WORK/out2/demux.bam" in s, s          # 输入 .bam -> 输出 .bam
assert "--isoseq" in s and "--peek-guess" in s, s
assert "-j 2" in s, s
ns = build_parser().parse_args(
    ["lima", "--reads", "$WORK/reads.bam", "--primers", "$WORK/primers.fasta",
     "--outdir", "$WORK/out3", "--isoseq", "--threads", "2", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "lima" and ns.isoseq is True and ns.threads == 2, ns
print("  OK:", s)
PY

echo "==> [5/5] lima 版本冒烟（若已安装）"
if command -v lima >/dev/null 2>&1; then
    # 注意：macOS 上 `lima` 可能误命中 limactl（Lima VM 管理器）而非 PacBio lima；
    # 合成最小 BAM 无 ZMW，真实执行无生物学意义，此处仅做版本探测。
    ver="$(lima --version 2>/dev/null | head -n 1 || true)"
    echo "  检测到 lima: ${ver:-（无法读取版本）}"
else
    echo "  lima 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
