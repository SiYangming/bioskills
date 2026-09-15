#!/usr/bin/env bash
# newbler native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - Newbler 二进制（runAssembly/runMapping）【可选】：软件已淘汰且官方停服，
#     通常不会安装；本测试以 stub 假二进制做 CLI 层冒烟，不下载/不编译/不执行真实组装。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在仓库内产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（占位 SFF + 迷你参考 FASTA）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/454Reads.sff" && test -s "$WORK/reference.fasta"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^assemble'
python "$NATIVE/main.py" --list-commands | grep -q '^map'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（assemble/map）+ --schema"

echo "==> [3/7] argv 构造验证：assemble（runAssembly 454 组装）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NewblerSkill, build_parser, _BINARIES

assert _BINARIES == {"assemble": "runAssembly", "map": "runMapping"}, _BINARIES

skill = NewblerSkill()
skill._resolve_sub_binary = lambda sub: "/opt/454/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "assemble", reads="$WORK/454Reads.sff", output_dir="./", force=True, trimmed=True)
s = " ".join(cmd)
assert cmd[0] == "/opt/454/bin/runAssembly", s
assert "-o ./" in s, s
assert "-force" in s, s
assert "-tr" in s, s
assert s.rstrip().endswith("$WORK/454Reads.sff"), s
print("  OK:", s)

# 关闭 force/trimmed 时不应出现对应旗标
cmd = skill.build_command(
    "assemble", reads="$WORK/454Reads.sff", output_dir="$WORK/out", force=False, trimmed=False)
s = " ".join(cmd)
assert "-force" not in s and "-tr" not in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["assemble", "-r", "$WORK/454Reads.sff", "-o", "./", "--no-force", "--no-trimmed", "--threads", "4"])
assert ns.subcommand == "assemble" and ns.reads == "$WORK/454Reads.sff"
assert ns.force is False and ns.trimmed is False and ns.threads == 4, ns
print("  OK: parser assemble")
PY

echo "==> [4/7] argv 构造验证：map（runMapping 454 回贴参考）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NewblerSkill, build_parser, _BINARIES

skill = NewblerSkill()
skill._resolve_sub_binary = lambda sub: "/opt/454/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "map", reads="$WORK/454Reads.sff", reference="$WORK/reference.fasta",
    output_dir="./", force=True, trimmed=True)
s = " ".join(cmd)
assert cmd[0] == "/opt/454/bin/runMapping", s
assert "$WORK/454Reads.sff" in s, s
assert s.rstrip().endswith("$WORK/reference.fasta"), s
print("  OK:", s)

ns = build_parser().parse_args(
    ["map", "-r", "$WORK/454Reads.sff", "-R", "$WORK/reference.fasta", "-o", "."])
assert ns.subcommand == "map" and ns.reference == "$WORK/reference.fasta", ns
print("  OK: parser map")
PY

echo "==> [5/7] build_command 运行时校验：缺必填 / 缺参考 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import NewblerSkill

skill = NewblerSkill()
skill._resolve_sub_binary = lambda sub: "runAssembly"

# 缺 reads
for sub in ("assemble", "map"):
    try:
        skill.build_command(sub, reference="$WORK/reference.fasta")
        raise AssertionError("缺 reads 应抛 RuntimeError: %r" % sub)
    except RuntimeError:
        pass
# map 缺 reference
try:
    skill.build_command("map", reads="$WORK/454Reads.sff")
    raise AssertionError("map 缺 reference 应抛 RuntimeError")
except RuntimeError:
    pass
# 未知子命令（用未 monkeypatch 的干净实例，_binary_for 应先抛错）
from main import NewblerSkill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "assemble2", "mapping"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；assemble 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/runAssembly"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/runMapping"
chmod +x "$WORK/fakebin/runAssembly" "$WORK/fakebin/runMapping"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

def norm_stdout(text: str) -> str:
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble",
     "-r", "$WORK/454Reads.sff", "-o", "./", "--no-force", "--no-trimmed"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "runAssembly" in norm and "-o ./" in norm, norm
assert "$WORK/454Reads.sff" in norm, norm
print("  OK: CLI 层（assemble deprecated 提示 + 命令构造输出）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble", "-r", "$WORK/454Reads.sff", "-o", "./"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'runAssembly'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [7/7] 真实冒烟（本机已装 Newbler 时跳过——说明型驱动不执行真实组装）"
if command -v runAssembly >/dev/null 2>&1; then
    echo "  已检测到 runAssembly（说明型驱动不执行真实组装；argv 构造验证已覆盖）"
else
    echo "  Newbler 未安装（已淘汰，通常无法安装），argv 构造验证已通过"
fi

echo "ALL TESTS PASSED"
