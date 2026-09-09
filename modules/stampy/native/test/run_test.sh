#!/usr/bin/env bash
# stampy native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - Stampy 1.0.32（stampy.py）【可选】：已装时按说明型驱动走命令构造（不执行真实
#     比对，deprecated 软件默认路径）；未装则用 stub 假二进制做 CLI 冒烟。
#   - 本测试不下载/不编译/不执行真实 stampy（任务约束 + 软件 deprecated + Python2）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（迷你参考 FASTA + PE reads）"
cat > "$WORK/ref.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '@r1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_1.fastq"
printf '@r2\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_2.fastq"
test -s "$WORK/ref.fa" && test -s "$WORK/reads_1.fastq" && test -s "$WORK/reads_2.fastq"
echo "  OK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^genome'
python "$NATIVE/main.py" --list-commands | grep -q '^hash'
python "$NATIVE/main.py" --list-commands | grep -q '^map'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（genome/hash/map）+ --schema"

echo "==> [3/7] argv 构造验证：genome（-G 前缀 + FASTA + species/assembly）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StampySkill, build_parser, _BINARIES

assert _BINARIES == {"genome": "stampy.py", "hash": "stampy.py", "map": "stampy.py"}, _BINARIES

skill = StampySkill()
skill._resolve_sub_binary = lambda sub: "~/software/stampy-1.0.32/stampy.py"

cmd = skill.build_command(
    "genome", prefix="genome", reference=["$WORK/ref.fa"],
    species="human", assembly="hg19",
)
s = " ".join(cmd)
assert "~/software/stampy-1.0.32/stampy.py" in s, s
assert "-G genome" in s, s
assert "--species human" in s and "--assembly hg19" in s, s
assert "$WORK/ref.fa" in s and s.rstrip().endswith("hg19"), s
print("  OK:", s)

# parser：genome 位置参数 prefix + reference
ns = build_parser().parse_args(
    ["genome", "genome", "$WORK/ref.fa", "--species", "human", "--assembly", "hg19"])
assert ns.subcommand == "genome" and ns.prefix == "genome"
assert ns.reference == ["$WORK/ref.fa"]
assert ns.species == "human" and ns.assembly == "hg19"
print("  OK: parser genome")
PY

echo "==> [4/7] argv 构造验证：hash（-g -H + maxcount）与 map（全参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StampySkill, build_parser, _BINARIES

skill = StampySkill()
skill._resolve_sub_binary = lambda sub: "~/software/stampy-1.0.32/stampy.py"

# hash
cmd = skill.build_command("hash", prefix="genome", maxcount=100)
s = " ".join(cmd)
assert "-g genome" in s and "-H genome" in s, s
assert "--maxcount 100" in s, s
print("  OK:", s)

# map 全参数（--sensitive / --substitutionrate / -t 线程 / -f / -o）
cmd = skill.build_command(
    "map", genome_prefix="genome", hash_prefix="genome",
    reads="$WORK/reads_1.fastq,$WORK/reads_2.fastq",
    output="$WORK/out.sam", output_format="sam",
    sensitive=True, substitution_rate=0.01, threads=8,
)
s = " ".join(cmd)
assert "-g genome" in s and "-h genome" in s, s
assert "-M $WORK/reads_1.fastq,$WORK/reads_2.fastq" in s, s
assert "$WORK/out.sam" in s and "-f sam" in s, s
for frag in ("--sensitive", "--substitutionrate 0.01", "-t 8"):
    assert frag in s, (frag, s)
print("  OK:", s)

# map：auto 线程不注入 -t
cmd = skill.build_command(
    "map", genome_prefix="genome", hash_prefix="genome",
    reads="$WORK/reads_1.fastq", output_format="sam", threads="auto",
)
s = " ".join(cmd)
assert "-t" not in s, s
print("  OK:", s)

# parser：hash + map
ns = build_parser().parse_args(["hash", "genome", "--maxcount", "50"])
assert ns.subcommand == "hash" and ns.prefix == "genome" and ns.maxcount == 50
ns = build_parser().parse_args(
    ["map", "-g", "genome", "--hash-prefix", "genome", "-M", "$WORK/reads_1.fastq,$WORK/reads_2.fastq",
     "-o", "$WORK/out.sam", "-f", "sam", "--sensitive",
     "--substitution-rate", "0.02", "--threads", "4"])
assert ns.subcommand == "map" and ns.genome_prefix == "genome" and ns.hash_prefix == "genome"
assert ns.sensitive is True and ns.substitution_rate == 0.02 and ns.threads == 4
assert ns.output_format == "sam"
print("  OK: parser hash + map（全参数）")
PY

echo "==> [5/7] build_command 运行时校验：缺必填 / 非法格式 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import StampySkill

skill = StampySkill()
skill._resolve_sub_binary = lambda sub: "stampy.py"

# genome：缺 prefix / 缺 reference
for kw in (dict(reference=["$WORK/ref.fa"]),
           dict(prefix="genome"),
           dict()):
    try:
        skill.build_command("genome", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# hash：缺 prefix
try:
    skill.build_command("hash")
    raise AssertionError("hash 缺 prefix 应报错")
except RuntimeError:
    pass
# map：缺 genome/hash/reads
for kw in (dict(hash_prefix="h", reads="r.fq"),
           dict(genome_prefix="g", reads="r.fq"),
           dict(genome_prefix="g", hash_prefix="h")):
    try:
        skill.build_command("map", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# map：非法 -f 格式
try:
    skill.build_command("map", genome_prefix="g", hash_prefix="h",
                        reads="r.fq", output_format="cram")
    raise AssertionError("非法 -f 应报错")
except RuntimeError:
    pass
# 未知子命令
try:
    skill.build_command("align", genome_prefix="g", hash_prefix="h", reads="r.fq")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import StampySkill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "simulate", "run"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；map 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/stampy.py"
chmod +x "$WORK/fakebin/stampy.py"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

def norm_stdout(text: str) -> str:
    # 命令按 " \\\n    " 续行打印：逐行分词并丢弃续行反斜杠
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

# map：stub PATH 下构造命令（rc 0 + deprecated 提示）
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "map", "-g", "genome", "--hash-prefix", "genome",
     "-M", "$WORK/reads_1.fastq,$WORK/reads_2.fastq", "-o", "$WORK/out.sam",
     "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "stampy.py" in norm and "-g genome" in norm and "-h genome" in norm, norm
assert "$WORK/reads_1.fastq,$WORK/reads_2.fastq" in norm, norm
assert "$WORK/out.sam" in norm and "-f sam" in norm and "-t 8" in norm, norm
print("  OK: CLI 层（map deprecated 提示 + 命令构造输出）")

# genome：stub PATH 下构造 + .stidx 产物 hint
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "genome", "genome", "$WORK/ref.fa",
     "--species", "human"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
norm = norm_stdout(r.stdout)
assert "stampy.py" in norm and "-G genome" in norm, norm
assert ".stidx" in r.stderr, r.stderr
print("  OK: CLI 层（genome 命令构造 + 产物提示）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "hash", "genome"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'stampy.py'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [7/7] 真实冒烟（本机已装 stampy.py 时跳过——说明型驱动不执行真实比对）"
if command -v stampy.py >/dev/null 2>&1; then
    echo "  已检测到 stampy.py（说明型驱动不执行真实比对；argv 构造验证已覆盖）"
else
    echo "  stampy 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
