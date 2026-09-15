#!/usr/bin/env bash
# edger native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
# 说明：edgeR 为 R 包，本机通常无 R 环境；测试以「python 构造 argv（monkeypatch
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
python "$NATIVE/main.py" --list-commands | grep -q '^norm'
python "$NATIVE/main.py" --list-commands | grep -q '^check'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：analyze/norm（monkeypatch Rscript 解析）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from pathlib import Path
from main import EdgerSkill, build_parser

skill = EdgerSkill()
skill._resolve_binary = lambda: "/opt/conda/envs/edger/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", counts="$WORK/gene.rawCount.matrix", coldata="$WORK/coldata.txt",
    output="$WORK/edgeR_results.txt", pair="control,treatment",
    cpm_cutoff=1, min_samples=3, adjust="BH", threads=8)

assert cmd[0] == "/opt/conda/envs/edger/bin/Rscript", cmd
assert cmd[1].endswith(".R"), cmd
script = Path(cmd[1]).read_text()
for token in ("library(edgeR)", "DGEList", "cpm(y)", "calcNormFactors(y)",
              "estimateDisp(y)", "exactTest(y", "topTags", "write.table", "EDGER_OK"):
    assert token in script, f"R 脚本缺少: {token}"
assert 'Sys.setenv(OMP_NUM_THREADS = "8"' in script, script
assert 'pair = c("control", "treatment")' in script, script
assert "rowSums(cpm(y) > 1.0) >= 3" in script, script
print("  OK:", " ".join(cmd))

cmd_norm = skill.build_command(
    "norm", counts="$WORK/gene.rawCount.matrix", output="$WORK/edgeR_norm_factors.txt",
    method="TMM", threads=4)
norm_script = Path(cmd_norm[1]).read_text()
assert 'calcNormFactors(y, method = "TMM")' in norm_script, norm_script
assert 'Sys.setenv(OMP_NUM_THREADS = "4"' in norm_script, norm_script
assert "EDGER_NORM_OK" in norm_script, norm_script
print("  OK:", " ".join(cmd_norm))

# 线程优先级：--threads > per_subcommand_threads > default_cpus
def threads_used(**extra):
    s = EdgerSkill(); s._resolve_binary = lambda: "Rscript"; s.tmpdir = "$WORK"
    c = s.build_command("analyze", counts="$WORK/gene.rawCount.matrix",
                        coldata="$WORK/coldata.txt", output="$WORK/o.txt", **extra)
    return Path(c[1]).read_text()

s_default = EdgerSkill(); s_default.tmpdir = "$WORK"
expected_default = s_default._effective_threads("analyze", None)
assert f'Sys.setenv(OMP_NUM_THREADS = "{expected_default}"' in threads_used(), "缺省应取 per_subcommand/默认"
assert 'Sys.setenv(OMP_NUM_THREADS = "3"' in threads_used(threads=3), "--threads 应优先"
print("  OK: 线程优先级 --threads > per_subcommand_threads > default_cpus")

ns = build_parser().parse_args(
    ["analyze", "$WORK/gene.rawCount.matrix", "$WORK/coldata.txt",
     "-o", "$WORK/o.txt", "--pair", "control,treatment", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "analyze" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser analyze")
PY

echo "==> [4/4] argv 构造验证：check（library 校验走 Rscript -e）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import EdgerSkill
skill = EdgerSkill()
skill._resolve_binary = lambda: "Rscript"
cmd = skill.build_command("check")
assert cmd[0] == "Rscript" and cmd[1] == "-e", cmd
assert 'library(edgeR)' in cmd[2] and 'packageVersion("edgeR")' in cmd[2], cmd
print("  OK:", " ".join(cmd[:2]), cmd[2][:60] + "...")
PY

echo "ALL TESTS PASSED"
