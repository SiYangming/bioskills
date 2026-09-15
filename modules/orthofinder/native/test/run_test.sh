#!/usr/bin/env bash
# orthofinder native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - orthofinder 二进制【可选】：未安装时全部退化为「python 构造 argv 验证命令构建」
#     断言（monkeypatch 二进制解析），不实际运行全流程（需真实蛋白组/比对依赖）。
# 覆盖：run（默认 diamond + -t/-a 线程）/ run（msa + -A/-T/-I/-d/--only）/ resume / help
#      / parser / 缺二进制报错。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（多物种蛋白 FASTA 目录）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/input_proteins/speciesA.fasta"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --list-commands | grep -q '^resume'
python "$NATIVE/main.py" --list-commands | grep -q '^help'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证：run（默认 diamond + -t/-a 线程）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthofinderSkill

skill = OrthofinderSkill()
skill._resolve_binary = lambda: "/opt/orthofinder/bin/orthofinder"

# 默认：search=diamond（-S diamond），线程注入 -t 与 -a（per_subcommand.run=8）
cmd = skill.build_command("run", proteomes_dir="$WORK/input_proteins")
s = " ".join(cmd)
assert s.startswith("/opt/orthofinder/bin/orthofinder "), s
assert "-f $WORK/input_proteins" in s, s
assert "-S diamond" in s, s
assert "-t 8" in s and "-a 8" in s, s
print("  OK:", s)

# 显式线程优先于 per_subcommand
cmd = skill.build_command("run", proteomes_dir="$WORK/input_proteins", threads=16)
s = " ".join(cmd)
assert "-t 16" in s and "-a 16" in s, s
print("  OK:", s)

# 输出目录 + 结果名
cmd = skill.build_command("run", proteomes_dir="$WORK/input_proteins",
                          output_dir="$WORK/results", name="run1", threads=4)
s = " ".join(cmd)
assert "-o $WORK/results" in s, s
assert "-n run1" in s, s
print("  OK:", s)
PY

echo "==> [4/7] argv 构造验证：run（msa + -A/-T/-I/-d/--only/extra）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthofinderSkill

skill = OrthofinderSkill()
skill._resolve_binary = lambda: "orthofinder"

cmd = skill.build_command(
    "run", proteomes_dir="$WORK/input_proteins", search="blast", method="msa",
    inflation=1.5, msa_program="mafft", tree_program="fasttree",
    species_tree="$WORK/tree.nwk", orthoxml="$WORK/xml.txt", dna=True,
    only="og", threads=4,
)
s = " ".join(cmd)
for frag in ("-S blast", "-M msa", "-I 1.5", "-A mafft", "-T fasttree",
             "-s $WORK/tree.nwk", "-x $WORK/xml.txt", "-d", "-og", "-t 4", "-a 4"):
    assert frag in s, (frag, s)
print("  OK:", s)

# 非法 --only
try:
    skill.build_command("run", proteomes_dir="$WORK/input_proteins", only="bogus")
    raise AssertionError("非法 only 应报错")
except RuntimeError:
    pass
print("  OK: 非法 only 报错")
PY

echo "==> [5/7] argv 构造验证：resume（-b 续跑）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthofinderSkill

skill = OrthofinderSkill()
skill._resolve_binary = lambda: "orthofinder"

cmd = skill.build_command("resume", previous_results_dir="$WORK/prev_results", threads=8)
s = " ".join(cmd)
assert "-b $WORK/prev_results" in s, s
assert "-S diamond" in s, s
assert "-t 8" in s and "-a 8" in s, s
print("  OK:", s)

# 新增物种目录（-f）一并带上
cmd = skill.build_command("resume", previous_results_dir="$WORK/prev_results",
                          proteomes_dir="$WORK/input_proteins", threads=4)
s = " ".join(cmd)
assert "-b $WORK/prev_results" in s and "-f $WORK/input_proteins" in s, s
print("  OK:", s)

# help
assert skill.build_command("help") == ["orthofinder", "-h"]
print("  OK: help")
PY

echo "==> [6/7] parser 解析 + 运行时校验（缺必填 / 未知子命令 / 缺二进制）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthofinderSkill, build_parser

ns = build_parser().parse_args(
    ["run", "-f", "$WORK/input_proteins", "-t", "8", "-S", "diamond",
     "-M", "dendroblast", "--only", "og", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.proteomes_dir == "$WORK/input_proteins"
assert ns.threads == 8 and ns.search == "diamond" and ns.method == "dendroblast"
assert ns.only == "og" and ns.tmpdir == "/tmp", ns

ns = build_parser().parse_args(["resume", "$WORK/prev_results", "--threads", "4"])
assert ns.subcommand == "resume" and ns.previous_results_dir == "$WORK/prev_results"
assert ns.threads == 4
print("  OK: parser run / resume")

skill = OrthofinderSkill()
skill._resolve_binary = lambda: "orthofinder"
for sub, kw in (("run", dict()),                       # 缺 -f
                ("resume", dict())):                   # 缺 -b
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("应抛 RuntimeError: %s" % sub)
    except RuntimeError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
# 真实缺二进制（无 monkeypatch）→ 明确报错
clean = OrthofinderSkill()
try:
    clean.build_command("run", proteomes_dir="x")
    raise AssertionError("缺 orthofinder 二进制应抛 RuntimeError")
except RuntimeError as e:
    assert "未找到可执行文件" in str(e), e
print("  OK: 运行时参数校验")
PY

echo "==> [7/7] orthofinder 冒烟（若已安装）"
if command -v orthofinder >/dev/null 2>&1; then
    orthofinder -h 2>&1 | head -n 2 || true
else
    echo "  orthofinder 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
