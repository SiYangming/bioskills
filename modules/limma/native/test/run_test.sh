#!/usr/bin/env bash
# limma native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
# 说明：limma 为 R 包，本机通常无 R 环境；测试以「python 构造 argv（monkeypatch
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
python "$NATIVE/main.py" --list-commands | grep -q '^voom'
python "$NATIVE/main.py" --list-commands | grep -q '^check'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：analyze/voom（monkeypatch Rscript 解析）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from pathlib import Path
from main import LimmaSkill, build_parser

skill = LimmaSkill()
skill._resolve_binary = lambda: "/opt/conda/envs/limma/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", counts="$WORK/gene.rawCount.matrix", coldata="$WORK/coldata.txt",
    output="$WORK/limma_voom_results.txt", design="~condition", coef=2,
    cpm_cutoff=1, min_samples=3, adjust="BH", threads=8)

assert cmd[0] == "/opt/conda/envs/limma/bin/Rscript", cmd
assert cmd[1].endswith(".R"), cmd
script = Path(cmd[1]).read_text()
for token in ("library(limma)", "library(edgeR)", "DGEList", "calcNormFactors(y)",
              "model.matrix(~condition", "voom(y, design", "lmFit(v, design)",
              "eBayes(fit)", "topTable(fit", "write.table", "LIMMA_OK"):
    assert token in script, f"R 脚本缺少: {token}"
assert 'Sys.setenv(OMP_NUM_THREADS = "8"' in script, script
assert "coef = 2" in script and 'adjust.method = "BH"' in script, script
print("  OK:", " ".join(cmd))

cmd_voom = skill.build_command(
    "voom", counts="$WORK/gene.rawCount.matrix", coldata="$WORK/coldata.txt",
    output="$WORK/limma_voom_matrix.txt", threads=4)
voom_script = Path(cmd_voom[1]).read_text()
assert "voom(y, design, plot = FALSE)" in voom_script, voom_script
assert "v\$E" in voom_script and "LIMMA_VOOM_OK" in voom_script, voom_script
assert 'Sys.setenv(OMP_NUM_THREADS = "4"' in voom_script, voom_script
print("  OK:", " ".join(cmd_voom))

# 线程优先级：--threads > per_subcommand_threads > default_cpus
def threads_used(**extra):
    s = LimmaSkill(); s._resolve_binary = lambda: "Rscript"; s.tmpdir = "$WORK"
    c = s.build_command("analyze", counts="$WORK/gene.rawCount.matrix",
                        coldata="$WORK/coldata.txt", output="$WORK/o.txt", **extra)
    return Path(c[1]).read_text()

s_default = LimmaSkill(); s_default.tmpdir = "$WORK"
expected_default = s_default._effective_threads("analyze", None)
assert f'Sys.setenv(OMP_NUM_THREADS = "{expected_default}"' in threads_used(), "缺省应取 per_subcommand/默认"
assert 'Sys.setenv(OMP_NUM_THREADS = "3"' in threads_used(threads=3), "--threads 应优先"
print("  OK: 线程优先级 --threads > per_subcommand_threads > default_cpus")

ns = build_parser().parse_args(
    ["analyze", "$WORK/gene.rawCount.matrix", "$WORK/coldata.txt",
     "-o", "$WORK/o.txt", "--design", "~condition", "--coef", "2", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "analyze" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser analyze")
PY

echo "==> [4/4] argv 构造验证：check（library 校验走 Rscript -e）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LimmaSkill
skill = LimmaSkill()
skill._resolve_binary = lambda: "Rscript"
cmd = skill.build_command("check")
assert cmd[0] == "Rscript" and cmd[1] == "-e", cmd
assert 'library(limma)' in cmd[2] and 'packageVersion("limma")' in cmd[2], cmd
print("  OK:", " ".join(cmd[:2]), cmd[2][:60] + "...")
PY

echo "ALL TESTS PASSED"
