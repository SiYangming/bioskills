#!/usr/bin/env bash
# fgenesh native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - fgenesh 二进制【可选且许可受限】：若已安装（用户自备 Softberry 授权发行包并加入 PATH），
#     会做 fgenesh 可执行冒烟；否则跳过真实执行。
# 说明：FGENESH 许可受限、需授权参数文件与真实基因组，合成数据无法覆盖真实预测，因此对
#      predict 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（合成 genome + params 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：predict（-L/-o/-gff 与 -cpu 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FgeneshSkill, build_parser
# 直接指定 -L
skill = FgeneshSkill()
skill._resolve_binary = lambda: "/opt/env/bin/fgenesh"
cmd = skill.build_command(
    "predict", genome="$WORK/genome.fa", params="$WORK/params/fungi.par",
    output="$WORK/fgenesh.out", gff=True, threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/fgenesh $WORK/genome.fa "), s
assert "-L $WORK/params/fungi.par" in s, s
assert "-o $WORK/fgenesh.out" in s and "-gff" in s, s
assert "-cpu 8" in s, s  # 线程注入
print("  OK:", s)
# --species + --params-dir 自动解析
cmd2 = skill.build_command(
    "predict", genome="$WORK/genome.fa", species="human",
    params_dir="$WORK/params", output="$WORK/out", gene_only=True,
)
s2 = " ".join(cmd2)
assert "-L $WORK/params/human.par" in s2, s2
assert "-gene" in s2 and "-cpu" in s2, s2
print("  OK:", s2)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/genome.fa", "-L", "$WORK/params/fungi.par",
     "-o", "$WORK/o", "-gff", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser predict")
PY

echo "==> [4/4] fgenesh 冒烟（若已安装且授权）"
if command -v fgenesh >/dev/null 2>&1; then
    fgenesh 2>&1 | head -n 3 || true
else
    echo "  fgenesh 未安装（许可受限，需用户自备 Softberry 授权发行包），跳过真实冒烟"
fi

echo "ALL TESTS PASSED"
