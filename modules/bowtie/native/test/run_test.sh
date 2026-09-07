#!/usr/bin/env bash
# bowtie（v1）native 最小回归测试
# 前置：python3 必须在 PATH；若本机装有 bowtie/bowtie-build（conda activate bowtie
# 或 native/install.sh 安装），则追加跑 index+align 最小链路，否则跳过（自省测试必跑）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成参考 + reads）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/refs.fa"
test -f "$WORK/reads_se.fq"

echo "==> [2/5] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^index " "$WORK/commands.txt"
grep -q "^align " "$WORK/commands.txt"

echo "==> [3/5] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/5] main.py index/align 最小链路（需要 bowtie，未安装则跳过）"
if command -v bowtie >/dev/null 2>&1 && command -v bowtie-build >/dev/null 2>&1; then
    python "$NATIVE/main.py" index "$WORK/refs.fa" "$WORK/btidx" --threads 2
    test -f "$WORK/btidx.1.ebwt"
    test -f "$WORK/btidx.2.ebwt"
    test -f "$WORK/btidx.rev.2.ebwt"

    python "$NATIVE/main.py" align -x "$WORK/btidx" -1 "$WORK/reads_1.fq" -2 "$WORK/reads_2.fq" \
        -o "$WORK/pe.sam" --threads 2
    test -f "$WORK/pe.sam"
    grep -q "@SQ" "$WORK/pe.sam"

    python "$NATIVE/main.py" align -x "$WORK/btidx" -U "$WORK/reads_se.fq" \
        -o "$WORK/se.sam" --threads 2
    test -f "$WORK/se.sam"
    # 单端 4 条 read 默认报告模式（-k1）每条应输出 1 行比对
    ALIGNED=$(grep -c -v "^@" "$WORK/se.sam")
    test "$ALIGNED" -eq 4
else
    echo "  [SKIP] 未检测到 bowtie / bowtie-build，跳过 index+align（仅跑自省链路）"
fi

echo "==> [5/5] 版本探测（可选信息）"
if command -v bowtie >/dev/null 2>&1; then
    bowtie --version | head -n 1
fi

echo "ALL TESTS PASSED"
