#!/usr/bin/env bash
# tophat2 native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - TopHat2（tophat）【可选】：已装时按说明型驱动走命令构造（不执行真实比对，
#     deprecated 软件默认路径）；未装则用 stub 假二进制做 CLI 冒烟。
#   - 本测试不下载/不编译/不执行真实 tophat 比对（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（迷你参考 FASTA + PE reads + GTF）"
cat > "$WORK/genome.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf '@r1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_1.fq"
printf '@r2\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' > "$WORK/reads_2.fq"
printf 'chr1\ttest\texon\t1\t10\t.\t+\t.\tgene_id "g1";\n' > "$WORK/genes.gtf"
test -s "$WORK/genome.fa" && test -s "$WORK/reads_1.fq" && test -s "$WORK/genes.gtf"
echo "  OK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^tophat'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（tophat）+ --schema"

echo "==> [3/7] argv 构造验证：tophat（PE 全参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Tophat2Skill, build_parser, _BINARIES

assert _BINARIES == {"tophat": "tophat"}, _BINARIES

skill = Tophat2Skill()
skill._resolve_sub_binary = lambda sub: "~/software/tophat-2.1.1.Linux_x86_64/tophat"

cmd = skill.build_command(
    "tophat", genome_index_base="genome_index",
    reads=["$WORK/reads_1.fq", "$WORK/reads_2.fq"],
    out_dir="$WORK/tophat_out", gtf="$WORK/genes.gtf",
    transcriptome_index="tx_idx", read_mismatches=3, read_edit_dist=4,
    max_multihits=50, inner_dist=150, threads=8,
)
s = " ".join(cmd)
assert "~/software/tophat-2.1.1.Linux_x86_64/tophat" in s, s
assert "-o $WORK/tophat_out" in s and "-p 8" in s, s
assert "-G $WORK/genes.gtf" in s and "--transcriptome-index tx_idx" in s, s
for frag in ("-N 3", "--read-edit-dist 4", "--max-multihits 50", "-r 150"):
    assert frag in s, (frag, s)
assert "genome_index" in s and "$WORK/reads_1.fq" in s and "$WORK/reads_2.fq" in s, s
assert s.rstrip().endswith("$WORK/reads_2.fq"), s   # 位置参数末位为最后 reads
print("  OK:", s)

# auto 线程 → -p 4（默认注入）
cmd = skill.build_command(
    "tophat", genome_index_base="genome_index",
    reads=["$WORK/reads_1.fq", "$WORK/reads_2.fq"],
    threads="auto",
)
s = " ".join(cmd)
assert "-p 4" in s, s
assert "-G" not in s and "--transcriptome-index" not in s, s
print("  OK:", s)

# parser：tophat 全参数
ns = build_parser().parse_args(
    ["tophat", "genome_index", "$WORK/reads_1.fq", "$WORK/reads_2.fq",
     "-o", "$WORK/tophat_out", "-G", "$WORK/genes.gtf",
     "--transcriptome-index", "tx_idx", "-N", "3", "--read-edit-dist", "4",
     "--max-multihits", "50", "-r", "150", "--threads", "8"])
assert ns.subcommand == "tophat" and ns.genome_index_base == "genome_index"
assert ns.reads == ["$WORK/reads_1.fq", "$WORK/reads_2.fq"]
assert ns.out_dir == "$WORK/tophat_out" and ns.gtf == "$WORK/genes.gtf"
assert ns.transcriptome_index == "tx_idx" and ns.read_mismatches == 3
assert ns.read_edit_dist == 4 and ns.max_multihits == 50
assert ns.inner_dist == 150 and ns.threads == 8
print("  OK: parser tophat（全参数）")
PY

echo "==> [4/7] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Tophat2Skill

skill = Tophat2Skill()
skill._resolve_sub_binary = lambda sub: "tophat"

# 缺 genome_index_base / 缺 reads
for kw in (dict(reads=["$WORK/reads_1.fq"]),
           dict(genome_index_base="genome_index"),
           dict()):
    try:
        skill.build_command("tophat", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
# 未知子命令
try:
    skill.build_command("hisat2", genome_index_base="g", reads=["r.fq"])
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import Tophat2Skill as _CleanSkill
_clean = _CleanSkill()
for _sub in ("bogus", "align", "fusion"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass
print("  OK: 运行时参数校验")
PY

echo "==> [5/7] CLI 层校验：无子命令返回 2；tophat 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/tophat"
chmod +x "$WORK/fakebin/tophat"
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

# stub PATH 下构造 tophat 命令（rc 0 + deprecated 提示）
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "tophat", "genome_index",
     "$WORK/reads_1.fq", "$WORK/reads_2.fq", "-o", "$WORK/tophat_out",
     "-G", "$WORK/genes.gtf", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
assert "HISAT2" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "tophat" in norm and "genome_index" in norm, norm
assert "-o $WORK/tophat_out" in norm and "-p 8" in norm, norm
assert "-G $WORK/genes.gtf" in norm, norm
assert "$WORK/reads_1.fq" in norm and "$WORK/reads_2.fq" in norm, norm
assert norm.rstrip().endswith("$WORK/reads_2.fq"), norm
assert "accepted_hits.bam" in r.stderr, r.stderr   # 产物 hint
print("  OK: CLI 层（tophat deprecated 提示 + 命令构造输出 + 产物 hint）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "tophat", "genome_index",
     "$WORK/reads_1.fq"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'tophat'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")
PY

echo "==> [6/7] 真实冒烟（本机已装 tophat 时跳过——说明型驱动不执行真实比对）"
if command -v tophat >/dev/null 2>&1; then
    echo "  已检测到 tophat（说明型驱动不执行真实比对；argv 构造验证已覆盖）"
else
    echo "  tophat 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
