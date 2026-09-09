#!/usr/bin/env bash
# blasr native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - BLASR（blasr/sawriter）【可选】：已装时按说明型驱动走命令构造（不执行真实
#     比对，deprecated 软件默认路径）；未装则用 stub 假二进制做 CLI 冒烟。
#   - 本测试不下载/不编译/不执行真实 blasr（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（迷你参考 FASTA + reads）"
cat > "$WORK/ref.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '>read1\nACGTACGTACGTACGTACGTACGTACGTACGT\n' > "$WORK/subreads.fasta"
test -s "$WORK/ref.fa" && test -s "$WORK/subreads.fasta"
echo "  OK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^sawriter'
python "$NATIVE/main.py" --list-commands | grep -q '^blasr'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（sawriter/blasr）+ --schema"

echo "==> [3/7] argv 构造验证：sawriter（参考 FASTA → .sa）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlasrSkill, build_parser, _BINARIES

assert _BINARIES == {"sawriter": "sawriter", "blasr": "blasr"}, _BINARIES

skill = BlasrSkill()
skill._resolve_sub_binary = lambda sub: "~/software/blasr/bin/" + _BINARIES[sub]

cmd = skill.build_command("sawriter", reference="$WORK/ref.fa", out_sa="$WORK/ref.fa.sa")
s = " ".join(cmd)
assert "~/software/blasr/bin/sawriter" in s, s
assert "$WORK/ref.fa" in s and "$WORK/ref.fa.sa" in s, s
assert s.rstrip().endswith("$WORK/ref.fa.sa"), s
print("  OK:", s)

# parser
ns = build_parser().parse_args(["sawriter", "$WORK/ref.fa", "$WORK/ref.fa.sa"])
assert ns.subcommand == "sawriter" and ns.reference == "$WORK/ref.fa"
assert ns.out_sa == "$WORK/ref.fa.sa"
print("  OK: parser sawriter")
PY

echo "==> [4/7] argv 构造验证：blasr（BAM/SAM 输出 + nproc/bestn/minPctIdentity）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlasrSkill, build_parser, _BINARIES

skill = BlasrSkill()
skill._resolve_sub_binary = lambda sub: "~/software/blasr/bin/" + _BINARIES[sub]

# BAM 输出全参数
cmd = skill.build_command(
    "blasr", reads="$WORK/subreads.fasta", reference="$WORK/ref.fa",
    sa_file="$WORK/ref.fa.sa", out="$WORK/aln.bam", bam=True,
    bestn=10, min_pct_identity=70.0, threads=8,
)
s = " ".join(cmd)
assert "~/software/blasr/bin/blasr" in s, s
assert "$WORK/subreads.fasta" in s and "$WORK/ref.fa" in s and "$WORK/ref.fa.sa" in s, s
assert "$WORK/aln.bam" in s, s
for frag in ("--bestn 10", "--minPctIdentity 70.0", "--nproc 8", "--bam"):
    assert frag in s, (frag, s)
assert "--sam" not in s, s
print("  OK:", s)

# SAM 输出 + auto 线程（默认 --nproc 4）
cmd = skill.build_command(
    "blasr", reads="$WORK/subreads.fasta", reference="$WORK/ref.fa",
    sa_file="$WORK/ref.fa.sa", out="$WORK/aln.sam", sam=True, threads="auto",
)
s = " ".join(cmd)
assert "--sam" in s and "--nproc 4" in s, s
assert "--bam" not in s, s
print("  OK:", s)

# parser：blasr 全参数
ns = build_parser().parse_args(
    ["blasr", "$WORK/subreads.fasta", "$WORK/ref.fa", "$WORK/ref.fa.sa",
     "--out", "$WORK/aln.bam", "--bam", "--bestn", "5",
     "--min-pct-identity", "75", "--threads", "16"])
assert ns.subcommand == "blasr" and ns.reads == "$WORK/subreads.fasta"
assert ns.reference == "$WORK/ref.fa" and ns.sa_file == "$WORK/ref.fa.sa"
assert ns.out == "$WORK/aln.bam" and ns.bam is True and ns.sam is False
assert ns.bestn == 5 and ns.min_pct_identity == 75.0 and ns.threads == 16
print("  OK: parser blasr（全参数）")
PY

echo "==> [5/7] build_command 运行时校验：缺必填 / sam+bam 冲突 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlasrSkill

skill = BlasrSkill()
skill._resolve_sub_binary = lambda sub: "blasr"

# sawriter：缺 reference / 缺 out_sa
for kw in (dict(out_sa="x.sa"), dict(reference="r.fa"), dict()):
    try:
        skill.build_command("sawriter", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# blasr：缺 reads/reference/sa
for kw in (dict(reference="r.fa", sa_file="r.sa"),
           dict(reads="rd.fa", sa_file="r.sa"),
           dict(reads="rd.fa", reference="r.fa")):
    try:
        skill.build_command("blasr", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# sam+bam 冲突
try:
    skill.build_command("blasr", reads="rd.fa", reference="r.fa",
                        sa_file="r.sa", sam=True, bam=True)
    raise AssertionError("--sam 与 --bam 同给应报错")
except RuntimeError:
    pass
# 未知子命令
try:
    skill.build_command("pbalign", reads="rd.fa", reference="r.fa", sa_file="r.sa")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import BlasrSkill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "align", "map"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；blasr 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/blasr"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/sawriter"
chmod +x "$WORK/fakebin/blasr" "$WORK/fakebin/sawriter"
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

# blasr：stub PATH 下构造命令（rc 0 + deprecated 提示）
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "blasr", "$WORK/subreads.fasta",
     "$WORK/ref.fa", "$WORK/ref.fa.sa", "--out", "$WORK/aln.bam", "--bam",
     "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "blasr" in norm and "$WORK/ref.fa.sa" in norm, norm
assert "$WORK/aln.bam" in norm and "--bam" in norm and "--nproc 8" in norm, norm
assert "minimap2" in r.stderr or "pbmm2" in r.stderr, r.stderr
print("  OK: CLI 层（blasr deprecated 提示 + 命令构造输出）")

# sawriter：stub PATH 下构造 + .sa hint
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "sawriter", "$WORK/ref.fa", "$WORK/ref.fa.sa"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
norm = norm_stdout(r.stdout)
assert "sawriter" in norm and "$WORK/ref.fa.sa" in norm, norm
assert ".sa" in r.stderr, r.stderr
print("  OK: CLI 层（sawriter 命令构造 + 产物提示）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "blasr", "$WORK/subreads.fasta",
     "$WORK/ref.fa", "$WORK/ref.fa.sa"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'blasr'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [7/7] 真实冒烟（本机已装 blasr 时跳过——说明型驱动不执行真实比对）"
if command -v blasr >/dev/null 2>&1; then
    echo "  已检测到 blasr（说明型驱动不执行真实比对；argv 构造验证已覆盖）"
else
    echo "  blasr 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
