#!/usr/bin/env bash
# discovar native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - DISCOVAR 程序【可选】：本驱动为说明型，不执行真实组装；未装时用 stub 假二进制
#     （PATH 注入）做 CLI 冒烟，argv 构造断言恒跑。
#   - 本测试不下载/不编译/不执行真实 DISCOVAR（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（BAM/参考占位 + 组装目录）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/sample-reads.bam" && test -s "$WORK/sample-genome.fasta"
test -d "$WORK/a.final"
echo "  OK"

echo "==> [2/6] 自省：--list-commands / --schema"
for c in discovardenovo discovar prepare nhoodinfo; do
    python "$NATIVE/main.py" --list-commands | grep -q "^$c"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（4 子命令）+ --schema"

echo "==> [3/6] argv 构造验证：discovardenovo（KEY=VALUE + NUM_THREADS/REFHEAD）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiscovarSkill, build_parser, _BINARIES

assert _BINARIES == {"discovardenovo": "DiscovarDeNovo", "discovar": "Discovar",
                     "prepare": "PrepareDiscovarGenome", "nhoodinfo": "NhoodInfo"}, _BINARIES

skill = DiscovarSkill()
skill._resolve_sub_binary = lambda sub: "/opt/discovar/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "discovardenovo", reads="$WORK/sample-reads.bam", out_dir="$WORK/asm",
    refhead="sample-genome", threads=4)
s = " ".join(cmd)
assert "/opt/discovar/bin/DiscovarDeNovo" in s, s
assert "READS=$WORK/sample-reads.bam" in s, s
assert "OUT_DIR=$WORK/asm" in s, s
assert "NUM_THREADS=4" in s and "REFHEAD=sample-genome" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["discovardenovo", "--reads", "$WORK/sample-reads.bam", "--out-dir", "$WORK/asm",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "discovardenovo" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
print("  OK: parser discovardenovo")
PY

echo "==> [4/6] argv 构造验证：discovar（OUT_HEAD/REGIONS/TMP/REFERENCE）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiscovarSkill, _BINARIES

skill = DiscovarSkill()
skill._resolve_sub_binary = lambda sub: "/opt/discovar/bin/" + _BINARIES[sub]

# 有参考 variant calling：含 REFERENCE + 自定义 TMP
cmd = skill.build_command(
    "discovar", reads="$WORK/sample-reads.bam", out_head="$WORK/asm/genome",
    regions="10:30892106-30933760", tmp="$WORK/asm/tmp",
    reference="$WORK/sample-genome.fasta")
s = " ".join(cmd)
assert "/opt/discovar/bin/Discovar" in s, s
assert "READS=$WORK/sample-reads.bam" in s, s
assert "OUT_HEAD=$WORK/asm/genome" in s, s
assert "REGIONS=10:30892106-30933760" in s, s
assert "TMP=$WORK/asm/tmp" in s, s
assert "REFERENCE=$WORK/sample-genome.fasta" in s, s
print("  OK:", s)

# 无参考区域组装：无 REFERENCE；TMP 默认取 self.tmpdir
skill.tmpdir = "/tmp/skilltmp"
cmd = skill.build_command(
    "discovar", reads="$WORK/sample-reads.bam", out_head="$WORK/asm/genome",
    regions="10:1-100")
s = " ".join(cmd)
assert "REFERENCE=" not in s, s
assert "TMP=/tmp/skilltmp" in s, s
print("  OK: 默认 TMP 注入")
PY

echo "==> [5/6] argv 构造验证：prepare / nhoodinfo"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DiscovarSkill, _BINARIES

skill = DiscovarSkill()
skill._resolve_sub_binary = lambda sub: "/opt/discovar/bin/" + _BINARIES[sub]

cmd = skill.build_command("prepare", ref="$WORK/sample-genome.fasta")
s = " ".join(cmd)
assert s == "/opt/discovar/bin/PrepareDiscovarGenome REF=$WORK/sample-genome.fasta", s
print("  OK:", s)

cmd = skill.build_command(
    "nhoodinfo", out="out", dir_in="$WORK/a.final", seeds="10:30.5M")
s = " ".join(cmd)
assert "/opt/discovar/bin/NhoodInfo" in s, s
assert "OUT=out" in s and "DIR_IN=$WORK/a.final" in s, s
assert "SEEDS=10:30.5M" in s and "COUNT=True" in s and "SHOW_INV=True" in s, s
print("  OK:", s)

# 关闭 COUNT/SHOW_INV
cmd = skill.build_command("nhoodinfo", out="out", dir_in="$WORK/a.final",
                          count=False, show_inv=False)
s = " ".join(cmd)
assert "COUNT=False" in s and "SHOW_INV=False" in s, s
print("  OK:", s)

# 运行时校验：缺必填 / 未知子命令
for sub, kw in (("discovardenovo", dict(out_dir="d")),
                ("discovardenovo", dict(reads="r.bam")),
                ("discovar", dict(reads="r.bam", out_head="h")),
                ("prepare", {}),
                ("nhoodinfo", dict(out="o"))):
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("缺必填应报错: %r" % kw)
    except RuntimeError:
        pass
try:
    skill.build_command("bogus", reads="r")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令 rc 2；stub 二进制时构造命令 + deprecated 提示"
mkdir -p "$WORK/fakebin"
for b in DiscovarDeNovo Discovar PrepareDiscovarGenome NhoodInfo; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/$b"
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import sys, os, subprocess

def norm_stdout(text: str) -> str:
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "discovardenovo",
     "--reads", "$WORK/sample-reads.bam", "--out-dir", "$WORK/asm", "--threads", "4"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "DiscovarDeNovo" in norm and "READS=$WORK/sample-reads.bam" in norm, norm
assert "NUM_THREADS=4" in norm, norm
print("  OK: CLI 层（discovardenovo deprecated 提示 + 命令构造输出）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "prepare", "--ref", "$WORK/sample-genome.fasta"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'PrepareDiscovarGenome'" in r.stderr, \
    (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "ALL TESTS PASSED"
