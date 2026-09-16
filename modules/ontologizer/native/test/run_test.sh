#!/usr/bin/env bash
# ontologizer native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - java + Ontologizer.jar【可选】：若同时具备（PATH 中有 java 且 ONTOLOGIZER_JAR 可用），
#     会额外做 java -jar Ontologizer.jar -v 冒烟；否则仅做 argv 构造验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（go.obo / GAF / study / population）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：enrich（富集分析参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OntologizerSkill, build_parser
skill = OntologizerSkill()
skill._resolve_binary = lambda: "java"
skill._resolve_jar = lambda sub: "/opt/ontologizer/Ontologizer.jar"
cmd = skill.build_command(
    "enrich", go="$WORK/go.obo", association="$WORK/gene_association.gaf",
    studyset="$WORK/S1_vs_S3_S1_UP.list", population="$WORK/population.list",
    calculation="Parent-Child-Union", mtc="Bonferroni", outdir="$WORK",
)
s = " ".join(cmd)
assert cmd[:3] == ["java", "-Xmx6g", "-Djava.io.tmpdir=/tmp"], cmd
assert "-jar /opt/ontologizer/Ontologizer.jar" in s, s
for frag in ("-g $WORK/go.obo", "-a $WORK/gene_association.gaf",
             "-s $WORK/S1_vs_S3_S1_UP.list", "-p $WORK/population.list",
             "-c Parent-Child-Union", "-m Bonferroni", "-o $WORK"):
    assert frag in s, (frag, s)
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["enrich", "-g", "$WORK/go.obo", "-a", "$WORK/gene_association.gaf",
     "-s", "$WORK/S1_vs_S3_S1_UP.list", "-p", "$WORK/population.list",
     "--threads", "4", "--tmpdir", "$WORK"]
)
assert ns.subcommand == "enrich" and ns.threads == 4 and ns.tmpdir == "$WORK", ns
print("  OK: parser enrich")
PY

echo "==> [4/6] argv 构造验证 #2：gui / 校验与线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OntologizerSkill
skill = OntologizerSkill()
skill._resolve_binary = lambda: "java"
skill._resolve_jar = lambda sub: "/opt/ontologizer/" + ("Ontologizer.jar" if sub == "enrich" else "OntologizerGui.jar")

# gui -> java <opts> -jar OntologizerGui.jar
c = skill.build_command("gui")
assert c == ["java", "-Xmx6g", "-Djava.io.tmpdir=/tmp", "-jar", "/opt/ontologizer/OntologizerGui.jar"], c
print("  OK gui:", " ".join(c))

# 缺必填参数必须报错
try:
    skill.build_command("enrich", go="$WORK/go.obo")
except ValueError as e:
    print("  OK enrich 缺参报错:", e)
else:
    raise AssertionError("enrich 缺参应抛 ValueError")

# 非法 -c / -m 必须报错
try:
    skill.build_command("enrich", go="g", association="a", studyset="s", population="p", calculation="Bad")
except ValueError as e:
    print("  OK 非法 calculation 报错:", e)
else:
    raise AssertionError("非法 calculation 应抛 ValueError")
try:
    skill.build_command("enrich", go="g", association="a", studyset="s", population="p", mtc="Bad")
except ValueError as e:
    print("  OK 非法 mtc 报错:", e)
else:
    raise AssertionError("非法 mtc 应抛 ValueError")

# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("enrich", 4) == 4
assert skill._effective_threads("enrich", None) == 1   # meta per_subcommand_threads.enrich=1
print("  OK threads priority")
PY

echo "==> [5/6] JAVA_OPTS 透传与 --tmpdir 覆盖"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OntologizerSkill
skill = OntologizerSkill()
skill._resolve_binary = lambda: "java"
skill._resolve_jar = lambda sub: "/j.jar"
# 默认 JAVA_OPTS 含 -Xmx6g 与 -Djava.io.tmpdir（{tmpdir} 占位已渲染）
assert "-Xmx6g" in skill.env_vars["JAVA_OPTS"], skill.env_vars
assert "-Djava.io.tmpdir=" in skill.env_vars["JAVA_OPTS"], skill.env_vars
c = skill.build_command("gui")
assert "-Xmx6g" in c and any(x.startswith("-Djava.io.tmpdir=") for x in c), c
print("  OK JAVA_OPTS 透传:", " ".join(c))

# --tmpdir 覆盖后 JAVA_OPTS 的 -Djava.io.tmpdir 应随 tmpdir 变化
skill.tmpdir = "/custom/tmp"
skill.env_vars = skill._render_env_vars(
    (skill.meta.get("optimization", {}) or {}).get("env_vars", {})
)
assert "-Djava.io.tmpdir=/custom/tmp" in skill.env_vars["JAVA_OPTS"], skill.env_vars
print("  OK --tmpdir 覆盖 JAVA_OPTS:", skill.env_vars["JAVA_OPTS"])
PY

echo "==> [6/6] Ontologizer 冒烟（若 java + jar 可用）"
if command -v java >/dev/null 2>&1 && { [[ -n "${ONTOLOGIZER_JAR:-}" && -f "${ONTOLOGIZER_JAR}" ]] || [[ -f "${ONTOLOGIZER_HOME:-/nonexistent}/Ontologizer.jar" ]]; }; then
    JAR="${ONTOLOGIZER_JAR:-${ONTOLOGIZER_HOME}/Ontologizer.jar}"
    java -jar "$JAR" -v 2>&1 | head -n 2 || true
else
    echo "  java 或 Ontologizer.jar 不可用，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
