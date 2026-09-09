#!/usr/bin/env bash
# soap2 (SOAPaligner) native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SOAPaligner 2.21 二进制（soap/2bwt-builder）【可选】：已装时按说明型驱动
#     走命令构造（不执行真实比对，deprecated 软件默认路径）；未装则用 stub 假
#     二进制做 CLI 冒烟。
#   - 本测试不下载/不编译/不执行真实 soap 比对（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（迷你参考 FASTA + SE/PE reads）"
cat > "$WORK/ref.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '@r1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_1.fa"
printf '@r2\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_2.fa"
test -s "$WORK/ref.fa" && test -s "$WORK/reads_1.fa" && test -s "$WORK/reads_2.fa"
echo "  OK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^2bwt-builder'
python "$NATIVE/main.py" --list-commands | grep -q '^soap'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（2bwt-builder/soap）+ --schema"

echo "==> [3/7] argv 构造验证：2bwt-builder（参考 FASTA → 索引）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soap2Skill, build_parser, _BINARIES

assert _BINARIES == {"2bwt-builder": "2bwt-builder", "soap": "soap"}, _BINARIES

skill = Soap2Skill()
skill._resolve_sub_binary = lambda sub: "/opt/soap2.21release/" + _BINARIES[sub]

cmd = skill.build_command("2bwt-builder", reference="$WORK/ref.fa")
s = " ".join(cmd)
assert "/opt/soap2.21release/2bwt-builder" in s, s
assert s.rstrip().endswith("$WORK/ref.fa"), s
print("  OK:", s)

# parser
ns = build_parser().parse_args(["2bwt-builder", "$WORK/ref.fa"])
assert ns.subcommand == "2bwt-builder" and ns.reference == "$WORK/ref.fa"
print("  OK: parser 2bwt-builder")
PY

echo "==> [4/7] argv 构造验证：soap（PE 全参数 / SE 无 -b / 线程注入）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soap2Skill, build_parser, _BINARIES

skill = Soap2Skill()
skill._resolve_sub_binary = lambda sub: "/opt/soap2.21release/" + _BINARIES[sub]

# PE 全参数（含 unpaired_out → -2；断言用 flag+值连写，避免与路径混淆）
cmd = skill.build_command(
    "soap", index="ref.fa", reads_a="$WORK/reads_1.fa", reads_b="$WORK/reads_2.fa",
    output="$WORK/lib1.soap", unpaired_out="$WORK/un.soap",
    min_insert=200, max_insert=600, filter_ns=3,
    repeat_mode=2, seed_length=100, mismatches=3, gaps=0, match_mode=2, threads=8,
)
s = " ".join(cmd)
assert "/opt/soap2.21release/soap" in s, s
assert "-D ref.fa" in s, s
assert "$WORK/reads_1.fa" in s and "$WORK/reads_2.fa" in s, s
assert "$WORK/lib1.soap" in s and "$WORK/un.soap" in s, s
for frag in ("-m 200", "-x 600", "-n 3", "-r 2", "-l 100", "-v 3", "-g 0", "-M 2", "-p 8", "-2"):
    assert frag in s, (frag, s)
print("  OK:", s)

# SE：无 -b、无 -2、auto 线程不注入 -p
cmd = skill.build_command(
    "soap", index="ref.fa", reads_a="$WORK/reads_1.fa", output="$WORK/se.soap",
    threads="auto",
)
s = " ".join(cmd)
assert "-b" not in s, s
assert "-2" not in s, s
assert "-p" not in s, s
assert "$WORK/se.soap" in s and "-D ref.fa" in s, s
print("  OK:", s)

# parser：soap 全参数
ns = build_parser().parse_args(
    ["soap", "--index", "ref.fa", "--reads-a", "$WORK/reads_1.fa",
     "--reads-b", "$WORK/reads_2.fa", "--output", "$WORK/lib1.soap",
     "--unpaired-out", "$WORK/un.sam", "--min-insert", "150", "--max-insert", "500",
     "--repeat-mode", "0", "--mismatches", "2", "--threads", "4"])
assert ns.subcommand == "soap" and ns.index == "ref.fa"
assert ns.min_insert == 150 and ns.max_insert == 500
assert ns.repeat_mode == 0 and ns.mismatches == 2 and ns.threads == 4
assert ns.unpaired_out == "$WORK/un.sam"
print("  OK: parser soap（全参数）")
PY

echo "==> [5/7] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Soap2Skill

skill = Soap2Skill()
skill._resolve_sub_binary = lambda sub: "soap"

# 2bwt-builder：缺 reference
try:
    skill.build_command("2bwt-builder")
    raise AssertionError("缺 reference 应抛 RuntimeError")
except RuntimeError:
    pass

# soap：缺 -D / 缺 -a / 缺 -o
for kw in (dict(reads_a="$WORK/reads_1.fa", output="o.soap"),      # 缺 index
           dict(index="ref.fa", output="o.soap"),                  # 缺 reads_a
           dict(index="ref.fa", reads_a="$WORK/reads_1.fa")):      # 缺 output
    try:
        skill.build_command("soap", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass

# 未知子命令
try:
    skill.build_command("soap2", index="ref.fa", reads_a="a.fa", output="o")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import Soap2Skill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "soap2", "align"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；soap 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/soap"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/2bwt-builder"
chmod +x "$WORK/fakebin/soap" "$WORK/fakebin/2bwt-builder"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

def norm_stdout(text: str) -> str:
    # 命令按 " \\\n    " 续行打印：逐行分词并丢弃续行反斜杠
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

# PATH 前置 stub bin（soap/2bwt-builder 可执行即视为已装）：构造命令应成功（rc 0）
env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "soap", "--index", "ref.fa",
     "--reads-a", "$WORK/reads_1.fa", "--reads-b", "$WORK/reads_2.fa",
     "--output", "$WORK/lib1.soap", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "soap" in norm and "-D ref.fa" in norm, norm
assert "$WORK/reads_1.fa" in norm and "$WORK/reads_2.fa" in norm, norm
assert "$WORK/lib1.soap" in norm and "-p 8" in norm, norm
print("  OK: CLI 层（soap deprecated 提示 + 命令构造输出）")

# 2bwt-builder：stub PATH 下构造索引命令 + 产物 hint
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "2bwt-builder", "$WORK/ref.fa"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "2bwt-builder" in r.stdout and "$WORK/ref.fa" in r.stdout, r.stdout
assert ".bwt" in r.stderr, r.stderr       # 索引产物 hint
print("  OK: CLI 层（2bwt-builder 命令构造 + 产物提示）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "soap", "--index", "ref.fa",
     "--reads-a", "$WORK/reads_1.fa", "--output", "$WORK/o.soap"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'soap'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [7/7] 真实冒烟（本机已装 soapaligner 时跳过——说明型驱动不执行真实比对）"
if command -v soap >/dev/null 2>&1; then
    echo "  已检测到 soap（说明型驱动不执行真实比对；argv 构造验证已覆盖）"
else
    echo "  soapaligner 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
