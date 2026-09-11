#!/usr/bin/env bash
# hmmer（HMMER 3.x）native 最小回归测试
# 前置：python3 必须在 PATH；若本机装有 hmmbuild/hmmpress/hmmsearch（conda activate
# 或 native/install.sh 安装），则追加跑 hmmbuild→hmmpress→hmmsearch 最小链路，否则跳过
# （自省 + 契约测试必跑）。任何环境下 exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成蛋白 MSA + 序列库）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/family.sto"
test -f "$WORK/proteins.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^hmmbuild " "$WORK/commands.txt"
grep -q "^hmmpress " "$WORK/commands.txt"
grep -q "^hmmsearch " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 子命令参数契约（--threads / --tmpdir 必须存在）"
for sub in hmmbuild hmmpress hmmsearch; do
    python "$NATIVE/main.py" "$sub" --help > "$WORK/help_$sub.txt"
    grep -q -- "--threads" "$WORK/help_$sub.txt"
    grep -q -- "--tmpdir" "$WORK/help_$sub.txt"
done

echo "==> [5/6] hmmbuild→hmmpress→hmmsearch 最小链路（需要 HMMER 3.x，未安装则跳过）"
if command -v hmmbuild >/dev/null 2>&1 \
    && command -v hmmpress >/dev/null 2>&1 \
    && command -v hmmsearch >/dev/null 2>&1; then
    python "$NATIVE/main.py" hmmbuild "$WORK/family.hmm" "$WORK/family.sto" -n teach_family --threads 2
    test -f "$WORK/family.hmm"
    grep -q "HMMER3" "$WORK/family.hmm"

    python "$NATIVE/main.py" hmmpress "$WORK/family.hmm"
    for ext in h3f h3i h3m h3p; do
        test -f "$WORK/family.hmm.$ext"
    done

    python "$NATIVE/main.py" hmmsearch --hmm "$WORK/family.hmm" "$WORK/proteins.fa" \
        --tblout "$WORK/hits.tbl" -E 10 -o "$WORK/search.out" --threads 2
    test -f "$WORK/hits.tbl"
    test -f "$WORK/search.out"
    grep -q "^# target name" "$WORK/hits.tbl"
else
    echo "  [SKIP] 未检测到 hmmbuild/hmmpress/hmmsearch，跳过最小链路（仅跑自省/契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v hmmsearch >/dev/null 2>&1; then
    hmmsearch -h 2>&1 | grep -m1 "HMMER" || true
fi

echo "ALL TESTS PASSED"
