#!/usr/bin/env bash
# blast2go native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）+ perl（占位脚本用）
#   - Java / Blast2GO 发行包【可选】：若宿主已装 java，会额外做 java -version 冒烟；
#     否则跳过真实执行。
# 说明：Blast2GO / b2g4pipe 需真实 BLAST XML + MySQL 注释库 + Java 才能产出结果，合成数据
#      无法覆盖真实计算，因此三个子命令采用「python 构造 argv 验证命令构建不崩溃」
#      （monkeypatch java/perl 解析）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试占位数据（BLAST XML / b2g4pipe / 注释库 / 客户端）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/nr.xml" && test -f "$WORK/b2g4pipe/b2gPipe.properties"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - <<PY
import json
d = json.load(open("$WORK/schema.json"))
assert d["title"] == "blast2go", d.get("title")
for k in ("subcommand", "input", "out", "prop", "b2g_dir", "threads", "java_opts"):
    assert k in d["properties"], (k, d["properties"].keys())
print("  OK: schema title/keys")
PY

echo "==> [3/6] annot：b2g4pipe B2GAnnotPipe 命令行构造"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Blast2GOSkill, _ANNOT_MAIN, build_parser
skill = Blast2GOSkill()
skill._resolve_java = lambda: "/usr/bin/java"
cmd = skill.build_command(
    "annot", input="$WORK/nr.xml", out="$WORK/go", b2g_dir="$WORK/b2g4pipe",
)
s = " ".join(cmd)
assert cmd[0] == "/usr/bin/java", cmd
assert "-cp $WORK/b2g4pipe/*:$WORK/b2g4pipe/ext/*" in s, s
assert _ANNOT_MAIN in s and cmd[cmd.index(_ANNOT_MAIN) + 1] == "-in", s
assert "-in $WORK/nr.xml" in s and "-out $WORK/go" in s, s
assert "-prop $WORK/b2g4pipe/b2gPipe.properties" in s, s
assert "-annot" in s and "-dat" in s and "-annex" in s, s
# Java 工具：JAVA_OPTS 透传
assert "JAVA_OPTS" in skill.env_vars and "-Xmx" in skill.env_vars["JAVA_OPTS"], skill.env_vars
print("  OK:", s)

# --java-opts 覆盖 JAVA_OPTS
skill.build_command("annot", input="$WORK/nr.xml", out="$WORK/go",
                    b2g_dir="$WORK/b2g4pipe", java_opts="-Xmx12g")
assert skill.env_vars["JAVA_OPTS"] == "-Xmx12g", skill.env_vars
print("  OK: --java-opts 覆盖 JAVA_OPTS")

# --no-annot/--no-dat/--no-annex 关闭标志
cmd2 = skill.build_command("annot", input="$WORK/nr.xml", out="$WORK/go",
                           b2g_dir="$WORK/b2g4pipe", annot=False, dat=False, annex=False)
s2 = " ".join(cmd2)
assert "-annot" not in s2 and "-dat" not in s2 and "-annex" not in s2, s2
print("  OK: 关闭 annot/dat/annex")

ns = build_parser().parse_args(
    # 注意：JAVA_OPTS 以 '-' 开头，需用 --java-opts=<值> 形式传给 argparse
    ["annot", "-in", "$WORK/nr.xml", "-out", "$WORK/go",
     "--b2g-dir", "$WORK/b2g4pipe", "--java-opts=-Xmx8g", "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "annot" and ns.java_opts == "-Xmx8g" and ns.tmpdir == "/tmp", ns
print("  OK: parser annot（子命令后 --threads/--tmpdir/--java-opts）")
PY

echo "==> [4/6] install_db：install_blast2goDB.sh（cwd=db_home）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Blast2GOSkill, build_parser
skill = Blast2GOSkill()
skill._perl = lambda: "/usr/bin/perl"
cmd = skill.build_command("install_db", db_home="$WORK/blast2go-db")
assert cmd == ["/usr/bin/perl", "$WORK/blast2go-db/install_blast2goDB.sh"], cmd
assert getattr(skill, "_cwd", None) == "$WORK/blast2go-db", skill._cwd
print("  OK:", " ".join(cmd), "cwd=$WORK/blast2go-db")

ns = build_parser().parse_args(["install_db", "--db-home", "$WORK/blast2go-db"])
assert ns.subcommand == "install_db" and ns.db_home == "$WORK/blast2go-db", ns
print("  OK: parser install_db")

# 缺失 install_blast2goDB.sh 应报错
try:
    skill.build_command("install_db", db_home="$WORK")
    raise AssertionError("缺少 install_blast2goDB.sh 应报错")
except RuntimeError:
    pass
print("  OK: 缺脚本校验")
PY

echo "==> [5/6] client：Blast2GO 3.3 启动器 + java 冒烟"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Blast2GOSkill, build_parser
skill = Blast2GOSkill()
cmd = skill.build_command("client", blast2go_home="$WORK/Blast2GO")
assert cmd == ["$WORK/Blast2GO/Blast2GO"], cmd
print("  OK:", " ".join(cmd))
ns = build_parser().parse_args(["client", "--blast2go-home", "$WORK/Blast2GO"])
assert ns.subcommand == "client" and ns.blast2go_home == "$WORK/Blast2GO", ns
print("  OK: parser client")
try:
    skill.build_command("client", blast2go_home="$WORK/nonexistent")
    raise AssertionError("缺少 Blast2GO 启动器应报错")
except RuntimeError:
    pass
print("  OK: 缺启动器校验")
PY
if command -v java >/dev/null 2>&1; then
    java -version 2>&1 | head -n 1
else
    echo "  java 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "==> [6/6] Dockerfile / Apptainer.def 消费用户自备包（静态检查）"
grep -q 'B2G4PIPE_ZIP' "$NATIVE/Dockerfile" && grep -q 'b2g4pipe_v2.5.zip' "$NATIVE/Dockerfile"
grep -q '%files' "$NATIVE/Apptainer.def" && grep -q 'b2g4pipe_v2.5.zip' "$NATIVE/Apptainer.def"
echo "  OK: 容器配方消费用户自备 b2g4pipe 发行包（无伪造链接）"

echo "ALL TESTS PASSED"
