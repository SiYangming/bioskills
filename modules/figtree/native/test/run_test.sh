#!/usr/bin/env bash
# figtree native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - java【可选】：FigTree 为 GUI 工具，export 需图形栈且 jar 未必安装；本测试对 export/view
#     采用「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch 二进制/jar 解析）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（Newick/NEXUS 树占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q '^export' "$WORK/commands.txt"
grep -q '^view' "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：export（无界面导出 PDF / PNG）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FigtreeSkill, build_parser
skill = FigtreeSkill()
skill._resolve_binary = lambda: "/opt/jdk/bin/java"
skill._resolve_jar = lambda: "/opt/FigTree_v1.4.4/lib/figtree.jar"

cmd = skill.build_command("export", input="$WORK/tree.nwk", output="$WORK/tree.pdf", graphic="PDF")
s = " ".join(cmd)
assert "/opt/jdk/bin/java" in s, s
assert "-Xmx2g" in s, s                               # JAVA_OPTS 透传
assert "-Djava.awt.headless=true" in s, s             # 无界面导出
assert "-jar /opt/FigTree_v1.4.4/lib/figtree.jar" in s, s
assert "-graphic PDF" in s, s
assert "$WORK/tree.nwk" in s and "$WORK/tree.pdf" in s, s
print("  OK:", s)

cmd2 = skill.build_command(
    "export", input="$WORK/tree.nex", output="$WORK/tree.png",
    graphic="PNG", width=320, height=320,
)
s2 = " ".join(cmd2)
assert "-graphic PNG" in s2 and "-width 320" in s2 and "-height 320" in s2, s2
print("  OK:", s2)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["export", "$WORK/tree.nwk", "$WORK/o.svg", "-graphic", "SVG",
     "--width", "800", "--threads", "1", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "export" and ns.graphic == "SVG" and ns.threads == 1, ns
print("  OK: parser export")
PY

echo "==> [4/5] argv 构造验证 #2：view（交互式 GUI，不注入 headless）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FigtreeSkill, build_parser
skill = FigtreeSkill()
skill._resolve_binary = lambda: "java"
skill._resolve_jar = lambda: "$WORK/fake/lib/figtree.jar"
cmd = skill.build_command("view", input="$WORK/tree.nwk")
s = " ".join(cmd)
assert "-jar $WORK/fake/lib/figtree.jar" in s, s
assert "-Djava.awt.headless=true" not in s, s          # view 需显示环境
assert s.endswith("$WORK/tree.nwk"), s
print("  OK:", s)
ns = build_parser().parse_args(["view", "$WORK/tree.nwk", "--url"])
assert ns.subcommand == "view" and ns.url is True, ns
print("  OK: parser view")
PY

echo "==> [5/5] java/figtree 冒烟（若已安装；不强制导出）"
if command -v java >/dev/null 2>&1; then
    java -version 2>&1 | head -n 1
else
    echo "  java 未安装，跳过（argv 构造验证已通过）"
fi
if command -v figtree >/dev/null 2>&1; then
    figtree -help 2>&1 | head -n 2
else
    echo "  figtree 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
