#!/usr/bin/env bash
# fusionmap native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - FusionMap / FusionMap.exe 二进制【可选】：商业/许可受限，需从官方下载页获取；若已部署
#     （native/install.sh 或 native/Dockerfile / Apptainer.def），会额外做可执行文件冒烟；否则跳过。
# 说明：FusionMap 需官方参考数据与真实 FASTQ 才能产出结果，统一采用「python 构造 argv 验证
#      命令构建不崩溃」的断言方式（含 Linux 直接可执行 / Windows .exe→mono 两种形态）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTQ + Ref 目录占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q '^detect' "$WORK/commands.txt"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：detect（Linux 直接可执行，文档 12.1 示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FusionMapSkill, build_parser
skill = FusionMapSkill()
skill._resolve_binary = lambda: "/opt/fusionmap/FusionMap"
cmd = skill.build_command(
    "detect", input=["$WORK/reads_1.fastq", "$WORK/reads_2.fastq"],
    ref="$WORK/Ref", output="$WORK/out", fusion="DetectFusion", threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/fusionmap/FusionMap", s
assert "mono" not in cmd, s
assert "--fusion DetectFusion" in s, s
assert "--input $WORK/reads_1.fastq $WORK/reads_2.fastq" in s, s
assert "--ref $WORK/Ref" in s and "--output $WORK/out" in s, s
assert "--thread 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["detect", "--input", "$WORK/single.fastq", "--ref", "$WORK/Ref",
     "--output", "$WORK/out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "detect" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.input == ["$WORK/single.fastq"], ns
print("  OK: parser detect (SE)")
PY

echo "==> [4/5] argv 构造验证 #2：Windows .exe → mono 前缀 + 必填校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FusionMapSkill
skill = FusionMapSkill()
skill._resolve_binary = lambda: "/opt/fusionmap/FusionMap.exe"
cmd = skill.build_command(
    "detect", input="$WORK/single.fastq", ref="$WORK/Ref",
    output="$WORK/out", threads=4,
)
s = " ".join(cmd)
assert cmd[0] == "mono" and cmd[1] == "/opt/fusionmap/FusionMap.exe", s
assert "--fusion DetectFusion" in s, s  # 默认模式
assert "--thread 4" in s, s
print("  OK:", s)

# 必填校验
for kw in (dict(ref="$WORK/Ref", output="$WORK/out"),
           dict(input="$WORK/single.fastq", output="$WORK/out"),
           dict(input="$WORK/single.fastq", ref="$WORK/Ref")):
    try:
        skill.build_command("detect", **kw)
        raise SystemExit("detect 缺必填参数时应报错")
    except ValueError as e:
        print("  OK: detect 必填校验 ->", e)
PY

echo "==> [5/5] FusionMap 冒烟（若已部署）"
if command -v FusionMap >/dev/null 2>&1; then
    echo "  找到 FusionMap: $(command -v FusionMap)"
elif command -v FusionMap.exe >/dev/null 2>&1; then
    echo "  找到 FusionMap.exe（需 mono 运行）: $(command -v FusionMap.exe)"
else
    echo "  FusionMap 未部署（商业/许可受限，需从官方下载页获取），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
