#!/usr/bin/env bash
# raxml-ng native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - RAxML-NG 二进制【可选】：若已安装（conda activate raxml-ng / PATH 中有 raxml-ng），
#     仅做 `--parse`（快速）真实冒烟并断言 <prefix>.raxml.log / .raxml.rba；否则仅做 argv 构造验证。
# 说明：RAxML-NG 为 CPU 密集工具，--threads 注入（默认 8）；真实建树耗时长，本最小回归不做。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（FASTA 比对 + Newick 树）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：all（--all + --bs-trees + --threads）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RaxmlNgSkill, build_parser
skill = RaxmlNgSkill()
skill._resolve_binary = lambda: "/opt/env/bin/raxml-ng"
cmd = skill.build_command(
    "all", msa="$WORK/sample.fa", model="GTR+G", threads=8, bootstrap_reps=100,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/raxml-ng", s
assert "--all" in s, s
assert "--msa $WORK/sample.fa" in s and "--model GTR+G" in s, s
assert "--threads 8" in s and "--bs-trees 100" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["all", "--msa", "$WORK/sample.fa", "--model", "GTR+G", "--bs-trees", "100",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "all" and ns.bootstrap_reps == 100, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser all")
PY

echo "==> [4/5] argv 构造验证：search / evaluate / parse / version（--tree + 线程优先级）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RaxmlNgSkill
skill = RaxmlNgSkill()
skill._resolve_binary = lambda: "raxml-ng"

se = skill.build_command("search", msa="$WORK/sample.fa", model="GTR+G", threads=4)
s = " ".join(se)
assert "--search" in s and "--threads 4" in s, s
print("  OK:", s)

ev = skill.build_command("evaluate", msa="$WORK/sample.fa", tree="$WORK/sample.nwk",
                         model="GTR+G", threads=4)
s = " ".join(ev)
assert "--evaluate" in s and "--tree $WORK/sample.nwk" in s and "--threads 4" in s, s
print("  OK:", s)

pa = skill.build_command("parse", msa="$WORK/sample.fa")
assert pa == ["raxml-ng", "--parse", "--msa", "$WORK/sample.fa", "--model", "GTR+G"], pa
print("  OK:", " ".join(pa))

# 线程优先级：未显式给线程 → all 取 per_subcommand_threads.all（meta 登记 8）
ml = skill.build_command("all", msa="$WORK/sample.fa", threads=None)
assert " ".join(ml).strip().endswith("--threads 8"), ml
print("  OK: all 默认线程 8（per_subcommand_threads）")

v = skill.build_command("version")
assert v == ["raxml-ng", "--version"], v
print("  OK:", " ".join(v))
PY

echo "==> [5/5] RAxML-NG --parse 真实冒烟（若已安装）"
if command -v raxml-ng >/dev/null 2>&1; then
    # --parse 同样要求 --model（驱动已默认注入 GTR+G）
    python "$NATIVE/main.py" parse --msa "$WORK/sample.fa" --model GTR+G --prefix "$WORK/sample.raxml"
    # 稳定产物：<prefix>.raxml.log 与 <prefix>.raxml.rba（.reduced.phy 仅在位点被压缩时生成，故不作硬断言）
    test -f "$WORK/sample.raxml.raxml.log" || test -f "$WORK/sample.raxml.raxml.rba" \
        || { echo "  未找到 --parse 产物（.raxml.log/.rba）"; exit 1; }
    echo "  OK: --parse 真实执行成功（产物：$(ls "$WORK" | grep sample.raxml | tr '\n' ' '))"
else
    echo "  RAxML-NG 未安装，跳过真实执行（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
