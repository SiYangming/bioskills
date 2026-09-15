#!/usr/bin/env bash
# masurca native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - masurca 二进制【可选】：若已安装（conda activate / PATH 中有），会额外做 masurca --version 冒烟；
#     否则跳过真实执行。
# 说明：MaSuRCA 组装需要真实 Illumina/PacBio 数据且耗时极长，合成数据无法覆盖真实计算，因此对
#      config/simple/run 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（config.txt + 占位 reads + assemble.sh）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/config.txt"
grep -q '^DATA' "$WORK/config.txt"
grep -q '^PARAMETERS' "$WORK/config.txt"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：config（生成 assemble.sh）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MasurcaSkill, build_parser
skill = MasurcaSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/masurca"
cmd = skill.build_command("config", config="$WORK/config.txt")
s = " ".join(cmd)
assert s == "/opt/env/bin/masurca $WORK/config.txt", s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["config", "$WORK/config.txt", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "config" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.config == "$WORK/config.txt", ns
print("  OK: parser config")
PY

echo "==> [4/6] argv 构造验证 #2：simple / run"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MasurcaSkill
skill = MasurcaSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/masurca"

cmd = skill.build_command("simple",
                          pe_reads="$WORK/illumina.1.fastq,$WORK/illumina.2.fastq",
                          long_reads="$WORK/subreads.fasta", threads=32)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/masurca -t 32 -i "), s
assert "$WORK/illumina.1.fastq,$WORK/illumina.2.fastq" in s, s
assert "-r $WORK/subreads.fasta" in s, s
print("  OK:", s)

# 纯二代（无长读）
cmd = skill.build_command("simple",
                          pe_reads="$WORK/illumina.1.fastq,$WORK/illumina.2.fastq", threads=16)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/masurca -t 16 -i ") and "-r" not in s, s
print("  OK:", s)

# run：执行 assemble.sh（不需要 masurca 二进制）
cmd = skill.build_command("run", script="$WORK/assemble.sh")
s = " ".join(cmd)
assert s == "bash $WORK/assemble.sh", s
print("  OK:", s)
PY

echo "==> [5/6] 必填参数缺失应报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MasurcaSkill
skill = MasurcaSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/masurca"
for bad in (
    lambda: skill.build_command("config"),
    lambda: skill.build_command("simple"),
):
    try:
        bad()
    except ValueError:
        pass
    else:
        raise AssertionError("缺少必填参数时应抛 ValueError")
print("  OK: 必填参数校验生效")
PY

echo "==> [6/6] masurca 冒烟（若已安装）"
if command -v masurca >/dev/null 2>&1; then
    masurca --version 2>&1 | head -n 1 || masurca -h 2>&1 | head -n 1
else
    echo "  masurca 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
