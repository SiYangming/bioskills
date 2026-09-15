#!/usr/bin/env bash
# abyss native 最小回归测试（可执行驱动：argv 构造 + 真实执行冒烟）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ABySS【可选】：若 PATH 中已有 abyss-pe，额外做一次 abyss-pe --help 冒烟；
#     未安装则 [SKIP] 并打印原因（argv 构造 / argparse / 真实执行链路断言恒跑，
#     本机未装 ABySS 时全绿）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（PE/MP reads + contigs）"
python "$HERE/generate_data.py" "$WORK"
for f in fragment.1.fastq fragment.2.fastq jumping.1.fastq jumping.2.fastq E_coli-6.fa; do
    test -s "$WORK/$f"
done
echo "  OK: PE/MP reads + contigs 已生成"

echo "==> [2/7] 自省：--list-commands（8 子命令）/ --schema（JSON 合法）"
LIST="$(python "$NATIVE/main.py" --list-commands)"
for c in assemble map fixmate distance-est scaffold path-consensus merge-contigs path-overlap; do
    grep -q "^$c" <<<"$LIST"
done
test "$(printf '%s\n' "$LIST" | grep -c .)" -eq 8
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "
import json
d = json.load(open('$WORK/schema.json'))
assert d.get('type') == 'object', d
assert 'subcommand' in d.get('properties', {}), d
print('  OK: 8 子命令 + --schema JSON 合法')
"

echo "==> [3/7] argv 构造验证 #1：assemble（abyss-pe key=value + np/j）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AbyssSkill, build_parser, _BINARIES

assert _BINARIES == {"assemble": "abyss-pe", "map": "abyss-map", "fixmate": "abyss-fixmate",
                     "distance-est": "DistanceEst", "scaffold": "abyss-scaffold",
                     "path-consensus": "PathConsensus", "merge-contigs": "MergeContigs",
                     "path-overlap": "PathOverlap"}, _BINARIES

skill = AbyssSkill()
skill._resolve_sub_binary = lambda sub: "/opt/abyss/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "assemble", kmer=51, name="E_coli", lib="pe1 mp=mp1", np=4,
    extra_args='pe1="fragment.1.fastq fragment.2.fastq" mp1="jumping.1.fastq jumping.2.fastq"',
    threads=8)
s = " ".join(cmd)
assert "/opt/abyss/bin/abyss-pe" in s, s
assert "np=4" in s and "j=8" in s and "k=51" in s, s
assert "name=E_coli" in s and "lib=pe1 mp=mp1" in s, s
assert 'pe1="fragment.1.fastq fragment.2.fastq"' in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["assemble", "--kmer", "51", "--name", "E_coli", "--np", "4",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "assemble" and ns.kmer == 51 and ns.threads == 8, ns
print("  OK: parser assemble")
PY

echo "==> [4/7] argv 构造验证 #2：map / fixmate / distance-est"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AbyssSkill, _BINARIES

skill = AbyssSkill()
skill._resolve_sub_binary = lambda sub: "/opt/abyss/bin/" + _BINARIES[sub]

# map：-j J -l L r1 r2 ref
cmd = skill.build_command(
    "map", reads1="$WORK/jumping.1.fastq", reads2="$WORK/jumping.2.fastq",
    ref="$WORK/E_coli-6.fa", kmer=51, threads=4)
s = " ".join(cmd)
assert s == ("/opt/abyss/bin/abyss-map -j 4 -l 51 $WORK/jumping.1.fastq "
             "$WORK/jumping.2.fastq $WORK/E_coli-6.fa"), s
print("  OK:", s)

# fixmate：-l L -h hist
cmd = skill.build_command("fixmate", hist="$WORK/mp1-6.hist", kmer=51)
s = " ".join(cmd)
assert s == "/opt/abyss/bin/abyss-fixmate -l 51 -h $WORK/mp1-6.hist", s
print("  OK:", s)

# distance-est：--dot -j -k -l -s -n -o hist
cmd = skill.build_command(
    "distance-est", hist="$WORK/mp1-6.hist", out="$WORK/mp1-6.dist.dot", dot=True,
    kmer=51, length=51, size=200, num=3, threads=4)
s = " ".join(cmd)
assert "--dot" in s and "-j 4" in s and "-k 51" in s and "-l 51" in s, s
assert "-s 200" in s and "-n 3" in s, s
assert "-o $WORK/mp1-6.dist.dot $WORK/mp1-6.hist" in s, s
print("  OK:", s)
PY

echo "==> [5/7] argv 构造验证 #3：scaffold / path-consensus / merge-contigs / path-overlap"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AbyssSkill, _BINARIES

skill = AbyssSkill()
skill._resolve_sub_binary = lambda sub: "/opt/abyss/bin/" + _BINARIES[sub]

# scaffold：-k -s -n -g graph assembly dist
cmd = skill.build_command(
    "scaffold", graph="$WORK/E_coli-6.path.dot", assembly="$WORK/E_coli-6.fa",
    dist="$WORK/mp1-6.dist.dot", kmer=51, size=200, num=3)
s = " ".join(cmd)
assert s == ("/opt/abyss/bin/abyss-scaffold -k 51 -s 200 -n 3 -g $WORK/E_coli-6.path.dot "
             "$WORK/E_coli-6.fa $WORK/mp1-6.dist.dot"), s
print("  OK:", s)

# path-consensus：-k -p -s -g -o contigs...
cmd = skill.build_command(
    "path-consensus", scaffolds="$WORK/E_coli-7.fa", graph="$WORK/E_coli-7.adj",
    output_path="$WORK/E_coli-7.path",
    contigs=["$WORK/E_coli-6.fa", "$WORK/E_coli-6.fa", "$WORK/E_coli-6.path"],
    kmer=51, percent=0.9)
s = " ".join(cmd)
assert "/opt/abyss/bin/PathConsensus" in s, s
assert "-k 51" in s and "-p 0.9" in s, s
assert "-s $WORK/E_coli-7.fa -g $WORK/E_coli-7.adj -o $WORK/E_coli-7.path" in s, s
assert s.rstrip().endswith("$WORK/E_coli-6.path"), s
print("  OK:", s)

# merge-contigs：-k -o contigs adj path（contigs 用 '-'）
cmd = skill.build_command(
    "merge-contigs", out="$WORK/E_coli-8.fa", contigs="-",
    adj="$WORK/E_coli-7.adj", path_file="$WORK/E_coli-7.path", kmer=51)
s = " ".join(cmd)
assert s == ("/opt/abyss/bin/MergeContigs -k 51 -o $WORK/E_coli-8.fa - "
             "$WORK/E_coli-7.adj $WORK/E_coli-7.path"), s
print("  OK:", s)

# path-overlap：--overlap --dot -k adj path
cmd = skill.build_command(
    "path-overlap", adj="$WORK/E_coli-7.adj", path_file="$WORK/E_coli-7.path",
    kmer=51, overlap=True, dot=True)
s = " ".join(cmd)
assert s == ("/opt/abyss/bin/PathOverlap --overlap --dot -k 51 $WORK/E_coli-7.adj "
             "$WORK/E_coli-7.path"), s
print("  OK:", s)
PY

echo "==> [6/7] 运行时校验 + CLI 层（真实执行链路）"
mkdir -p "$WORK/fakebin"
for b in abyss-pe abyss-map abyss-fixmate DistanceEst abyss-scaffold PathConsensus \
         MergeContigs PathOverlap; do
    cat > "$WORK/fakebin/$b" <<'EOS'
#!/usr/bin/env bash
echo "FAKE $(basename "$0") $*"
EOS
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import os, subprocess, sys
sys.path.insert(0, "$NATIVE")
from main import AbyssSkill

# 缺必填 / 未知子命令
skill = AbyssSkill()
skill._resolve_sub_binary = lambda sub: "abyss"
for sub, kw in (("assemble", {}),                              # 缺 kmer
                ("map", dict(reads1="r.fq")),                  # 缺 ref
                ("fixmate", {}),                               # 缺 hist
                ("distance-est", dict(hist="h")),              # 缺 out
                ("scaffold", dict(assembly="a.fa", dist="d.dot")),          # 缺 graph
                ("path-consensus", dict(scaffolds="s", graph="g", output_path="o")),  # 缺 contigs
                ("merge-contigs", dict(out="o", adj="a", path_file="p")),   # 缺 contigs
                ("path-overlap", dict(adj="a"))):              # 缺 path
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("缺必填应报错: %s %r" % (sub, kw))
    except RuntimeError:
        pass
try:
    skill.build_command("bogus", kmer=51)
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验（8 子命令缺必填 + 未知子命令）")

# 线程优先级：显式 > per_subcommand_threads > default_cpus
assert skill._effective_threads("assemble", 4) == 4
assert skill._effective_threads("assemble", None) == 8
assert skill._effective_threads("fixmate", None) == 4
print("  OK: 线程优先级（显式 4 / assemble 默认 8 / default 4）")

# --tmpdir 经 TMPDIR 注入
skill.tmpdir = "$WORK/abyss_tmp"
assert skill.run_env()["TMPDIR"] == "$WORK/abyss_tmp", skill.run_env()
print("  OK: --tmpdir -> TMPDIR 注入")

# CLI：无子命令 -> rc 2
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
print("  OK: CLI 无子命令 rc 2")

# CLI：stub 二进制 PATH -> run() 真实执行（fake abyss-pe 被调用）
env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:/usr/bin:/bin"
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble", "--kmer", "51",
     "--name", "E_coli", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "FAKE abyss-pe" in r.stdout, r.stdout
assert "k=51" in r.stdout and "j=8" in r.stdout, r.stdout
print("  OK: run() 真实执行（stdout: %s）" % r.stdout.strip())

# CLI：真实缺二进制（PATH 无 abyss）-> 明确报错 rc 1
env = dict(os.environ)
env["PATH"] = "/nonexistent-abyss-cli-test"
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble", "--kmer", "51"],
    capture_output=True, text=True, env=env)
assert r.returncode == 1 and "未找到可执行文件 'abyss-pe'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 无二进制时明确报错 rc 1")
PY

echo "==> [7/7] ABySS 真实冒烟（若已安装）"
ABYSS_BIN=""
if command -v abyss-pe >/dev/null 2>&1; then
    ABYSS_BIN="$(command -v abyss-pe)"
elif [[ -n "${ABYSS:-}" ]] && command -v "${ABYSS}" >/dev/null 2>&1; then
    ABYSS_BIN="$(command -v "${ABYSS}")"
fi
if [[ -n "$ABYSS_BIN" ]]; then
    SMOKE="$("$ABYSS_BIN" --help 2>&1 | head -n 10 || true)"
    [[ -n "$SMOKE" ]] || SMOKE="$("$ABYSS_BIN" version 2>&1 | head -n 10 || true)"
    if [[ -n "$SMOKE" ]]; then
        echo "  OK: abyss-pe 可执行（${ABYSS_BIN}）"
        printf '%s\n' "$SMOKE" | head -n 3 | sed 's/^/      /'
    else
        echo "  [WARN] 检测到 ${ABYSS_BIN} 但无输出（--help / version 均为空）"
    fi
else
    echo "  [SKIP] PATH 中未找到 abyss-pe（\$ABYSS 亦未设置）→ 跳过真实组装冒烟。"
    echo "         原因：本机未安装 ABySS；argv 构造与 CLI 真实执行链路断言已全部通过。"
    echo "         安装后可复跑：mamba create -n abyss-native -c conda-forge -c bioconda abyss=1.9.0"
fi

echo "ALL TESTS PASSED"
