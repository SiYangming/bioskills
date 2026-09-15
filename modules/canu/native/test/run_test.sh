#!/usr/bin/env bash
# canu native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - canu 二进制【可选】：若已安装（conda activate / PATH 中有），会额外做 canu --version 冒烟；
#     否则跳过真实执行。
# 说明：canu 完整组装需要真实长读数据且耗时极长，合成数据无法覆盖真实计算，
#      因此对 assemble/correct/trim 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成占位长读）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/subreads.fasta"
grep -q '^>' "$WORK/subreads.fasta"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：assemble（文档 lambda 示例）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CanuSkill, build_parser
skill = CanuSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/canu"
cmd = skill.build_command(
    "assemble", reads="$WORK/subreads.fasta", prefix="out",
    genome_size="58000", use_grid=False, threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/canu -p out"), s
assert "genomeSize=58000" in s, s
assert "useGrid=false" in s and "maxThreads=8" in s, s
assert s.rstrip().endswith("-pacbio-raw $WORK/subreads.fasta"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["assemble", "$WORK/subreads.fasta", "-p", "out", "--genome-size", "8m",
     "--data-type", "nanopore-raw", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.prefix == "out" and ns.genome_size == "8m" and ns.data_type == "nanopore-raw", ns
print("  OK: parser assemble")
PY

echo "==> [4/6] argv 构造验证 #2：correct / trim 阶段标志"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CanuSkill
skill = CanuSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/canu"

cmd = skill.build_command("correct", reads="$WORK/subreads.fasta", prefix="out",
                          directory="$WORK/canu_out", genome_size="8m",
                          data_type="nanopore-raw", threads=8)
s = " ".join(cmd)
assert "-d $WORK/canu_out" in s, s
assert "genomeSize=8m" in s and "maxThreads=8" in s, s
assert "-correct" in s and "-nanopore-raw" in s, s
assert "-trim" not in s, s
print("  OK:", s)

cmd = skill.build_command("trim", reads="$WORK/subreads.fasta", prefix="out",
                          genome_size="8m", threads=4)
s = " ".join(cmd)
assert "-trim" in s and "-correct" not in s, s
assert s.rstrip().endswith("-pacbio-raw $WORK/subreads.fasta"), s
print("  OK:", s)

# use_grid=True 时不注入 maxThreads，改为 useGrid=true
cmd = skill.build_command("assemble", reads="$WORK/subreads.fasta", prefix="out",
                          genome_size="8m", use_grid=True, threads=8)
s = " ".join(cmd)
assert "useGrid=true" in s and "maxThreads" not in s, s
print("  OK:", s)
PY

echo "==> [5/6] 必填参数与非法值应报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CanuSkill
skill = CanuSkill()
skill._resolve_binary = lambda name=None, **kw: "/opt/env/bin/canu"
for bad in (
    lambda: skill.build_command("assemble", reads="$WORK/subreads.fasta", prefix="out"),
    lambda: skill.build_command("assemble", reads="$WORK/subreads.fasta", genome_size="8m"),
    lambda: skill.build_command("assemble", prefix="out", genome_size="8m"),
    lambda: skill.build_command("assemble", reads="$WORK/subreads.fasta",
                                prefix="out", genome_size="8m", data_type="bogus"),
):
    try:
        bad()
    except ValueError:
        pass
    else:
        raise AssertionError("缺少必填参数/非法 data_type 时应抛 ValueError")
print("  OK: 参数校验生效")
PY

echo "==> [6/6] canu 冒烟（若已安装）"
if command -v canu >/dev/null 2>&1; then
    canu --version | head -n 1
else
    echo "  canu 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
