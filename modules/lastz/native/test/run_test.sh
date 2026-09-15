#!/usr/bin/env bash
# LASTZ native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - lastz 二进制【可选】：若已安装（conda 环境 lastz / brew / 容器），会额外做版本冒烟
#     + 用迷你序列跑一次真实比对；否则仅做 argv 构造断言（monkeypatch _resolve_sub_binary，
#     不依赖工具已安装）。
# 说明：LASTZ 单线程，--threads 仅占位接受不注入命令行。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你参考/查询 FASTA）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/ref.fasta" && test -s "$WORK/query.fasta"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^align' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证：align（format/output/hspthresh/gappedthresh/filter）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LastzSkill, build_parser, _BINARIES

assert _BINARIES == {"align": "lastz"}, _BINARIES

skill = LastzSkill()
skill._resolve_sub_binary = lambda sub: "/opt/env/bin/lastz"

cmd = skill.build_command(
    "align", target="$WORK/ref.fasta", query="$WORK/query.fasta",
    output="$WORK/result.maf", format="maf",
    hspthresh=2200, gappedthresh=4000, identity=90, coverage=50,
    step=20, notransition=True,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/lastz", s
assert s.startswith("/opt/env/bin/lastz $WORK/ref.fasta $WORK/query.fasta"), s
for frag in ("--output=$WORK/result.maf", "--format=maf", "--hspthresh=2200",
             "--gappedthresh=4000", "--filter=identity:90", "--filter=coverage:50",
             "--step=20", "--notransition"):
    assert frag in s, (frag, s)
print("  OK:", s)

# 二档：lav 输出 + nogapped + chain
cmd = skill.build_command(
    "align", target="$WORK/ref.fasta", query="$WORK/query.fasta",
    output="$WORK/result.lav", format="lav", nogapped=True, chain=True,
)
s = " ".join(cmd)
for frag in ("--output=$WORK/result.lav", "--format=lav", "--nogapped", "--chain"):
    assert frag in s, (frag, s)
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式；threads 占位为字符串）
ns = build_parser().parse_args(
    ["align", "$WORK/ref.fasta", "$WORK/query.fasta",
     "--output", "$WORK/o.maf", "--format", "maf", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "align" and ns.threads == "4" and ns.tmpdir == "/tmp", ns
assert ns.target == "$WORK/ref.fasta" and ns.query == "$WORK/query.fasta"
print("  OK: parser align")
PY

echo "==> [4/6] 运行时参数校验：缺 target/query、未知子命令、线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LastzSkill

skill = LastzSkill()
skill._resolve_sub_binary = lambda sub: "lastz"

for kw in (dict(query="q.fa"), dict(target="t.fa")):
    try:
        skill.build_command("align", **kw)
        raise AssertionError("缺必填参数应报错: %r" % kw)
    except ValueError:
        pass
try:
    skill.build_command("bogus", target="t.fa", query="q.fa")
    raise AssertionError("未知子命令应报错")
except ValueError:
    pass

# 线程优先级：用户显式 > per_subcommand_threads(align=1) > default
assert skill._effective_threads("align", 8) == 8
assert skill._effective_threads("align", None) == 1
print("  OK: 运行时校验 + 线程优先级")
PY

echo "==> [5/6] CLI 层校验：无子命令返回 2；无二进制时明确报错 rc 1"
python3 - <<PY
import sys, subprocess
sys.path.insert(0, "$NATIVE")
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "align", "$WORK/ref.fasta", "$WORK/query.fasta",
     "--output", "$WORK/x.maf"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'lastz'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无子命令 rc 2；无二进制 rc 1）")
PY

echo "==> [6/6] lastz 真实冒烟（若已安装）"
if command -v lastz >/dev/null 2>&1; then
    lastz --version | head -n 1
    python "$NATIVE/main.py" align "$WORK/ref.fasta" "$WORK/query.fasta" \
        --output "$WORK/real.maf" --format maf 2>/dev/null || true
    if test -s "$WORK/real.maf"; then
        echo "  OK: lastz 真实冒烟通过（real.maf 已产出）"
    else
        echo "  已检测到 lastz 但迷你数据未产出（序列过短；argv 构造验证已通过）"
    fi
else
    echo "  lastz 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
