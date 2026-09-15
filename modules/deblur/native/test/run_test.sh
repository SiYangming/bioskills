#!/usr/bin/env bash
# deblur native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - deblur 二进制【可选】：若已安装（conda activate / PATH 中有 deblur），
#     会额外做 deblur --version 冒烟；否则跳过真实执行。
# 说明：Deblur 去噪需要真实扩增子数据与参考数据库，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式；并用空 PATH 断言缺二进制约错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（demux / ref / 去嵌合目录）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^workflow'
python "$NATIVE/main.py" --list-commands | grep -q '^build-biom-table'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证 #1：workflow（参考库 + 并行作业数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DeblurSkill, build_parser

skill = DeblurSkill()
skill._resolve_binary = lambda: "/opt/env/bin/deblur"
cmd = skill.build_command(
    "workflow", seqs_fp="$WORK/demux.fasta", output_dir="$WORK/out",
    trim_length=120, left_trim_length=0,
    reference_fp="$WORK/ref.fasta", reference_db_fp="$WORK/ref.idx",
    neg_ref_fp="$WORK/phix.fasta",
    min_reads=10, min_size=2, mean_error=0.005, indel_prob=0.01, indel_max=3,
    threads=4, overwrite=True,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/deblur", cmd
assert cmd[1] == "workflow", cmd
assert "--seqs-fp $WORK/demux.fasta" in s, s
assert "--output-dir $WORK/out" in s, s
assert "--trim-length 120" in s and "--left-trim-length 0" in s, s
assert "--pos-ref-fp $WORK/ref.fasta" in s, s
assert "--pos-ref-db-fp $WORK/ref.idx" in s, s
assert "--neg-ref-fp $WORK/phix.fasta" in s, s
assert "--min-reads 10" in s and "--min-size 2" in s, s
assert "--mean-error 0.005" in s and "--indel-prob 0.01" in s and "--indel-max 3" in s, s
assert "--jobs-to-start 4" in s, s
assert "--overwrite" in s, s
print("  OK:", s)

# 多样本参考库（append 语义）
cmd = skill.build_command("workflow", seqs_fp="$WORK/demux.fasta", output_dir="$WORK/o2",
                          trim_length=120, reference_fp=["$WORK/a.fa", "$WORK/b.fa"], threads=8)
s = " ".join(cmd)
assert "--pos-ref-fp $WORK/a.fa" in s and "--pos-ref-fp $WORK/b.fa" in s, s
assert "--jobs-to-start 8" in s, s
print("  OK: 多参考库 + threads=8")

ns = build_parser().parse_args(["workflow", "--seqs-fp", "$WORK/demux.fasta",
                                "--output-dir", "$WORK/o3", "--trim-length", "120",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "workflow" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser workflow")
PY

echo "==> [4/7] argv 构造验证 #2：dereplicate / trim / build-biom-table"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DeblurSkill, build_parser

def fresh():
    s = DeblurSkill()
    s._resolve_binary = lambda: "deblur"
    return s

cmd = fresh().build_command("dereplicate", seqs_fp="$WORK/demux.fasta",
                            output_fp="$WORK/derep.fasta", min_size=2)
assert cmd == ["deblur", "dereplicate", "$WORK/demux.fasta", "$WORK/derep.fasta", "--min-size", "2"], cmd
print("  OK:", " ".join(cmd))

cmd = fresh().build_command("trim", seqs_fp="$WORK/demux.fasta",
                            output_fp="$WORK/trim.fasta", trim_length=120)
assert cmd == ["deblur", "trim", "$WORK/demux.fasta", "$WORK/trim.fasta", "--trim-length", "120"], cmd
print("  OK:", " ".join(cmd))

cmd = fresh().build_command("build-biom-table", seqs_fp="$WORK/chimera_removed",
                            output_fp="$WORK/biom_out", min_reads=10,
                            file_type=".fasta.trim.derep.no_artifacts.msa.deblur.no_chimeras")
s = " ".join(cmd)
assert cmd[1] == "build-biom-table" and "$WORK/chimera_removed" in s, s
assert "--min-reads 10" in s and "--file_type .fasta.trim.derep.no_artifacts.msa.deblur.no_chimeras" in s, s
print("  OK:", s)

ns = build_parser().parse_args(["trim", "$WORK/demux.fasta", "$WORK/o.fasta",
                                "--trim-length", "120", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "trim" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser trim")
PY

echo "==> [5/7] 缺二进制约错（空 PATH）"
python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import DeblurSkill
os.environ["PATH"] = ""
try:
    DeblurSkill().build_command("trim", seqs_fp="$WORK/demux.fasta",
                                output_fp="$WORK/x.fasta", trim_length=120)
    raise AssertionError("空 PATH 下应因缺少 deblur 抛 RuntimeError")
except RuntimeError:
    pass
print("  OK: 空 PATH 下 deblur 缺失正确报错")
PY

echo "==> [6/7] 缺少必填参数的报错路径"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import DeblurSkill
skill = DeblurSkill()
skill._resolve_binary = lambda: "deblur"
for kwargs, name in ((dict(seqs_fp="$WORK/demux.fasta", output_dir="$WORK/o"), "workflow 缺 trim-length"),
                     (dict(seqs_fp="$WORK/demux.fasta", trim_length=120), "workflow 缺 output-dir"),
                     (dict(seqs_fp="$WORK/demux.fasta"), "trim 缺 output")):
    try:
        skill.build_command("workflow" if name.startswith("workflow") else "trim", **kwargs)
        raise AssertionError("应因缺少参数抛 ValueError: " + name)
    except ValueError:
        pass
print("  OK: 缺参报错路径正确")
PY

echo "==> [7/7] deblur 冒烟（若已安装）"
if command -v deblur >/dev/null 2>&1; then
    deblur --version
else
    echo "  deblur 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
