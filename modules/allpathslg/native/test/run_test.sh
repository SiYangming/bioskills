#!/usr/bin/env bash
# allpathslg native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
# 前置：python3 + pyyaml（base.py 依赖）。不下载/不编译/不执行 ALLPATHS-LG
# （官方分发点已下线 + deprecated）；测试用 stub 二进制验证 CLI 层。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "WORK=$WORK"

echo "==> [1/4] 自省：--list-commands / --schema"
for sub in prepare assemble errorcorrect kspec; do
    python "$NATIVE/main.py" --list-commands | grep -q "^$sub"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（4 子命令）+ --schema"

echo "==> [2/4] argv 构造验证（prepare / assemble / errorcorrect / kspec）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AllpathsLgSkill, build_parser, _BINARIES

assert _BINARIES == {
    "prepare": "PrepareAllPathsInputs.pl",
    "assemble": "RunAllPathsLG",
    "errorcorrect": "ErrorCorrectReads.pl",
    "kspec": "KmerSpectrumPlot.pl",
}, _BINARIES

skill = AllpathsLgSkill()
skill._resolve_sub_binary = lambda sub: "/opt/allpathslg-52488/bin/" + _BINARIES[sub]

# prepare
cmd = skill.build_command(
    "prepare", data_dir="$WORK/E_coli.genome/data", in_groups_csv="$WORK/in_groups.csv",
    in_libs_csv="$WORK/in_libs.csv", ploidy=1, genome_size=4600000,
)
s = " ".join(cmd)
assert "/opt/allpathslg-52488/bin/PrepareAllPathsInputs.pl" in s, s
for frag in ("DATA_DIR=", "PLOIDY=1", "IN_GROUPS_CSV=", "IN_LIBS_CSV=",
             "GENOME_SIZE=4600000", "OVERWRITE=True"):
    assert frag in s, (frag, s)
print("  OK:", s)

# assemble
cmd = skill.build_command(
    "assemble", pre="$WORK", ref_name="E_coli.genome", data_subdir="data",
    run="run", subdir="test", maxpar=1,
)
s = " ".join(cmd)
for frag in ("RunAllPathsLG", "PRE=", "REFERENCE_NAME=E_coli.genome",
             "DATA_SUBDIR=data", "RUN=run", "SUBDIR=test", "MAXPAR=1"):
    assert frag in s, (frag, s)
print("  OK:", s)

# errorcorrect（FindErrors，含可选 KEEP_KMER_SPECTRA / FILL_FRAGMENTS / PAIRED_STDEV）
cmd = skill.build_command(
    "errorcorrect", reads_out="illumina",
    paired_reads_a="$WORK/r1.fastq", paired_reads_b="$WORK/r2.fastq",
    phred_encoding=33, paired_sep=68, paired_stdev=66, ploidy=1,
    keep_kspec=True, fill_fragments=True,
)
s = " ".join(cmd)
for frag in ("ErrorCorrectReads.pl", "PHRED_ENCODING=33", "READS_OUT=illumina",
             "KEEP_KMER_SPECTRA=1", "FILL_FRAGMENTS=1",
             "PAIRED_READS_A_IN=$WORK/r1.fastq", "PAIRED_READS_B_IN=$WORK/r2.fastq",
             "PLOIDY=1", "PAIRED_SEP=68", "PAIRED_STDEV=66"):
    assert frag in s, (frag, s)
print("  OK:", s)

# kspec
cmd = skill.build_command("kspec")
assert cmd == ["/opt/allpathslg-52488/bin/KmerSpectrumPlot.pl", "SPECTRA=1"], cmd
print("  OK:", " ".join(cmd))

# parser 全参数
ns = build_parser().parse_args([
    "errorcorrect", "--reads-out", "illumina", "--paired-reads-a", "$WORK/r1.fastq",
    "--paired-reads-b", "$WORK/r2.fastq", "--paired-sep", "68", "--paired-stdev", "66",
    "--keep-kspec", "--fill-fragments", "--ploidy", "1"])
assert ns.subcommand == "errorcorrect" and ns.reads_out == "illumina"
assert ns.paired_sep == 68 and ns.paired_stdev == 66 and ns.keep_kspec and ns.fill_fragments
print("  OK: parser errorcorrect（全参数）")
PY

echo "==> [3/4] 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AllpathsLgSkill

skill = AllpathsLgSkill()
skill._resolve_sub_binary = lambda sub: "RunAllPathsLG"

for sub, kws in [
    ("prepare", [dict(data_dir="d"), dict(in_groups_csv="g", in_libs_csv="l"),
                 dict(data_dir="d", in_groups_csv="g")]),
    ("assemble", [dict(pre="p"), dict(ref_name="r"), dict()]),
    ("errorcorrect", [dict(reads_out="o"), dict(reads_out="o", paired_reads_a="a",
                                                paired_reads_b="b"),
                      dict(reads_out="o", paired_reads_a="a", paired_reads_b="b")]),
]:
    for kw in kws:
        try:
            skill.build_command(sub, **kw)
            raise AssertionError("应抛 RuntimeError: %s %r" % (sub, kw))
        except RuntimeError:
            pass

try:
    skill.build_command("bogus", pre="p")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 缺必填 / 未知子命令校验")
PY

echo "==> [4/4] CLI 层校验：无子命令返回 2；stub PATH 下构造命令 rc 0"
mkdir -p "$WORK/fakebin"
for b in PrepareAllPathsInputs.pl RunAllPathsLG ErrorCorrectReads.pl KmerSpectrumPlot.pl; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/$b"
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode          # 无子命令 → help + rc 2

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "assemble", "--pre", "$WORK",
     "--ref-name", "E_coli.genome"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr or "deprecated" in r.stderr.lower(), r.stderr
assert "RunAllPathsLG" in r.stdout and "REFERENCE_NAME=E_coli.genome" in r.stdout, r.stdout
print("  OK: CLI assemble 构造")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "errorcorrect", "--reads-out", "illumina",
     "--paired-reads-a", "$WORK/r1.fastq", "--paired-reads-b", "$WORK/r2.fastq",
     "--paired-sep", "68", "--keep-kspec"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "ErrorCorrectReads.pl" in r.stdout and "KEEP_KMER_SPECTRA=1" in r.stdout, r.stdout
print("  OK: CLI errorcorrect 构造")

# 真实缺二进制（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "prepare", "--data-dir", "$WORK/d",
     "--in-groups-csv", "$WORK/g.csv", "--in-libs-csv", "$WORK/l.csv"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'PrepareAllPathsInputs.pl'" in r.stderr, \
    (r.returncode, r.stderr)
print("  OK: CLI 无二进制明确报错 rc 1")
PY

echo "ALL TESTS PASSED"
