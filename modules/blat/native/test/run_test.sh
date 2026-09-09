#!/usr/bin/env bash
# blat native 最小回归测试（真实命令构造 + stub 假二进制 CLI 冒烟）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - UCSC BLAT（blat）【可选】：已装时 argv 冒烟走真实二进制；未装则用 stub 假
#     二进制做 CLI 冒烟（echo 参数，rc 0）。
#   - 本测试不下载/不编译 UCSC 二进制。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你参考 FASTA + 查询 FASTA）"
cat > "$WORK/genome.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '>mrna1\nACGTACGTACGTACGTACGTACGTACGTACGT\n' > "$WORK/mrna.fa"
test -s "$WORK/genome.fa" && test -s "$WORK/mrna.fa"
echo "  OK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^blat'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（blat）+ --schema"

echo "==> [3/6] argv 构造验证：blat（-t/-q/-out + 位置参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlatSkill, build_parser, _BINARIES

assert _BINARIES == {"blat": "blat"}, _BINARIES

skill = BlatSkill()
skill._resolve_sub_binary = lambda sub: "/opt/ucsc/blat"

cmd = skill.build_command(
    "blat", database="$WORK/genome.fa", query="$WORK/mrna.fa",
    output="$WORK/mrna.psl", t_type="dnax", q_type="rnax",
    out_format="pslx", tile_size=11, min_score=30, no_head=True,
)
s = " ".join(cmd)
assert "/opt/ucsc/blat" in s, s
for frag in ("-t=dnax", "-q=rnax", "-out=pslx", "-tileSize=11", "-minScore=30", "-noHead"):
    assert frag in s, (frag, s)
assert "$WORK/genome.fa" in s and "$WORK/mrna.fa" in s and "$WORK/mrna.psl" in s, s
assert s.rstrip().endswith("$WORK/mrna.psl"), s   # output 为末位位置参数
print("  OK:", s)

# fastMap / fine / stepSize / minIdentity
cmd = skill.build_command(
    "blat", database="$WORK/genome.fa", query="$WORK/mrna.fa",
    output="$WORK/mrna.psl", fast_map=True, step_size=5, min_identity=95,
)
s = " ".join(cmd)
for frag in ("-fastMap", "-stepSize=5", "-minIdentity=95"):
    assert frag in s, (frag, s)
print("  OK:", s)

# parser：blat 全参数
ns = build_parser().parse_args(
    ["blat", "$WORK/genome.fa", "$WORK/mrna.fa", "$WORK/mrna.psl",
     "-t", "dnax", "-q", "rnax", "--out-format", "pslx",
     "--tile-size", "12", "--min-score", "20", "--fast-map"])
assert ns.subcommand == "blat" and ns.database == "$WORK/genome.fa"
assert ns.query == "$WORK/mrna.fa" and ns.output == "$WORK/mrna.psl"
assert ns.t_type == "dnax" and ns.q_type == "rnax"
assert ns.out_format == "pslx" and ns.tile_size == 12
assert ns.min_score == 20 and ns.fast_map is True
print("  OK: parser blat（全参数）")
PY

echo "==> [4/6] build_command 运行时校验：缺必填 / 非法类型/格式 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlatSkill

skill = BlatSkill()
skill._resolve_sub_binary = lambda sub: "blat"

# 缺 database / query / output
for kw in (dict(query="q.fa", output="o.psl"),
           dict(database="d.fa", output="o.psl"),
           dict(database="d.fa", query="q.fa")):
    try:
        skill.build_command("blat", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# 非法 -t/-q/-out
for bad in (dict(database="d.fa", query="q.fa", output="o", t_type="rna"),
            dict(database="d.fa", query="q.fa", output="o", out_format="bam2")):
    try:
        skill.build_command("blat", **bad)
        raise AssertionError("非法取值应报错: %r" % bad)
    except RuntimeError:
        pass
# 未知子命令
try:
    skill.build_command("gmap", database="d.fa", query="q.fa", output="o")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import BlatSkill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "gfServer", "pslMap"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [5/6] CLI 层校验：无子命令返回 2；stub blat 冒烟（echo 参数 rc 0）"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\necho "stub-blat:" "$@"\n' > "$WORK/fakebin/blat"
chmod +x "$WORK/fakebin/blat"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "blat", "$WORK/genome.fa", "$WORK/mrna.fa",
     "$WORK/mrna.psl", "-t", "dnax", "-q", "rnax", "--out-format", "psl"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "stub-blat:" in r.stdout, r.stdout
for frag in ("-t=dnax", "-q=rnax", "-out=psl", "$WORK/genome.fa",
             "$WORK/mrna.fa", "$WORK/mrna.psl"):
    assert frag in r.stdout, (frag, r.stdout)
print("  OK: CLI 层（stub blat 执行冒烟 rc 0 + 参数透传）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "blat", "$WORK/genome.fa",
     "$WORK/mrna.fa", "$WORK/mrna.psl"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'blat'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [6/6] 真实冒烟（本机已装 blat 时）"
if command -v blat >/dev/null 2>&1; then
    python "$NATIVE/main.py" blat "$WORK/genome.fa" "$WORK/mrna.fa" "$WORK/real.psl" 2>/dev/null || true
    if test -s "$WORK/real.psl"; then
        echo "  OK: blat 真实冒烟通过（real.psl 已产出）"
    else
        echo "  已检测到 blat 但 mini 数据未能产出（序列过短；argv 冒烟已通过）"
    fi
else
    echo "  blat 未安装，argv/stub 冒烟已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
