#!/usr/bin/env bash
# soapdenovo2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SOAPdenovo-63mer/127mer 二进制【可选】：若已安装（conda activate / PATH 中有），
#     会额外做版本冒烟；否则跳过真实执行。
# 说明：SOAPdenovo2 all 需要真实 Illumina reads + config.txt 才能建图，
#      合成数据无法覆盖真实计算，因此对 all/pregraph/contig/map/scaff 采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（config.txt + 占位 reads）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/config.txt"
grep -q '^\[LIB\]' "$WORK/config.txt"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：all（一步式组装，默认 63mer）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soapdenovo2Skill, build_parser
skill = Soapdenovo2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"
cmd = skill.build_command(
    "all", config="$WORK/config.txt", output="$WORK/out_K51/E_coli",
    kmer=51, threads=4, resolve_repeats=True,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-63mer all"), s
assert "-s $WORK/config.txt" in s, s
assert "-o $WORK/out_K51/E_coli" in s, s
assert "-K 51" in s and "-p 4" in s and s.rstrip().endswith("-R"), s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["all", "$WORK/config.txt", "-o", "$WORK/out_K51/E_coli",
     "-K", "51", "-R", "--threads", "8", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "all" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.config == "$WORK/config.txt" and ns.kmer == 51 and ns.resolve_repeats is True, ns
print("  OK: parser all")
PY

echo "==> [4/6] argv 构造验证 #2：pregraph / contig / map / scaff"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soapdenovo2Skill
skill = Soapdenovo2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"

cmd = skill.build_command("pregraph", config="$WORK/config.txt",
                          output="$WORK/out_K51/E_coli", kmer=51, threads=8,
                          resolve_repeats=True)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-63mer pregraph"), s
assert "-s $WORK/config.txt" in s and "-o $WORK/out_K51/E_coli" in s, s
assert "-K 51" in s and "-p 8" in s and s.rstrip().endswith("-R"), s
print("  OK:", s)

cmd = skill.build_command("contig", graph_prefix="$WORK/out_K51/E_coli", resolve_repeats=True)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-63mer contig"), s
assert "-g $WORK/out_K51/E_coli" in s and s.rstrip().endswith("-R"), s
print("  OK:", s)

cmd = skill.build_command("map", config="$WORK/config.txt", graph_prefix="$WORK/out_K51/E_coli")
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-63mer map"), s
assert "-s $WORK/config.txt" in s and "-g $WORK/out_K51/E_coli" in s, s
print("  OK:", s)

cmd = skill.build_command("scaff", graph_prefix="$WORK/out_K51/E_coli", fill_gaps=True)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-63mer scaff"), s
assert "-g $WORK/out_K51/E_coli" in s and s.rstrip().endswith("-F"), s
print("  OK:", s)

# --mer 127 应切换到 SOAPdenovo-127mer
cmd = skill.build_command("all", config="$WORK/config.txt",
                          output="$WORK/out_K127/E_coli", kmer=127, mer=127, threads=4)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/SOAPdenovo-127mer all"), s
assert "-K 127" in s, s
print("  OK:", s)
PY

echo "==> [5/6] 必填参数缺失应报错"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soapdenovo2Skill
skill = Soapdenovo2Skill()
skill._resolve_binary = lambda name=None, **kw: f"/opt/env/bin/{name}"
for bad in (
    lambda: skill.build_command("all", output="x"),
    lambda: skill.build_command("all", config="c.txt"),
    lambda: skill.build_command("contig"),
    lambda: skill.build_command("scaff"),
):
    try:
        bad()
    except ValueError:
        pass
    else:
        raise AssertionError("缺少必填参数时应抛 ValueError")
print("  OK: 必填参数校验生效")
PY

echo "==> [6/6] SOAPdenovo 冒烟（若已安装）"
FOUND=""
for b in SOAPdenovo-63mer SOAPdenovo-127mer; do
    if command -v "$b" >/dev/null 2>&1; then FOUND="$b"; break; fi
done
if [[ -n "$FOUND" ]]; then
    echo "  已安装: $FOUND"
    "$FOUND" 2>&1 | head -n 3 || true
else
    echo "  SOAPdenovo 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
