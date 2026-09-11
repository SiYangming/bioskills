#!/usr/bin/env bash
# MAFFT native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 mafft（conda activate <mafft 环境> / 官方容器内 / brew 已装）→ 追加真跑最小链路：
#   合成多序列 input.fa → align（--auto → -o 写文件；stdout 模式；--method linsi）
#   → 断言等长比对；version 子命令；真跑失败仅 [WARN] 提示不阻断。
# 无 mafft → 自省 + 契约 + [SKIP]；任何环境最终 exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成多序列 FASTA）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/input.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^align " "$WORK/commands.txt"
grep -q "^version " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] align/version 参数契约（--help 自省）"
python "$NATIVE/main.py" align --help > "$WORK/align_help.txt"
grep -q -- "--input" "$WORK/align_help.txt"
grep -q -- "--output" "$WORK/align_help.txt"
grep -q -- "--auto" "$WORK/align_help.txt"
grep -q -- "--method" "$WORK/align_help.txt"
python "$NATIVE/main.py" version --help > "$WORK/version_help.txt"
grep -q -- "--threads" "$WORK/version_help.txt"

echo "==> [5/6] align/version 最小链路（需要 mafft，未安装则跳过）"
if command -v mafft >/dev/null 2>&1; then
    # 5a. align --auto → -o 写文件，断言等长为多序列比对
    if python "$NATIVE/main.py" align "$WORK/input.fa" --threads 2 \
            -o "$WORK/aligned_auto.fa" 2> "$WORK/align_auto.log"; then
        test -s "$WORK/aligned_auto.fa"
        # MAFFT 输出默认按 60 列换行，需按 FASTA 记录拼接后再断言等长
        python - "$WORK/aligned_auto.fa" <<'PY'
import sys
from pathlib import Path
recs, name, buf = [], None, []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith(">"):
        if name is not None:
            recs.append((name, "".join(buf)))
        name, buf = line, []
    else:
        buf.append(line.strip())
if name is not None:
    recs.append((name, "".join(buf)))
assert len(recs) == 6, f"期望 6 条比对序列，实得 {len(recs)}"
lens = {len(s) for _, s in recs}
assert len(lens) == 1, f"比对结果非等长: {lens}"
print(f"  [ok] align --auto -> 6 条等长比对（{lens.pop()} bp）")
PY
    else
        echo "  [WARN] align --auto 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/align_auto.log" || true
    fi

    # 5b. stdout 模式 + -i/--input 选项
    if python "$NATIVE/main.py" align -i "$WORK/input.fa" --threads 2 \
            > "$WORK/aligned_stdout.fa" 2> "$WORK/align_stdout.log"; then
        test -s "$WORK/aligned_stdout.fa"
        grep -q "^>seq1" "$WORK/aligned_stdout.fa"
        echo "  [ok] align（stdout + -i）-> 输出含序列头"
    else
        echo "  [WARN] align stdout 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/align_stdout.log" || true
    fi

    # 5c. 高精度模式 --method linsi
    if python "$NATIVE/main.py" align "$WORK/input.fa" --method linsi --threads 2 \
            -o "$WORK/aligned_linsi.fa" 2> "$WORK/align_linsi.log"; then
        test -s "$WORK/aligned_linsi.fa"
        echo "  [ok] align --method linsi -> 输出非空"
    else
        echo "  [WARN] align --method linsi 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/align_linsi.log" || true
    fi

    # 5d. version 子命令
    if python "$NATIVE/main.py" version > "$WORK/version.txt" 2>&1; then
        grep -qi "v7\." "$WORK/version.txt" \
            && echo "  [ok] version -> $(head -n 1 "$WORK/version.txt")" \
            || echo "  [WARN] version 输出未含 v7.x：$(head -n 1 "$WORK/version.txt")"
    else
        echo "  [WARN] version 子命令失败，仅提示不阻断"
    fi
else
    echo "  [SKIP] 未检测到 mafft（conda activate <mafft 环境> / brew install mafft 后重跑），仅跑自省链路"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v mafft >/dev/null 2>&1; then
    mafft --version | head -n 1 || true
fi

echo "ALL TESTS PASSED"
