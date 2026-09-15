#!/usr/bin/env bash
# star-fusion native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - STAR-Fusion 二进制【可选】：若已安装（conda activate <env> / PATH 中有 STAR-Fusion），
#     会额外做 STAR-Fusion --version 冒烟；否则跳过真实执行。
# 说明：STAR-Fusion 需 CTAT 资源库与真实 reads 才能产出结果，统一采用「python 构造 argv 验证
#       命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（CTAT 资源库目录 + 双端/单端 FASTQ 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q '^detect' "$WORK/commands.txt"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：detect 双端（文档 12.3 示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StarFusionSkill, build_parser
skill = StarFusionSkill()
skill._resolve_binary = lambda: "/opt/env/bin/STAR-Fusion"
cmd = skill.build_command(
    "detect", genome_lib_dir="$WORK/CTAT_resource_lib",
    left_fq="$WORK/reads_1.fastq.gz", right_fq="$WORK/reads_2.fastq.gz",
    output_dir="$WORK/out", threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/STAR-Fusion", s
assert "--genome_lib_dir $WORK/CTAT_resource_lib" in s, s
assert "--left_fq $WORK/reads_1.fastq.gz" in s, s
assert "--right_fq $WORK/reads_2.fastq.gz" in s, s
assert "--output_dir $WORK/out" in s, s
assert "--CPU 8" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["detect", "--genome_lib_dir", "$WORK/CTAT_resource_lib",
     "--left_fq", "$WORK/reads_1.fastq.gz", "--right_fq", "$WORK/reads_2.fastq.gz",
     "--output_dir", "$WORK/out", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "detect" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.genome_lib_dir == "$WORK/CTAT_resource_lib", ns
print("  OK: parser detect (PE)")
PY

echo "==> [4/5] argv 构造验证 #2：单端（无 --right_fq）+ 必填校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StarFusionSkill
skill = StarFusionSkill()
skill._resolve_binary = lambda: "STAR-Fusion"
cmd = skill.build_command(
    "detect", genome_lib_dir="$WORK/CTAT_resource_lib",
    left_fq="$WORK/single.fastq.gz", output_dir="$WORK/out", threads=4,
)
s = " ".join(cmd)
assert "--right_fq" not in s, s
assert "--left_fq $WORK/single.fastq.gz" in s, s
assert "--CPU 4" in s, s
print("  OK:", s)

for kw in (dict(left_fq="$WORK/reads_1.fastq.gz", output_dir="$WORK/o"),
           dict(genome_lib_dir="$WORK/CTAT_resource_lib", output_dir="$WORK/o"),
           dict(genome_lib_dir="$WORK/CTAT_resource_lib", left_fq="$WORK/reads_1.fastq.gz")):
    try:
        skill.build_command("detect", **kw)
        raise SystemExit("detect 缺必填参数时应报错")
    except ValueError as e:
        print("  OK: detect 必填校验 ->", e)
PY

echo "==> [5/5] STAR-Fusion 冒烟（若已安装）"
if command -v STAR-Fusion >/dev/null 2>&1; then
    STAR-Fusion --version 2>&1 | head -n 2
else
    echo "  STAR-Fusion 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
