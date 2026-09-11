#!/usr/bin/env bash
# trf（Tandem Repeats Finder）native 最小回归测试
# 前置：python3 必须在 PATH；若本机装有 trf（conda activate <env> 或官方容器内），
# 则追加跑 scan 最小链路（合成小 FASTA → 命中串联重复 → 断言 .dat/.mask/.html），
# 否则跳过（自省与契约测试必跑）。任何环境都必须 exit 0 + ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PREFIX="genome.fa.2.7.7.80.10.50.500"

echo "==> [1/5] 生成测试数据（合成小 FASTA，含串联重复）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.fa"

echo "==> [2/5] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^scan " "$WORK/commands.txt"

echo "==> [3/5] main.py --schema 自省 + 参数契约（默认 7 个位置参数 = 2 7 7 80 10 50 500）"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"
python "$NATIVE/main.py" --help >/dev/null 2>&1 || true
python - "$NATIVE" <<'PY'
import sys, os
from pathlib import Path
native = Path(sys.argv[1])
sys.path.insert(0, str(native.parent.parent))
import importlib.util
spec = importlib.util.spec_from_file_location("trf_main", native / "main.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# 不依赖 trf 二进制：直接校验 build_command 的位置参数与选项顺序（输入路径被解析为绝对路径）
g = os.path.abspath("g.fa")
skill = mod.TrfSkill()
skill._resolve_binary = lambda: "trf"  # 契约测试，绕过可执行文件探测
cmd = skill.build_command("scan", genome_fasta="g.fa", mask=True, data=True, html=True)
assert cmd == ["trf", g, "2", "7", "7", "80", "10", "50", "500", "-m", "-d", "-h"], cmd
cmd2 = skill.build_command("scan", genome_fasta="g.fa",
                           match_weight=2, mismatch_weight=5, indel_weight=7,
                           match_prob=80, indel_prob=10, min_score=50, max_period=2000)
assert cmd2 == ["trf", g, "2", "5", "7", "80", "10", "50", "2000"], cmd2
print("参数契约通过：位置参数顺序与 -m/-d/-h 选项正确")
PY

echo "==> [4/5] main.py scan 最小链路（需要 trf，未安装则跳过）"
if command -v trf >/dev/null 2>&1; then
    python "$NATIVE/main.py" scan "$WORK/genome.fa" -m -d --threads 1
    test -f "$WORK/$PREFIX.dat"
    test -f "$WORK/$PREFIX.mask"
    test -f "$WORK/$PREFIX.1.html"                 # HTML 为 trf 默认产物
    grep -q "Parameters" "$WORK/$PREFIX.dat"       # 数据文件含参数行
    grep -q "Sequence" "$WORK/$PREFIX.dat"         # 数据文件含序列行
    grep -q "N" "$WORK/$PREFIX.mask"               # 屏蔽序列中出现 N

    # -h 语义回归：关闭默认 HTML（trf -h 自动开启 -d）
    mkdir -p "$WORK/nohtml"
    cp "$WORK/genome.fa" "$WORK/nohtml/genome.fa"
    python "$NATIVE/main.py" scan "$WORK/nohtml/genome.fa" -h --threads 1
    test -f "$WORK/nohtml/$PREFIX.dat"
    test ! -f "$WORK/nohtml/$PREFIX.1.html"
else
    echo "  [SKIP] 未检测到 trf，跳过 scan 真实链路（自省与参数契约已跑）"
fi

echo "==> [5/5] 版本探测（可选信息；注意上游常规模式成功退出码为 1，不代表失败）"
if command -v trf >/dev/null 2>&1; then
    trf -v 2>&1 | head -n 2 || true
fi

echo "ALL TESTS PASSED"
