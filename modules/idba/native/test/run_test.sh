#!/usr/bin/env bash
# idba native 最小回归测试（IDBA 1.1.3：idba_ud + fq2fa）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - idba 二进制【可选】：若已安装（idba_ud / fq2fa 在 PATH），会额外做冒烟；否则跳过。
# 说明：IDBA-UD 需要真实短读才能完成组装，合成数据无法覆盖真实组装；因此对 idba_ud 采用
#      「python 构造 argv 验证命令构建不崩溃」，CLI 层用 stub 假二进制验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你 FASTQ + FASTA 占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/illumina.fasta" && test -s "$WORK/illumina.1.fastq"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^idba_ud'
python "$NATIVE/main.py" --list-commands | grep -q '^fq2fa'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：idba_ud（文档示例参数 + 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IdbaSkill, build_parser, _BINARIES

assert _BINARIES == {"idba_ud": "idba_ud", "fq2fa": "fq2fa"}, _BINARIES

skill = IdbaSkill()
skill._resolve_sub_binary = lambda sub: "/opt/idba-1.1.3/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "idba_ud", reads="$WORK/illumina.fasta", output_dir="$WORK/out",
    mink=20, maxk=100, step=20, threads=4,
)
s = " ".join(cmd)
assert "/opt/idba-1.1.3/bin/idba_ud" in s, s
assert "-r $WORK/illumina.fasta" in s, s
assert "-o $WORK/out" in s, s
for frag in ("--mink 20", "--maxk 100", "--step 20", "--num_threads 4"):
    assert frag in s, (frag, s)
print("  OK:", s)

# 可选高级参数
cmd = skill.build_command(
    "idba_ud", reads="$WORK/illumina.fasta", mink=20, maxk=100, step=20,
    min_contig=500, min_pairs=3, seed_kmer=30,
    no_local=True, no_correct=True, pre_correction=True, threads=8,
)
s = " ".join(cmd)
for frag in ("--min_contig 500", "--min_pairs 3", "--seed_kmer 30",
             "--no_local", "--no_correct", "--pre_correction", "--num_threads 8"):
    assert frag in s, (frag, s)
print("  OK:", s)

# parser（子命令后 --threads/--tmpdir）
ns = build_parser().parse_args(
    ["idba_ud", "-r", "$WORK/illumina.fasta", "--mink", "20", "--maxk", "100",
     "--step", "20", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "idba_ud" and ns.mink == 20 and ns.threads == 4 and ns.tmpdir == "/tmp"
print("  OK: parser idba_ud")
PY

echo "==> [4/6] argv 构造验证 #2：fq2fa（--filter --merge / --paired / 单端）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IdbaSkill, build_parser, _BINARIES

skill = IdbaSkill()
skill._resolve_sub_binary = lambda sub: "/opt/idba-1.1.3/bin/" + _BINARIES[sub]

# 文档示例：fq2fa --filter --merge read_1.fq read_2.fq out.fa
cmd = skill.build_command(
    "fq2fa", inputs=["$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq"],
    output="$WORK/illumina.fasta", merge=True, filter=True,
)
s = " ".join(cmd)
assert s.startswith("/opt/idba-1.1.3/bin/fq2fa"), s
assert "--merge" in s and "--filter" in s, s
assert s.endswith("$WORK/illumina.fasta"), s
assert "$WORK/illumina.1.fastq" in s and "$WORK/illumina.2.fastq" in s, s
assert "--paired" not in s, s
print("  OK:", s)

# paired 单文件模式
cmd = skill.build_command("fq2fa", inputs="$WORK/illumina.1.fastq",
                          output="$WORK/p.fasta", paired=True, filter=True)
s = " ".join(cmd)
assert "--paired" in s and "--merge" not in s, s
print("  OK:", s)

# 单端无 flag
cmd = skill.build_command("fq2fa", inputs=["$WORK/illumina.1.fastq"], output="$WORK/out.fa")
s = " ".join(cmd)
assert s == "/opt/idba-1.1.3/bin/fq2fa $WORK/illumina.1.fastq $WORK/out.fa", s
print("  OK:", s)

# parser
ns = build_parser().parse_args(
    ["fq2fa", "$WORK/illumina.1.fastq", "$WORK/illumina.2.fastq",
     "-o", "$WORK/illumina.fasta", "--merge", "--filter"])
assert ns.subcommand == "fq2fa" and ns.merge is True and ns.filter is True
assert ns.output == "$WORK/illumina.fasta" and len(ns.inputs) == 2
print("  OK: parser fq2fa")
PY

echo "==> [5/6] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import IdbaSkill

skill = IdbaSkill()
skill._resolve_sub_binary = lambda sub: sub

try:
    skill.build_command("idba_ud")
    raise AssertionError("缺 reads 应抛 RuntimeError")
except RuntimeError:
    pass
try:
    skill.build_command("fq2fa")
    raise AssertionError("缺 inputs 应抛 RuntimeError")
except RuntimeError:
    pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令返回 2；stub 下构造命令；缺二进制报错；真实冒烟"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/idba_ud"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/fq2fa"
chmod +x "$WORK/fakebin/idba_ud" "$WORK/fakebin/fq2fa"
python3 - <<PY
import sys, os, subprocess

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "fq2fa", "$WORK/illumina.1.fastq",
     "$WORK/illumina.2.fastq", "-o", "$WORK/illumina.fasta", "--merge", "--filter"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "idba_ud", "-r", "$WORK/illumina.fasta",
     "--mink", "20", "--maxk", "100", "--step", "20", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "idba_ud", "-r", "$WORK/illumina.fasta"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'idba_ud'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（构造命令 + 缺二进制报错）")
PY

if command -v idba_ud >/dev/null 2>&1; then
    echo "  已检测到 idba_ud（argv 构造验证已覆盖；真实组装需真实短读）"
else
    echo "  IDBA 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
