#!/usr/bin/env bash
# gemoma native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - java + GeMoMa jar【可选】：若已安装（conda activate gemoma / GEMOMA_HOME 指向 jar），
#     会额外做 `java -jar GeMoMa-*.jar CLI` 冒烟；否则跳过真实执行。
# 说明：GeMoMa 真实预测需要参考/目标基因组与注释，合成数据无法覆盖真实计算，因此对
#      extractor/pipeline/gaf 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（FASTA/GFF 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：extractor"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeMoMaSkill, build_parser
skill = GeMoMaSkill()
skill._java = lambda: "/opt/jdk/bin/java"
skill._resolve_jar = lambda: "/opt/GeMoMa-1.9/GeMoMa-1.9.jar"
cmd = skill.build_command(
    "extractor", annotation="$WORK/ref.gff", genome="$WORK/ref.fasta",
    proteins="$WORK/ref_proteins.fasta", cds="$WORK/ref_cds.fasta",
)
s = " ".join(cmd)
assert "/opt/jdk/bin/java -jar /opt/GeMoMa-1.9/GeMoMa-1.9.jar CLI Extractor" in s, s
assert "-a $WORK/ref.gff" in s and "-g $WORK/ref.fasta" in s, s
assert "-p $WORK/ref_proteins.fasta" in s and "-c $WORK/ref_cds.fasta" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["extractor", "-a", "$WORK/ref.gff", "-g", "$WORK/ref.fasta",
     "-p", "$WORK/ref_proteins.fasta", "-c", "$WORK/ref_cds.fasta",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "extractor" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser extractor")
PY

echo "==> [4/6] argv 构造验证 #2：pipeline（-t 目标 + 参考 + -o + --threads）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeMoMaSkill
skill = GeMoMaSkill()
skill._java = lambda: "java"
skill._resolve_jar = lambda: "GeMoMa-1.9.jar"
cmd = skill.build_command(
    "pipeline", target="$WORK/target.fasta", annotation="$WORK/ref.gff",
    genome="$WORK/ref.fasta", proteins="$WORK/ref_proteins.fasta",
    cds="$WORK/ref_cds.fasta", output="$WORK/gemoma_output", threads=8,
)
s = " ".join(cmd)
assert "java -jar GeMoMa-1.9.jar CLI GeMoMaPipeline" in s, s
assert "-t $WORK/target.fasta" in s, s
assert "-a $WORK/ref.gff" in s and "-g $WORK/ref.fasta" in s, s
assert "-o $WORK/gemoma_output" in s, s
assert "--threads 8" in s, s
print("  OK:", s)
PY

echo "==> [5/6] argv 构造验证 #3：gaf（-g 输入 + -o 输出）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeMoMaSkill
skill = GeMoMaSkill()
skill._java = lambda: "java"
skill._resolve_jar = lambda: "GeMoMa-1.9.jar"
cmd = skill.build_command(
    "gaf", input="$WORK/predicted.gff", output="$WORK/gemoma.gff3",
)
s = " ".join(cmd)
assert "java -jar GeMoMa-1.9.jar CLI GAF" in s, s
assert "-g $WORK/predicted.gff" in s and "-o $WORK/gemoma.gff3" in s, s
print("  OK:", s)
PY

echo "==> [6/6] GeMoMa 冒烟（若已安装 java + jar）"
JAR="${GEMOMA_JAR:-}"
if [[ -z "$JAR" && -n "${GEMOMA_HOME:-}" ]]; then
    JAR="$(find "$GEMOMA_HOME" -maxdepth 1 -name 'GeMoMa-*.jar' 2>/dev/null | head -1)"
fi
if command -v java >/dev/null 2>&1 && [[ -n "$JAR" && -f "$JAR" ]]; then
    java -jar "$JAR" CLI 2>&1 | head -n 3
else
    echo "  java/GeMoMa jar 未就绪，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
