#!/usr/bin/env bash
# gmap native 最小回归测试（真实命令构造 + stub 假二进制 CLI 冒烟）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - GMAP/GSNAP（gmap_build/gmap/gsnap）【可选】：已装时 argv 冒烟走真实二进制；
#     未装则用 stub 假二进制做 CLI 冒烟（echo 参数，rc 0）。
#   - 本测试不下载/不编译 gmap 源码包。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你参考 FASTA + mRNA + reads）"
cat > "$WORK/genome.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '>mrna1\nACGTACGTACGTACGTACGTACGTACGTACGT\n' > "$WORK/mrna.fa"
printf '@r1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_1.fq"
printf '@r2\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_2.fq"
test -s "$WORK/genome.fa" && test -s "$WORK/mrna.fa" && test -s "$WORK/reads_1.fq"
echo "  OK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^gmap_build'
python "$NATIVE/main.py" --list-commands | grep -q '^gmap '
python "$NATIVE/main.py" --list-commands | grep -q '^gsnap'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（gmap_build/gmap/gsnap）+ --schema"

echo "==> [3/6] argv 构造验证：gmap_build / gmap / gsnap"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GmapSkill, build_parser, _BINARIES

assert _BINARIES == {"gmap_build": "gmap_build", "gmap": "gmap", "gsnap": "gsnap"}, _BINARIES

skill = GmapSkill()
skill._resolve_sub_binary = lambda sub: "/opt/gmap/bin/" + _BINARIES[sub]

# gmap_build（-D/-d + 参考 FASTA；--gunzip 变体）
cmd = skill.build_command(
    "gmap_build", db_dir="dbs", db_name="genome", reference="$WORK/genome.fa",
)
s = " ".join(cmd)
assert "/opt/gmap/bin/gmap_build" in s, s
assert "-D dbs" in s and "-d genome" in s, s
assert "--gunzip" not in s, s
assert s.rstrip().endswith("$WORK/genome.fa"), s
print("  OK:", s)
cmd = skill.build_command(
    "gmap_build", db_name="genome", reference="$WORK/genome.fa.gz", gunzip=True,
)
s = " ".join(cmd)
assert "--gunzip" in s and "-D ." in s, s
print("  OK:", s)

# gmap（-D/-d/-t/-f/-n + reads）
cmd = skill.build_command(
    "gmap", db_dir="dbs", db_name="genome", reads="$WORK/mrna.fa",
    format="samse", npaths=10, threads=8,
)
s = " ".join(cmd)
assert "/opt/gmap/bin/gmap" in s, s
for frag in ("-D dbs", "-d genome", "-t 8", "-f samse", "-n 10"):
    assert frag in s, (frag, s)
assert s.rstrip().endswith("$WORK/mrna.fa"), s
print("  OK:", s)

# gsnap（-A sam + 双端 reads；auto 线程 → -t 4）
cmd = skill.build_command(
    "gsnap", db_dir="dbs", db_name="genome",
    reads=["$WORK/reads_1.fq", "$WORK/reads_2.fq"], sam=True, threads="auto",
)
s = " ".join(cmd)
assert "/opt/gmap/bin/gsnap" in s, s
for frag in ("-D dbs", "-d genome", "-t 4", "-A sam"):
    assert frag in s, (frag, s)
assert "$WORK/reads_1.fq" in s and "$WORK/reads_2.fq" in s, s
assert s.rstrip().endswith("$WORK/reads_2.fq"), s
print("  OK:", s)

# parser
ns = build_parser().parse_args(["gmap_build", "$WORK/genome.fa", "-d", "genome",
                                "-D", "dbs", "--gunzip"])
assert ns.subcommand == "gmap_build" and ns.db_name == "genome" and ns.db_dir == "dbs"
assert ns.gunzip is True and ns.reference == "$WORK/genome.fa"
ns = build_parser().parse_args(
    ["gmap", "$WORK/mrna.fa", "-D", "dbs", "-d", "genome", "-f", "sampe",
     "-n", "5", "--threads", "8"])
assert ns.subcommand == "gmap" and ns.reads == ["$WORK/mrna.fa"]
assert ns.format == "sampe" and ns.npaths == 5 and ns.threads == 8
ns = build_parser().parse_args(
    ["gsnap", "$WORK/reads_1.fq", "$WORK/reads_2.fq", "-d", "genome", "-A"])
assert ns.subcommand == "gsnap" and ns.sam is True and ns.db_name == "genome"
print("  OK: parser（gmap_build/gmap/gsnap 全参数）")
PY

echo "==> [4/6] build_command 运行时校验：缺必填 / 非法格式 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GmapSkill

skill = GmapSkill()
skill._resolve_sub_binary = lambda sub: "gmap"

# gmap_build：缺 db_name / 缺 reference
for kw in (dict(reference="$WORK/genome.fa"), dict(db_name="genome"), dict()):
    try:
        skill.build_command("gmap_build", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# gmap：缺 db_name / 缺 reads
for kw in (dict(reads="$WORK/mrna.fa"), dict(db_name="genome"), dict()):
    try:
        skill.build_command("gmap", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# gsnap：缺 db_name / 缺 reads
for kw in (dict(reads="$WORK/reads_1.fq"), dict(db_name="genome"), dict()):
    try:
        skill.build_command("gsnap", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# gmap 非法 -f
try:
    skill.build_command("gmap", db_name="genome", reads="$WORK/mrna.fa",
                        format="cram")
    raise AssertionError("非法 -f 应报错")
except RuntimeError:
    pass
# 未知子命令
try:
    skill.build_command("star", db_name="g", reads="r.fa")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import GmapSkill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "gmap_build2", "snp"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [5/6] CLI 层校验：无子命令返回 2；stub 三命令冒烟（echo 参数 rc 0）"
mkdir -p "$WORK/fakebin"
for b in gmap_build gmap gsnap; do
    printf '#!/usr/bin/env bash\necho "stub-%s:" "$@"\n' "$b" > "$WORK/fakebin/$b"
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

# gmap_build stub
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gmap_build", "$WORK/genome.fa",
     "-d", "genome", "-D", "dbs"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "stub-gmap_build:" in r.stdout and "-d genome" in r.stdout, r.stdout
assert "-D dbs" in r.stdout and "$WORK/genome.fa" in r.stdout, r.stdout
print("  OK: CLI 层（gmap_build stub 冒烟）")

# gmap stub
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gmap", "$WORK/mrna.fa",
     "-d", "genome", "-D", "dbs", "-f", "samse", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "stub-gmap:" in r.stdout and "-d genome" in r.stdout, r.stdout
assert "-f samse" in r.stdout and "-t 8" in r.stdout, r.stdout
print("  OK: CLI 层（gmap stub 冒烟）")

# gsnap stub
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gsnap", "$WORK/reads_1.fq",
     "$WORK/reads_2.fq", "-d", "genome", "-A"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "stub-gsnap:" in r.stdout and "-d genome" in r.stdout, r.stdout
assert "-A sam" in r.stdout and "$WORK/reads_2.fq" in r.stdout, r.stdout
print("  OK: CLI 层（gsnap stub 冒烟）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "gmap", "$WORK/mrna.fa", "-d", "genome"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'gmap'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [6/6] 真实冒烟（本机已装 gmap_build 时跳过——stub 冒烟已覆盖执行路径）"
if command -v gmap >/dev/null 2>&1 && command -v gmap_build >/dev/null 2>&1; then
    echo "  已检测到 gmap（真实建库/比对需较大数据，不做；argv/stub 冒烟已通过）"
else
    echo "  gmap 未安装，argv/stub 冒烟已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
