#!/usr/bin/env bash
# dada2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - R + dada2【可选】：若 Rscript 可用且已安装 dada2 包，会额外做包加载冒烟；否则跳过。
# 说明：DADA2 去噪需要真实扩增子数据与 R，合成数据无法覆盖真实计算，因此对全部子命令采用
#      「python 构造 argv 验证 R 脚本生成不崩溃」的断言方式；并用空 PATH 断言缺二进制约错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成 fastq 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^filterAndTrim'
python "$NATIVE/main.py" --list-commands | grep -q '^denoise'
python "$NATIVE/main.py" --list-commands | grep -q '^makeSequenceTable'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] R 脚本生成验证 #1：filterAndTrim（双端 + 截短 + 线程）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Dada2Skill, build_parser

skill = Dada2Skill()
skill._resolve_binary = lambda: "/opt/env/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "filterAndTrim", input="$WORK/sample_R1.fastq", filt="$WORK/sample_R1.filt.fastq",
    rev="$WORK/sample_R2.fastq", filt_rev="$WORK/sample_R2.filt.fastq",
    trunc_len=120, trim_left=0, max_ee=2.0, trunc_q=2, min_len=20, threads=8,
)
assert cmd[0] == "/opt/env/bin/Rscript", cmd
assert cmd[1].endswith("filterAndTrim.R"), cmd
body = open(cmd[1]).read()
assert "filterAndTrim(" in body, body
assert "truncLen = c(120, 120)" in body, body
assert "trimLeft = c(0, 0)" in body, body
assert "multithread = 8" in body, body
assert "maxEE = 2.0" in body, body
assert "$WORK/sample_R2.fastq" in body, body
print("  OK:", " ".join(cmd))

ns = build_parser().parse_args(["filterAndTrim", "$WORK/sample_R1.fastq",
                                "--filt", "$WORK/o.fq", "--trunc-len", "120",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "filterAndTrim" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser filterAndTrim")
PY

echo "==> [4/6] R 脚本生成验证 #2：learnErrors / denoise / dada / mergePairs"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Dada2Skill, build_parser

def fresh(**over):
    s = Dada2Skill()
    s._resolve_binary = lambda: "Rscript"
    s.tmpdir = "$WORK"
    return s

body = lambda cmd: open(cmd[1]).read()

# learnErrors（per_subcommand_threads.learnErrors = 8）
cmd = fresh().build_command("learnErrors", reads="$WORK/sample_R1.filt.fastq",
                            output="$WORK/errF.rds")
b = body(cmd)
assert "learnErrors(" in b and "nbases = 1e8" in b, b
assert "multithread = 8" in b, b
assert "saveRDS(err, '$WORK/errF.rds')" in b, b
print("  OK: learnErrors")

# denoise（显式 --threads 覆盖）
cmd = fresh().build_command("denoise", reads="$WORK/sample_R1.filt.fastq",
                            error="$WORK/errF.rds", output="$WORK/dadaF.rds",
                            threads=2)
b = body(cmd)
assert "dada(" in b and "multithread = 2" in b, b
assert "pool = FALSE" in b and "selfConsist = FALSE" in b, b
assert "saveRDS(denoised, '$WORK/dadaF.rds')" in b, b
print("  OK: denoise")

# dada 别名与 denoise 同源
cmd = fresh().build_command("dada", reads="$WORK/sample_R1.filt.fastq",
                            error="$WORK/errF.rds", output="$WORK/dadaF2.rds", threads=1)
assert "dada(" in body(cmd)
print("  OK: dada 别名")

# mergePairs
cmd = fresh().build_command("mergePairs", dada_f="$WORK/dadaF.rds", dada_r="$WORK/dadaR.rds",
                            filt_f="$WORK/sample_R1.filt.fastq", filt_r="$WORK/sample_R2.filt.fastq",
                            output="$WORK/mergers.rds", min_overlap=12, max_mismatch=0)
b = body(cmd)
assert "mergePairs(" in b and "minOverlap = 12" in b and "maxMismatch = 0" in b, b
assert "dadaF = dadaF" in b and "derepR = '$WORK/sample_R2.filt.fastq'" in b, b
print("  OK: mergePairs")

# parser：子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["mergePairs", "--dada-f", "a.rds", "--dada-r", "b.rds",
                                "--filt-f", "f.fq", "--filt-r", "r.fq",
                                "--output", "m.rds", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "mergePairs" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser mergePairs")
PY

echo "==> [5/6] R 脚本生成验证 #3：makeSequenceTable / removeBimera + 缺二进制约错"
python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import Dada2Skill

def fresh():
    s = Dada2Skill()
    s._resolve_binary = lambda: "Rscript"
    s.tmpdir = "$WORK"
    return s

body = lambda cmd: open(cmd[1]).read()

cmd = fresh().build_command("makeSequenceTable", input="$WORK/mergers.rds",
                            output="$WORK/seqtab.rds")
b = body(cmd)
assert "makeSequenceTable(" in b and "readRDS('$WORK/mergers.rds')" in b, b
assert "saveRDS(seqtab, '$WORK/seqtab.rds')" in b, b
print("  OK: makeSequenceTable（合并对象输入）")

cmd = fresh().build_command("makeSequenceTable", dada="$WORK/dadaF.rds,$WORK/dadaR.rds",
                            output="$WORK/seqtab2.rds")
b = body(cmd)
assert "makeSequenceTable(list(readRDS('$WORK/dadaF.rds'), readRDS('$WORK/dadaR.rds')))" in b, b
print("  OK: makeSequenceTable（dada 列表输入）")

cmd = fresh().build_command("removeBimera", input="$WORK/seqtab.rds",
                            output="$WORK/seqtab.nochim.rds", method="consensus", threads=4)
b = body(cmd)
assert "removeBimeraDenovo(" in b and "method = 'consensus'" in b, b
assert "multithread = 4" in b and "saveRDS(seqtab.nochim, '$WORK/seqtab.nochim.rds')" in b, b
print("  OK: removeBimera")

# 缺二进制约错：空 PATH 下应抛 RuntimeError（避免宿主已装 Rscript 导致误判）
os.environ["PATH"] = ""
try:
    Dada2Skill().build_command("filterAndTrim", input="$WORK/sample_R1.fastq", filt="$WORK/x.fq")
    raise AssertionError("空 PATH 下应因缺少 Rscript 抛 RuntimeError")
except RuntimeError:
    pass
print("  OK: 空 PATH 下 Rscript 缺失正确报错")
PY

echo "==> [6/6] dada2 冒烟（若 Rscript + dada2 可用）"
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'suppressPackageStartupMessages(library(dada2))' >/dev/null 2>&1; then
    Rscript -e 'cat("  dada2", as.character(packageVersion("dada2")), "\n")'
    echo "  OK: dada2 包可加载"
else
    echo "  Rscript/dada2 未安装，跳过真实冒烟（R 脚本构造验证已通过）"
fi

echo "ALL TESTS PASSED"
