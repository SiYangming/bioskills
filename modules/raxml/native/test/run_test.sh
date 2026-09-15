#!/usr/bin/env bash
# raxml native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - RAxML 二进制【可选】：若已安装（conda activate raxml / PATH 中有 raxmlHPC-PTHREADS-SSE3），
#     仅做 `-v` 版本冒烟（真实建树耗时长，本最小回归不做）；否则仅做 argv 构造验证。
# 说明：RAxML 为 CPU 密集工具，--threads 注入 -T（默认 8）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（relaxed Phylip 比对）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：ml_bootstrap（14.md 密码子模型命令）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RaxmlSkill, build_parser
skill = RaxmlSkill()
skill._resolve_binary = lambda: "/opt/env/bin/raxmlHPC-PTHREADS-SSE3"
cmd = skill.build_command(
    "ml_bootstrap", msa="$WORK/sample.phy", model="GTRGAMMA", name="out_codon",
    bootstrap_seed=12345, parsimony_seed=12345, bootstrap_reps=100, threads=8,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/raxmlHPC-PTHREADS-SSE3", s
assert "-f a" in s, s
assert "-x 12345" in s and "-p 12345" in s and "-# 100" in s, s
assert "-m GTRGAMMA" in s and "-s $WORK/sample.phy" in s and "-n out_codon" in s, s
assert "-T 8" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["ml_bootstrap", "-s", "$WORK/sample.phy", "-m", "PROTGAMMAILGX",
     "-n", "out_protein", "-#", "100", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "ml_bootstrap", ns
assert ns.model == "PROTGAMMAILGX" and ns.bootstrap_reps == 100, ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser ml_bootstrap")
PY

echo "==> [4/5] argv 构造验证：ml_search / version / 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import RaxmlSkill
skill = RaxmlSkill()
skill._resolve_binary = lambda: "raxmlHPC-PTHREADS-SSE3"

cmd = skill.build_command("ml_search", msa="$WORK/sample.phy",
                          model="PROTGAMMAILGX", name="out_protein", threads=None)
s = " ".join(cmd)
assert "-f d" in s, s
assert "-p 12345" in s and "-m PROTGAMMAILGX" in s, s
# 未显式给线程 → 取 per_subcommand_threads.ml_search（meta 登记 8）
assert s.strip().endswith("-T 8"), s
print("  OK:", s)

cmd2 = skill.build_command("ml_search", msa="$WORK/sample.phy", threads=3)
assert " ".join(cmd2).strip().endswith("-T 3"), cmd2
print("  OK: 线程优先级 --threads=3 覆盖默认")

v = skill.build_command("version")
assert v == ["raxmlHPC-PTHREADS-SSE3", "-v"], v
print("  OK:", " ".join(v))
PY

echo "==> [5/5] RAxML 版本冒烟（若已安装，仅 -v）"
if command -v raxmlHPC-PTHREADS-SSE3 >/dev/null 2>&1; then
    raxmlHPC-PTHREADS-SSE3 -v 2>&1 | head -n 2 || true
else
    echo "  RAxML 未安装，跳过版本冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
