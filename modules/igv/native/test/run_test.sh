#!/usr/bin/env bash
# igv native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - igv.sh【可选】且需 Java + DISPLAY：若已安装且存在显示环境，会额外冒烟；
#     否则仅做 argv 构造验证（GUI 工具在无显示环境无法真实启动）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（.genome + BED 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：launch（genome/locus/多文件）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IgvSkill, build_parser
skill = IgvSkill()
skill._resolve_binary = lambda: "/opt/igv/IGV_Linux_2.5.3/igv.sh"
cmd = skill.build_command(
    "launch", genome="hg18", locus="chr1:1000-2000",
    files=["$WORK/sample.bed", "$WORK/sample.vcf"],
)
s = " ".join(cmd)
assert s == "/opt/igv/IGV_Linux_2.5.3/igv.sh --genome hg18 --locus chr1:1000-2000 $WORK/sample.bed $WORK/sample.vcf", s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["launch", "--genome", "hg18", "--locus", "chr1:1-9", "$WORK/sample.bed", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "launch" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.files == ["$WORK/sample.bed"], ns
print("  OK: parser launch")
PY

echo "==> [4/5] argv 构造验证 #2：batch（--batch 必填）与线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IgvSkill
skill = IgvSkill()
skill._resolve_binary = lambda: "igv.sh"
c = skill.build_command("batch", batch="$WORK/snapshot.txt", genome="$WORK/hg18.genome", files="$WORK/sample.bed")
s = " ".join(c)
assert s == "igv.sh --genome $WORK/hg18.genome --batch $WORK/snapshot.txt $WORK/sample.bed", s
print("  OK batch:", s)

try:
    skill.build_command("batch", genome="hg18")
except ValueError as e:
    print("  OK batch 缺 --batch 报错:", e)
else:
    raise AssertionError("batch 缺 --batch 应抛 ValueError")

# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("launch", 8) == 8
assert skill._effective_threads("batch", None) == 2   # meta per_subcommand_threads.batch=2
print("  OK threads priority")
PY

echo "==> [5/5] igv 冒烟（若已安装且可用显示）"
if command -v igv.sh >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    echo "  igv.sh 已安装且 DISPLAY=${DISPLAY}（真实 GUI 需人工交互，跳过自动冒烟）"
else
    echo "  igv.sh 未安装或无 DISPLAY，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
