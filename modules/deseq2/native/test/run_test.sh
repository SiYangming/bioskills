#!/usr/bin/env bash
# deseq2 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
# 说明：DESeq2 为 R 包，本机通常无 R 环境；测试以「python 构造 argv（monkeypatch
#      _resolve_binary）+ 断言生成的 R 脚本内容」为主，不真实执行 R。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免测试导入 main.py 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（raw count 矩阵 + 分组表）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^analyze'
python "$NATIVE/main.py" --list-commands | grep -q '^vst'
python "$NATIVE/main.py" --list-commands | grep -q '^check'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：analyze/vst（monkeypatch Rscript 解析）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from pathlib import Path
from main import Deseq2Skill, build_parser

skill = Deseq2Skill()
skill._resolve_binary = lambda: "/opt/conda/envs/deseq2/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", counts="$WORK/gene.rawCount.matrix", coldata="$WORK/coldata.txt",
    output="$WORK/DESeq2_results.txt", design="~condition",
    contrast="condition,treatment,control", min_count=10, min_samples=3, threads=8)

assert cmd[0] == "/opt/conda/envs/deseq2/bin/Rscript", cmd
assert cmd[1].endswith(".R"), cmd
script = Path(cmd[1]).read_text()
for token in ("library(DESeq2)", "DESeqDataSetFromMatrix", "DESeq(dds)",
              "results(dds", "write.table", "DESEQ2_OK"):
    assert token in script, f"R 脚本缺少: {token}"
assert 'register(MulticoreParam(8))' in script, script
assert 'c("condition", "treatment", "control")' in script, script
assert "rowSums(counts(dds) >= 10) >= 3" in script, script
print("  OK:", " ".join(cmd))

cmd_vst = skill.build_command(
    "vst", counts="$WORK/gene.rawCount.matrix", coldata="$WORK/coldata.txt",
    output="$WORK/vst_normalized_matrix.txt", transform="rlog", threads=4)
vst_script = Path(cmd_vst[1]).read_text()
assert "rlog(dds, blind = FALSE)" in vst_script, vst_script
assert "register(MulticoreParam(4))" in vst_script, vst_script
assert "DESEQ2_VST_OK" in vst_script, vst_script
print("  OK:", " ".join(cmd_vst))

# 线程优先级：--threads > per_subcommand_threads > default_cpus
def threads_used(**extra):
    s = Deseq2Skill()
    s._resolve_binary = lambda: "Rscript"
    s.tmpdir = "$WORK"
    c = s.build_command("analyze", counts="$WORK/gene.rawCount.matrix",
                        coldata="$WORK/coldata.txt", output="$WORK/o.txt", **extra)
    return Path(c[1]).read_text()

s_default = Deseq2Skill(); s_default.tmpdir = "$WORK"
expected_default = s_default._effective_threads("analyze", None)
assert f"register(MulticoreParam({expected_default}))" in threads_used(), "缺省应取 per_subcommand/默认"
assert "register(MulticoreParam(3))" in threads_used(threads=3), "--threads 应优先"
print("  OK: 线程优先级 --threads > per_subcommand_threads > default_cpus")

# parser 可解析完整 argv（子命令后 --threads/--tmpdir）
ns = build_parser().parse_args(
    ["analyze", "$WORK/gene.rawCount.matrix", "$WORK/coldata.txt",
     "-o", "$WORK/o.txt", "--design", "~condition", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "analyze" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser analyze")
PY

echo "==> [4/4] argv 构造验证：check（library 校验走 Rscript -e）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Deseq2Skill
skill = Deseq2Skill()
skill._resolve_binary = lambda: "Rscript"
cmd = skill.build_command("check")
assert cmd[0] == "Rscript" and cmd[1] == "-e", cmd
assert 'library(DESeq2)' in cmd[2] and 'packageVersion("DESeq2")' in cmd[2], cmd
print("  OK:", " ".join(cmd[:2]), cmd[2][:60] + "...")
PY

echo "ALL TESTS PASSED"
