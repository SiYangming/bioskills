#!/usr/bin/env bash
# gce native 最小回归测试（GCE 1.0.0：kmer_freq_hash + gce）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - GCE 二进制【可选】：若已安装（gce / kmer_freq_hash 在 PATH），会额外做冒烟；
#     否则跳过真实执行。
# 说明：GCE 需要真实测序数据才能产出有意义结果，合成数据无法覆盖真实计算，因此对
#      kmer_freq_hash / gce 采用「python 构造 argv 验证命令构建不崩溃」的断言方式；
#      CLI 层用 stub 假二进制验证命令构造与参数校验。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（reads 列表 + 深度频率表）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.list" && test -s "$WORK/out.freq.stat"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^kmer_freq_hash'
python "$NATIVE/main.py" --list-commands | grep -q '^gce'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证 #1：kmer_freq_hash（文档示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GceSkill, build_parser, _BINARIES

assert _BINARIES == {"kmer_freq_hash": "kmer_freq_hash", "gce": "gce"}, _BINARIES

skill = GceSkill()
skill._resolve_sub_binary = lambda sub: "/opt/gce-1.0.0/" + _BINARIES[sub]

cmd = skill.build_command(
    "kmer_freq_hash", reads_list="$WORK/reads.list", kmer_size=21,
    output_prefix="$WORK/out", init_hash=80000000, threads=8,
)
s = " ".join(cmd)
assert "/opt/gce-1.0.0/kmer_freq_hash" in s, s
assert "-k 21" in s, s
assert "-l $WORK/reads.list" in s, s
assert "-t 8" in s, s
assert "-i 80000000" in s, s
assert "-o 0" in s and "-p $WORK/out" in s, s
print("  OK:", s)

# parser（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["kmer_freq_hash", "-l", "$WORK/reads.list", "-k", "21", "-p", "$WORK/out",
     "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "kmer_freq_hash" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.reads_list == "$WORK/reads.list" and ns.output_prefix == "$WORK/out"
print("  OK: parser kmer_freq_hash")
PY

echo "==> [4/7] argv 构造验证 #2：gce（纯合 / 杂合模式）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GceSkill, build_parser, _BINARIES

skill = GceSkill()
skill._resolve_sub_binary = lambda sub: "/opt/gce-1.0.0/" + _BINARIES[sub]

# 文档示例：gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1
cmd = skill.build_command(
    "gce", freq_stat="$WORK/out.freq.stat", uniq_coverage=21,
    genome_size=273206457, est_mode=1, max_depth=8, bias=1,
)
s = " ".join(cmd)
assert "/opt/gce-1.0.0/gce" in s, s
assert "-f $WORK/out.freq.stat" in s, s
for frag in ("-c 21", "-g 273206457", "-m 1", "-D 8", "-b 1"):
    assert frag in s, (frag, s)
assert "-H" not in s, s
print("  OK:", s)

# 杂合模式：-H 1；仅最小参数
cmd = skill.build_command("gce", freq_stat="$WORK/out.freq.stat", hybrid=True)
s = " ".join(cmd)
assert "-H 1" in s, s
assert "-c" not in s and "-g" not in s, s
print("  OK:", s)

# parser：gce 全参数
ns = build_parser().parse_args(
    ["gce", "-f", "$WORK/out.freq.stat", "-g", "273206457", "-m", "1",
     "-D", "8", "-b", "1", "-H", "-o", "$WORK/out.table", "--log", "$WORK/out.log"])
assert ns.subcommand == "gce" and ns.freq_stat == "$WORK/out.freq.stat"
assert ns.genome_size == 273206457 and ns.hybrid is True and ns.max_depth == 8
assert ns.output == "$WORK/out.table" and ns.log == "$WORK/out.log"
print("  OK: parser gce（全参数）")
PY

echo "==> [5/7] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GceSkill

skill = GceSkill()
skill._resolve_sub_binary = lambda sub: sub

try:
    skill.build_command("kmer_freq_hash", output_prefix="out")
    raise AssertionError("缺 reads_list 应抛 RuntimeError")
except RuntimeError:
    pass
try:
    skill.build_command("kmer_freq_hash", reads_list="r.list")
    raise AssertionError("缺 output_prefix 应抛 RuntimeError")
except RuntimeError:
    pass
try:
    skill.build_command("gce")
    raise AssertionError("缺 freq_stat 应抛 RuntimeError")
except RuntimeError:
    pass
try:
    skill.build_command("bogus", freq_stat="x")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；stub 二进制下构造命令；缺二进制报错"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/gce"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/kmer_freq_hash"
chmod +x "$WORK/fakebin/gce" "$WORK/fakebin/kmer_freq_hash"
python3 - <<PY
import sys, os, subprocess

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "kmer_freq_hash", "-l", "$WORK/reads.list",
     "-k", "21", "-p", "$WORK/out", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gce", "-f", "$WORK/out.freq.stat",
     "-g", "273206457", "-H", "--log", "$WORK/out.log"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gce", "-f", "$WORK/out.freq.stat"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'gce'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（构造命令 + 缺二进制报错）")
PY

echo "==> [7/7] GCE 冒烟（若已安装）"
if command -v gce >/dev/null 2>&1; then
    gce -h 2>&1 | head -n 1 || true
    echo "  已检测到 gce（argv 构造验证已覆盖）"
else
    echo "  GCE 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
