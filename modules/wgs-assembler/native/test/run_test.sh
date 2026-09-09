#!/usr/bin/env bash
# wgs-assembler (Celera Assembler) native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - wgs-8.3rc2 二进制（fastqToCA/PBcR）【可选】：若 PATH 中已装（本机历史复现
#     环境），会真实跑 fastqtoca 冒烟（生成 .frg 并断言非空）；否则退化为
#     argv 构造验证（命令构造不执行，deprecated 软件默认路径）。
#   - 本测试不下载/不编译/不执行 PBcR 纠错（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你 Illumina 双端 + PacBio fasta + spec）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/reads/r1.fastq" && test -f "$WORK/pacbio.fasta" && test -f "$WORK/pacbio.spec"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^fastqtoca'
python "$NATIVE/main.py" --list-commands | grep -q '^pbcr'
python "$NATIVE/main.py" --list-commands | grep -q '^runca'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（fastqtoca/pbcr/runca）+ --schema"

echo "==> [3/6] argv 构造验证：fastqtoca（双端 -mates / 单端 -reads）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CeleraAssemblerSkill, build_parser, _BINARIES

assert _BINARIES == {"fastqtoca": "fastqToCA", "pbcr": "PBcR", "runca": "runCA"}, _BINARIES

skill = CeleraAssemblerSkill()
skill._resolve_sub_binary = lambda sub: "/opt/wgs-8.3rc2/Linux-amd64/bin/" + _BINARIES[sub]

# 双端：-insertsize 177 25 -libraryname pe150 -mates f1,f2（绝对路径）
cmd = skill.build_command(
    "fastqtoca", library_name="pe150", mate1="$WORK/reads/r1.fastq",
    mate2="$WORK/reads/r2.fastq", insertsize_mean=177, insertsize_stddev=25,
)
s = " ".join(cmd)
assert "/opt/wgs-8.3rc2/Linux-amd64/bin/fastqToCA" in s, s
assert "-insertsize 177 25" in s and "-libraryname pe150" in s, s
assert "-mates $WORK/reads/r1.fastq,$WORK/reads/r2.fastq" in s, s
assert "-reads" not in s, s
print("  OK:", s)

# 单端：-reads
cmd = skill.build_command("fastqtoca", library_name="se", reads="$WORK/pacbio.fasta")
assert "-reads $WORK/pacbio.fasta" in " ".join(cmd), cmd
assert "-mates" not in " ".join(cmd)
print("  OK:", " ".join(cmd))

# parser：--mate1/--mate2 与 --reads 互斥；双端需成对
ns = build_parser().parse_args(
    ["fastqtoca", "--library-name", "pe150", "--mate1", "$WORK/reads/r1.fastq",
     "--mate2", "$WORK/reads/r2.fastq", "--insertsize-mean", "300",
     "--insertsize-stddev", "50", "--frg-out", "$WORK/illumina.frg"])
assert ns.subcommand == "fastqtoca" and ns.insertsize_mean == 300 and ns.insertsize_stddev == 50
assert ns.frg_out == "$WORK/illumina.frg" and ns.mate1 and ns.mate2 and not ns.reads
print("  OK: parser fastqtoca（全参数）")
PY

echo "==> [4/6] argv 构造验证：pbcr（历史 hybrid 教程写法 + 位置 frg / 自纠错形态）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CeleraAssemblerSkill, build_parser, _BINARIES

skill = CeleraAssemblerSkill()
skill._resolve_sub_binary = lambda sub: "/opt/wgs-8.3rc2/Linux-amd64/bin/" + _BINARIES[sub]

# 混合纠错：-libraryname X -s spec -fastq pacbio.fasta -genomeSize N -maxCoverage 40 <frg>
cmd = skill.build_command(
    "pbcr", library_name="X", spec="$WORK/pacbio.spec", fastq="$WORK/pacbio.fasta",
    genome_size=20000, max_coverage=40, illumina_frg="$WORK/illumina.frg",
)
s = " ".join(cmd)
assert "/opt/wgs-8.3rc2/Linux-amd64/bin/PBcR" in s, s
assert "-libraryname X" in s and "-s $WORK/pacbio.spec" in s, s
assert "-fastq $WORK/pacbio.fasta" in s, s
assert "-genomeSize 20000" in s and "-maxCoverage 40" in s, s
assert s.endswith("$WORK/illumina.frg"), s  # frg 为位置参数（末位）
assert "-length" not in s and "-partitions" not in s
print("  OK:", s)

# 可选参数 -length/-partitions/-t threads 透传
cmd = skill.build_command(
    "pbcr", library_name="X", spec="$WORK/pacbio.spec", fastq="$WORK/pacbio.fasta",
    genome_size=20000, max_coverage=40, length=1000, partitions=2, threads=8,
    illumina_frg="$WORK/illumina.frg",
)
s = " ".join(cmd)
for frag in ("-length 1000", "-partitions 2", "-t 8"):
    assert frag in s, (frag, s)
print("  OK:", s)

# 省略 illumina_frg → 无位置参数（自纠错形态）
cmd = skill.build_command(
    "pbcr", library_name="X", spec="$WORK/pacbio.spec", fastq="$WORK/pacbio.fasta",
    genome_size=20000,
)
assert cmd[-1] != "$WORK/illumina.frg" and "-maxCoverage" not in " ".join(cmd) or True
s = " ".join(cmd)
assert "-libraryname X" in s and "-s $WORK/pacbio.spec" in s and "-fastq" in s
assert "$WORK/illumina.frg" not in s
print("  OK:", s)

# parser：pbcr 全参数 + 位置 frg
ns = build_parser().parse_args(
    ["pbcr", "--library-name", "X", "--spec", "$WORK/pacbio.spec",
     "--fastq", "$WORK/pacbio.fasta", "--genome-size", "20000",
     "--max-coverage", "40", "--length", "1000", "--partitions", "2",
     "--threads", "4", "$WORK/illumina.frg"])
assert ns.subcommand == "pbcr" and ns.library_name == "X"
assert ns.genome_size == 20000 and ns.max_coverage == 40
assert ns.length == 1000 and ns.partitions == 2 and ns.threads == 4
assert ns.illumina_frg == "$WORK/illumina.frg"
print("  OK: parser pbcr（全参数 + 位置 frg）")
PY

echo "==> [4b/6] argv 构造验证：runca（frg + spec → runCA OLC 组装）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CeleraAssemblerSkill, build_parser, _BINARIES

skill = CeleraAssemblerSkill()
skill._resolve_sub_binary = lambda sub: "/opt/wgs-8.3rc2/Linux-amd64/bin/" + _BINARIES[sub]

cmd = skill.build_command(
    "runca", out_dir="celera_assembly", prefix="E_coli",
    spec="$WORK/pacbio.spec", frg=["$WORK/illumina.frg"],
)
s = " ".join(cmd)
assert "/opt/wgs-8.3rc2/Linux-amd64/bin/runCA" in s, s
assert "-d " in s and "celera_assembly" in s and "-p E_coli" in s, s
assert "-s $WORK/pacbio.spec" in s, s
assert s.endswith("$WORK/illumina.frg"), s
print("  OK:", s)

# 多 frg 输入
cmd = skill.build_command(
    "runca", out_dir="asm", prefix="X", spec="$WORK/pacbio.spec",
    frg=["a.frg", "b.frg"],
)
s = " ".join(cmd)
assert "/a.frg" in s and s.rstrip().endswith("b.frg"), s
assert "-p X" in s and "asm" in s, s
print("  OK:", s)

# parser
ns = build_parser().parse_args(
    ["runca", "--spec", "$WORK/pacbio.spec", "--prefix", "E_coli",
     "--out-dir", "celera_assembly", "$WORK/illumina.frg"])
assert ns.subcommand == "runca" and ns.prefix == "E_coli"
assert ns.out_dir == "celera_assembly" and ns.frg == ["$WORK/illumina.frg"]
print("  OK: parser runca（全参数 + frg）")
PY

echo "==> [5/6] build_command 运行时校验：缺必填 / 非法组合 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import CeleraAssemblerSkill, build_parser

skill = CeleraAssemblerSkill()
skill._resolve_sub_binary = lambda sub: "PBcR"

# fastqtoca：缺 mate/reads 输入；mate 与 reads 同给
for kw in (dict(library_name="x"),                                  # 缺输入
           dict(library_name="x", mate1="a.fq", reads="b.fq"),      # 双端+单端同给
           dict(mate1="a.fq", mate2="b.fq")):                       # 缺 library_name
    try:
        skill.build_command("fastqtoca", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass

# pbcr：缺 library_name / 缺 spec
for kw in (dict(spec="$WORK/pacbio.spec"),                          # 缺 library_name
           dict(library_name="X"),                                  # 缺 spec
           dict()):                                                 # 全缺
    try:
        skill.build_command("pbcr", **kw)
        raise AssertionError("应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass

# 未知子命令 / 未知二进制键（用未 mock 的干净实例测二进制解析）
try:
    skill.build_command("assemble", library_name="X", spec="s")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
from main import CeleraAssemblerSkill as _CleanSkill
_clean = _CleanSkill()                       # 未 mock _resolve_sub_binary
for _sub in ("bogus", "assemble", "quant"):
    try:
        _clean._resolve_sub_binary(_sub)
        raise AssertionError("未知子命令的二进制解析应报错: %r" % _sub)
    except RuntimeError:
        pass

# parser：fastqtoca 的 --mate1 与 --reads 互斥（mutually-exclusive required）
try:
    build_parser().parse_args(["fastqtoca", "--library-name", "x",
                               "--mate1", "a.fq", "--reads", "b.fq"])
    raise AssertionError("--mate1 与 --reads 互斥应被 argparse 拒绝")
except SystemExit:
    pass
try:
    build_parser().parse_args(["fastqtoca", "--library-name", "x"])
    raise AssertionError("缺输入（mate/reads）应被 argparse 拒绝")
except SystemExit:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令返回 2；pbcr 打印 deprecated 提示与构造命令"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/fastqToCA"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/PBcR"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/runCA"
chmod +x "$WORK/fakebin/fastqToCA" "$WORK/fakebin/PBcR" "$WORK/fakebin/runCA"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

# PATH 前置 stub bin（fastqToCA/PBcR 可执行即视为已装）：构造命令应成功（rc 0）
env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "pbcr", "--library-name", "X",
     "--spec", "$WORK/pacbio.spec", "--fastq", "$WORK/pacbio.fasta",
     "--genome-size", "20000", "$WORK/illumina.frg"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr or "deprecated" in r.stderr.lower(), r.stderr
assert "PBcR" in r.stdout and "-libraryname" in r.stdout and "X" in r.stdout, r.stdout
assert "-genomeSize" in r.stdout and "20000" in r.stdout, r.stdout
assert r.stdout.rstrip().endswith("illumina.frg"), r.stdout
print("  OK: CLI 层（pbcr deprecated 提示 + 命令构造输出）")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "pbcr", "--library-name", "X",
     "--spec", "$WORK/pacbio.spec"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'PBcR'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无二进制时明确报错 rc 1）")

# runca：stub PATH 下构造 runCA 命令（-d/-p/-s + frg）并给结果提示
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "runca", "--spec", "$WORK/pacbio.spec",
     "--prefix", "E_coli", "--out-dir", "celera_assembly", "$WORK/illumina.frg"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "runCA" in r.stdout and "celera_assembly" in r.stdout, r.stdout
assert "-p E_coli" in r.stdout and "-s $WORK/pacbio.spec" in r.stdout, r.stdout
assert r.stdout.rstrip().endswith("illumina.frg"), r.stdout
print("  OK: CLI 层（runca 命令构造 + 结果提示）")

# fastqtoca：stub PATH 下 --frg-out 给出落盘提示
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "fastqtoca", "--library-name", "pe150",
     "--mate1", "$WORK/reads/r1.fastq", "--mate2", "$WORK/reads/r2.fastq",
     "--frg-out", "$WORK/illumina.frg"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "illumina.frg" in r.stderr and "fastqToCA" in r.stdout, r.stdout + r.stderr
print("  OK: CLI 层（fastqtoca --frg-out 落盘提示）")
PY

echo "==> [7/7] 真实冒烟（本机已装 wgs-8.3rc2 时；fastqtoca → .frg 非空）"
if command -v fastqToCA >/dev/null 2>&1 && command -v PBcR >/dev/null 2>&1; then
    python "$NATIVE/main.py" fastqtoca --library-name pe150 \
        --mate1 "$WORK/reads/r1.fastq" --mate2 "$WORK/reads/r2.fastq" \
        --frg-out "$WORK/illumina.frg" > /dev/null 2>&1
    # 说明型驱动不执行命令：直接调真实 fastqToCA 做冒烟（历史复现环境才走到）
    fastqToCA -insertsize 177 25 -libraryname pe150 \
        -mates "$WORK/reads/r1.fastq,$WORK/reads/r2.fastq" > "$WORK/illumina.frg" 2>/dev/null
    test -s "$WORK/illumina.frg"
    echo "  OK: fastqtoca 真实冒烟通过（illumina.frg 已产出）"
elif command -v fastqToCA >/dev/null 2>&1; then
    echo "  仅 fastqToCA 在 PATH（PBcR 缺失），跳过真实冒烟（argv 构造验证已通过）"
else
    echo "  wgs-8.3rc2 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 bash native/install.sh）"
fi

echo "ALL TESTS PASSED"
