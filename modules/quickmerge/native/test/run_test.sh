#!/usr/bin/env bash
# quickmerge native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - quickmerge / nucmer / delta-filter【可选】：若已安装（conda 环境 / 容器），会额外做
#     quickmerge -h 冒烟；否则仅做 argv 构造断言。
# 说明：quickmerge 合并两个组装需要完整基因组，合成数据无法覆盖真实计算，因此四个子命令采用
#      「python 构造 argv 验证命令构建不崩溃」的断言方式（monkeypatch _resolve_binary，不依赖工具已安装）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for c in nucmer para_nucmer delta_filter quickmerge; do
    grep -q "^$c" "$WORK/commands.txt"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：nucmer / para_nucmer"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import QuickmergeSkill, build_parser
skill = QuickmergeSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'quickmerge'}"

cmd = skill.build_command("nucmer", reference="$WORK/ref.fasta", query="$WORK/qry.fasta",
                          prefix="out", min_cluster=200, threads=8)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/nucmer", s
assert "-p out" in s and "-c 200" in s and "--threads 8" in s, s
assert s.endswith("$WORK/ref.fasta $WORK/qry.fasta"), s
print("  OK:", s)

cmd = skill.build_command("para_nucmer", reference="$WORK/ref.fasta", query="$WORK/qry.fasta",
                          cpu=8, nucmer_args=" -p out -l 100")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/para_nucmer", s
assert "--CPU 8" in s and "--nucmer" in s and "-p out -l 100" in s, s
assert s.endswith("$WORK/ref.fasta $WORK/qry.fasta"), s
print("  OK:", s)

ns = build_parser().parse_args(["nucmer", "$WORK/ref.fasta", "$WORK/qry.fasta",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "nucmer" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser nucmer")
PY

echo "==> [4/5] argv 构造验证 #2：delta_filter / quickmerge"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import QuickmergeSkill, build_parser
skill = QuickmergeSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'quickmerge'}"

cmd = skill.build_command("delta_filter", delta="$WORK/out.delta",
                          min_similarity=95, filter_ref=True, filter_query=True)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/delta-filter", s
assert "-i 95" in s and "-r" in s and "-q" in s and s.endswith("$WORK/out.delta"), s
print("  OK:", s)

cmd = skill.build_command("quickmerge", delta="$WORK/out.rq.delta",
                          query="$WORK/qry.fasta", reference="$WORK/ref.fasta",
                          hco=5.0, coverage=1.5, min_length=100000, min_overlap=5000, prefix="out")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/quickmerge", s
assert "-d $WORK/out.rq.delta" in s, s
assert "-q $WORK/qry.fasta" in s and "-r $WORK/ref.fasta" in s, s
assert "-hco 5.0" in s and "-c 1.5" in s, s
assert "-l 100000" in s and "-ml 5000" in s and "-p out" in s, s
print("  OK:", s)

# parser 可解析完整 argv
ns = build_parser().parse_args(["quickmerge", "-d", "$WORK/out.rq.delta", "-q", "$WORK/qry.fasta",
                                "-r", "$WORK/ref.fasta", "-hco", "5.0", "-c", "1.5",
                                "-l", "100000", "-ml", "5000", "-p", "out", "--threads", "4"])
assert ns.subcommand == "quickmerge" and ns.hco == 5.0 and ns.coverage == 1.5, ns
print("  OK: parser quickmerge")

# 线程优先级：用户显式 > per_subcommand_threads
assert skill._effective_threads("nucmer", 12) == 12
assert skill._effective_threads("nucmer", None) == 8
print("  OK: 线程优先级")
PY

echo "==> [5/5] quickmerge 冒烟（若已安装）"
if command -v quickmerge >/dev/null 2>&1; then
    quickmerge -h 2>&1 | head -n 3 || true
    echo "  OK: quickmerge 可调用"
else
    echo "  quickmerge 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
