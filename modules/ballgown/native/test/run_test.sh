#!/usr/bin/env bash
# ballgown native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
# 说明：Ballgown 为 R 包，本机通常无 R 环境；测试以「python 构造 argv（monkeypatch
#      _resolve_binary）+ 断言生成的 R 脚本内容」为主，不真实执行 R。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免测试导入 main.py 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（StringTie 输出目录占位 + 分组表）"
python "$HERE/generate_data.py" "$WORK"
test -d "$WORK/stringtie_out/sample1"
test -f "$WORK/stringtie_out/sample1/sample1_e_data.ctab"

echo "==> [2/4] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^analyze'
python "$NATIVE/main.py" --list-commands | grep -q '^check'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证：analyze（monkeypatch Rscript 解析）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from pathlib import Path
from main import BallgownSkill, build_parser

skill = BallgownSkill()
skill._resolve_binary = lambda: "/opt/conda/envs/ballgown/bin/Rscript"
skill.tmpdir = "$WORK"
cmd = skill.build_command(
    "analyze", data_dir="$WORK/stringtie_out", coldata="$WORK/coldata.txt",
    output_prefix="$WORK/ballgown_out", sample_pattern="sample",
    covariate="condition", min_expr=1, threads=8)

assert cmd[0] == "/opt/conda/envs/ballgown/bin/Rscript", cmd
assert cmd[1].endswith(".R"), cmd
script = Path(cmd[1]).read_text()
for token in ("library(ballgown)", "ballgown(dataDir", 'samplePattern = "sample"',
              "pData = pheno_data", "gexpr(bg)", "stattest(bg_filt", 'feature = "gene"',
              'feature = "transcript"', "write.table", "BALLGOWN_OK"):
    assert token in script, f"R 脚本缺少: {token}"
assert ".gene.txt" in script and ".transcript.txt" in script, script
assert 'Sys.setenv(OMP_NUM_THREADS = "8"' in script, script
print("  OK:", " ".join(cmd))

# 线程优先级：--threads > per_subcommand_threads > default_cpus
def threads_used(**extra):
    s = BallgownSkill(); s._resolve_binary = lambda: "Rscript"; s.tmpdir = "$WORK"
    c = s.build_command("analyze", data_dir="$WORK/stringtie_out",
                        coldata="$WORK/coldata.txt", output_prefix="$WORK/bo", **extra)
    return Path(c[1]).read_text()

s_default = BallgownSkill(); s_default.tmpdir = "$WORK"
expected_default = s_default._effective_threads("analyze", None)
assert f'Sys.setenv(OMP_NUM_THREADS = "{expected_default}"' in threads_used(), "缺省应取 per_subcommand/默认"
assert 'Sys.setenv(OMP_NUM_THREADS = "3"' in threads_used(threads=3), "--threads 应优先"
print("  OK: 线程优先级 --threads > per_subcommand_threads > default_cpus")

ns = build_parser().parse_args(
    ["analyze", "$WORK/stringtie_out", "$WORK/coldata.txt",
     "--output-prefix", "$WORK/bo", "--sample-pattern", "sample",
     "--covariate", "condition", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "analyze" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
assert ns.output_prefix == "$WORK/bo" and ns.covariate == "condition", ns
print("  OK: parser analyze")
PY

echo "==> [4/4] argv 构造验证：check（library 校验走 Rscript -e）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BallgownSkill
skill = BallgownSkill()
skill._resolve_binary = lambda: "Rscript"
cmd = skill.build_command("check")
assert cmd[0] == "Rscript" and cmd[1] == "-e", cmd
assert 'library(ballgown)' in cmd[2] and 'packageVersion("ballgown")' in cmd[2], cmd
print("  OK:", " ".join(cmd[:2]), cmd[2][:60] + "...")
PY

echo "ALL TESTS PASSED"
