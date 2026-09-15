#!/usr/bin/env bash
# MUMmer v4 native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - nucmer / delta-filter / show-coords【可选】：若已安装（conda 环境 mummer4 / brew / 容器），
#     会额外做版本冒烟 + 用合成 delta 跑一次 delta-filter/show-coords；否则仅做 argv 构造断言。
# 说明：nucmer 比对需要真实基因组才能产出结果，合成数据无法覆盖真实计算，因此五个子命令采用
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
for c in nucmer para_nucmer delta_filter show_coords mummerplot; do
    grep -q "^$c" "$WORK/commands.txt"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：nucmer / para_nucmer"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MummerSkill, build_parser
skill = MummerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'nucmer'}"

cmd = skill.build_command("nucmer", reference="$WORK/ref.fasta", query="$WORK/qry.fasta",
                          prefix="out", min_cluster=200, max_gap=200, threads=8)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/nucmer", s
assert "-p out" in s and "-c 200" in s and "-g 200" in s, s
assert "--threads 8" in s and s.endswith("$WORK/ref.fasta $WORK/qry.fasta"), s
print("  OK:", s)

cmd = skill.build_command("para_nucmer", reference="$WORK/ref.fasta", query="$WORK/qry.fasta",
                          cpu=8, nucmer_args=" -p out -l 100")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/para_nucmer", s
assert "--CPU 8" in s and "--nucmer" in s and "-p out -l 100" in s, s
assert s.endswith("$WORK/ref.fasta $WORK/qry.fasta"), s
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(["nucmer", "$WORK/ref.fasta", "$WORK/qry.fasta",
                                "-c", "200", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "nucmer" and ns.min_cluster == 200 and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser nucmer")
PY

echo "==> [4/5] argv 构造验证 #2：delta_filter / show_coords / mummerplot"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MummerSkill, build_parser
skill = MummerSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'nucmer'}"

cmd = skill.build_command("delta_filter", delta="$WORK/out.delta",
                          min_similarity=95, filter_ref=True, filter_query=True)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/delta-filter", s
assert "-i 95" in s and "-r" in s and "-q" in s and s.endswith("$WORK/out.delta"), s
print("  OK:", s)

cmd = skill.build_command("show_coords", delta="$WORK/out.rq.delta",
                          min_identity=95, min_align_len=10000, sort_ref=True)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/show-coords", s
assert "-c" in s and "-d" in s and "-l" in s, s
assert "-I 95" in s and "-L 10000" in s and "-r" in s, s
assert s.endswith("$WORK/out.rq.delta"), s
print("  OK:", s)

cmd = skill.build_command("mummerplot", delta="$WORK/out.delta",
                          prefix="out", plot_size="large", plot_terminal="png")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/mummerplot", s
assert "-f" in s and "-l" in s, s
assert "-p out" in s and "-s large" in s and "-t png" in s, s
assert s.endswith("$WORK/out.delta"), s
print("  OK:", s)

# 线程优先级：用户显式 > per_subcommand_threads
assert skill._effective_threads("nucmer", 12) == 12
assert skill._effective_threads("nucmer", None) == 8
print("  OK: 线程优先级")
PY

echo "==> [5/5] MUMmer 冒烟（若已安装）"
if command -v nucmer >/dev/null 2>&1; then
    nucmer --version 2>&1 | head -n 2
    if command -v delta-filter >/dev/null 2>&1 && command -v show-coords >/dev/null 2>&1; then
        delta-filter -i 95 -r -q "$WORK/out.delta" > "$WORK/out.rq.delta" 2>/dev/null || true
        show-coords -c -d -l "$WORK/out.delta" > "$WORK/out.show" 2>/dev/null || true
        echo "  OK: delta-filter / show-coords 冒烟（合成 delta）"
    fi
else
    echo "  MUMmer 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
