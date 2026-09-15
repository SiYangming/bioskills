#!/usr/bin/env bash
# cafe native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - cafe / caferror.py【可选】：未安装时退化为 argv 构造 + 生成脚本内容断言（不做真实分析）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（基因家族表 + Newick 树）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^command'
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --list-commands | grep -q '^caferror'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造 + 生成脚本内容验证（monkeypatch 二进制）"
python3 - <<PY
import sys, os
sys.path.insert(0, "$NATIVE")
from main import CafeSkill, build_parser

tree = open("$WORK/tree.nwk").read().strip()
skill = CafeSkill()
skill._resolve_binary = lambda: "/opt/env/bin/cafe"
skill._resolve_caferror = lambda: "/opt/env/bin/caferror.py"

# run：从 --gene-table/--tree 生成脚本并构造 cafe <script>
cmd = skill.build_command(
    "run", gene_table="$WORK/orthomcl2cafe.tab", tree=tree,
    output="$WORK/cafe_command", pvalue=0.01, report="out",
)
assert cmd[0] == "/opt/env/bin/cafe", cmd
assert cmd[1] == "$WORK/cafe_command", cmd
script = open(cmd[1]).read()
assert script.splitlines()[0] == "#!/opt/env/bin/cafe", script
assert "load -i $WORK/orthomcl2cafe.tab" in script, script
# 未显式 --threads → 取 per_subcommand_threads.run = 8
assert "load -i $WORK/orthomcl2cafe.tab -t 8 -p 0.01" in script, script
assert "tree " in script and "lambda -s" in script and "report out" in script, script
assert os.access(cmd[1], os.X_OK), "生成的命令脚本应可执行"
print("  OK:", " ".join(cmd))

# 线程优先级：显式 --threads 4 覆盖 per_subcommand(8)
cmd = skill.build_command(
    "run", gene_table="$WORK/orthomcl2cafe.tab", tree=tree,
    output="$WORK/cafe_command4", threads=4,
)
script = open(cmd[1]).read()
assert " -t 4 -p 0.01" in script, script
print("  OK: --threads 覆盖 -> -t 4")

# caferror：caferror.py -i <script> + -d/-o/-v
cmd = skill.build_command(
    "caferror", command_file="$WORK/cafe_command",
    tmp_dir="$WORK/caferror_1", err_output="$WORK/err.txt", verbose=True,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/caferror.py", s
assert cmd[1:3] == ["-i", "$WORK/cafe_command"], s
assert "-d $WORK/caferror_1" in s and "-o $WORK/err.txt" in s and "-v 1" in s, s
print("  OK:", s)

# caferror：无 --command-file 时用同一参数生成脚本
cmd = skill.build_command(
    "caferror", gene_table="$WORK/orthomcl2cafe.tab", tree=tree,
    script_out="$WORK/cafe_command2", tmp_dir="$WORK/caferror_2",
)
assert cmd[0] == "/opt/env/bin/caferror.py" and cmd[1] == "-i", cmd
assert cmd[2] == "$WORK/cafe_command2" and os.path.exists(cmd[2]), cmd
print("  OK:", " ".join(cmd))

# parser 可解析子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["run", "--command-file", "$WORK/cafe_command",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser run --threads/--tmpdir")
PY

echo "==> [4/5] command 子命令（main 端到端：仅生成脚本、不执行）"
TREE="$(cat "$WORK/tree.nwk")"
python "$NATIVE/main.py" command --gene-table "$WORK/orthomcl2cafe.tab" \
    --tree "$TREE" -o "$WORK/from_main" --threads 6 > "$WORK/from_main.path"
test -f "$WORK/from_main"
grep -q -e "#!/" "$WORK/from_main"
grep -q " -t 6 -p 0.01" "$WORK/from_main"
grep -q "lambda -s" "$WORK/from_main"

echo "==> [5/5] cafe 冒烟（若已安装）"
if command -v cafe >/dev/null 2>&1; then
    cafe --help 2>&1 | head -n 3 || true
else
    echo "  cafe 未安装，跳过真实冒烟（argv/脚本内容验证已通过）"
fi

echo "ALL TESTS PASSED"
