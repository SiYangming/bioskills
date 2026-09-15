#!/usr/bin/env bash
# edena native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - Edena 二进制【可选】：本驱动为说明型，不执行真实组装；未装时用 stub 假二进制
#     （PATH 注入）做 CLI 冒烟，argv 构造断言恒跑。
#   - 本测试不下载/不编译/不执行真实 edena 组装（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（PE/SE reads 占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/fragment.1.fastq" && test -s "$WORK/fragment.2.fastq" && test -s "$WORK/se.fastq"
echo "  OK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^assemble'
python "$NATIVE/main.py" --list-commands | grep -q '^overlap'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（assemble/overlap）+ --schema"

echo "==> [3/6] argv 构造验证：assemble（PE -DRpairs / SE / 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EdenaSkill, build_parser

skill = EdenaSkill()
skill._resolve_binary = lambda: "/opt/edena/bin/edena"

# PE：-nThreads + -DRpairs r1 r2 + -p
cmd = skill.build_command(
    "assemble", reads1="$WORK/fragment.1.fastq", reads2="$WORK/fragment.2.fastq",
    prefix="out", threads=4,
)
s = " ".join(cmd)
assert "/opt/edena/bin/edena" in s, s
assert "-nThreads 4" in s, s
assert "-DRpairs $WORK/fragment.1.fastq $WORK/fragment.2.fastq" in s, s
assert "-p out" in s, s
print("  OK:", s)

# SE：无 -DRpairs
cmd = skill.build_command("assemble", reads1="$WORK/se.fastq", threads=8)
s = " ".join(cmd)
assert "-nThreads 8" in s and "-DRpairs" not in s, s
assert s.rstrip().endswith("$WORK/se.fastq"), s
print("  OK:", s)

# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(
    ["assemble", "--reads1", "$WORK/se.fastq", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "assemble" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser assemble")
PY

echo "==> [4/6] argv 构造验证：overlap（-e/-overlapCutoff/-p）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EdenaSkill, build_parser

skill = EdenaSkill()
skill._resolve_binary = lambda: "edena"

cmd = skill.build_command(
    "overlap", overlap_out="$WORK/out.ovl", overlap_cutoff=70, prefix="out_70")
s = " ".join(cmd)
assert "edena -e $WORK/out.ovl" in s, s
assert "-overlapCutoff 70" in s, s
assert "-p out_70" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["overlap", "-e", "$WORK/out.ovl", "--overlap-cutoff", "50", "-p", "out_50"])
assert ns.subcommand == "overlap" and ns.overlap_cutoff == 50 and ns.prefix == "out_50", ns
print("  OK: parser overlap")
PY

echo "==> [5/6] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EdenaSkill

skill = EdenaSkill()
skill._resolve_binary = lambda: "edena"

# assemble 缺 reads1
try:
    skill.build_command("assemble")
    raise AssertionError("缺 reads1 应报错")
except RuntimeError:
    pass
# overlap 缺 -e / 缺 -overlapCutoff
try:
    skill.build_command("overlap", overlap_cutoff=70)
    raise AssertionError("缺 overlap_out 应报错")
except RuntimeError:
    pass
try:
    skill.build_command("overlap", overlap_out="out.ovl")
    raise AssertionError("缺 overlap_cutoff 应报错")
except RuntimeError:
    pass
# 未知子命令
try:
    skill.build_command("bogus", reads1="a.fastq")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令 rc 2；stub 二进制时构造命令 + deprecated 提示"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/edena"
chmod +x "$WORK/fakebin/edena"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

def norm_stdout(text: str) -> str:
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble",
     "--reads1", "$WORK/fragment.1.fastq", "--reads2", "$WORK/fragment.2.fastq",
     "--threads", "4"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "edena" in norm and "-nThreads 4" in norm, norm
assert "-DRpairs" in norm and "$WORK/fragment.1.fastq" in norm, norm
print("  OK: CLI 层（assemble deprecated 提示 + 命令构造输出）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble", "--reads1", "$WORK/se.fastq"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'edena'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "ALL TESTS PASSED"
