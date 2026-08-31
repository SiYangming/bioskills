#!/usr/bin/env bash
# samtools native 最小回归测试
# 前置：samtools 与 python3 已在 PATH 中（或通过 conda activate samtools-native）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
SKILLS_ROOT="$(dirname "$(dirname "$NATIVE")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 BAM）"
python "$HERE/generate_data.py" "$WORK"
# 产物：$WORK/refs.fa $WORK/reads.sam

echo "==> [2/5] view: SAM -> BAM"
python "$NATIVE/main.py" view "$WORK/reads.sam" -o "$WORK/reads.bam" --output-format BAM --threads 2

echo "==> [3/5] sort + index"
python "$NATIVE/main.py" sort "$WORK/reads.bam" -o "$WORK/reads.sorted.bam" --threads 2
python "$NATIVE/main.py" index "$WORK/reads.sorted.bam"

echo "==> [4/5] flagstat / idxstats"
python "$NATIVE/main.py" flagstat "$WORK/reads.sorted.bam" > "$WORK/flagstat.txt"
python "$NATIVE/main.py" idxstats "$WORK/reads.sorted.bam" > "$WORK/idxstats.txt"

echo "==> [5/5] faidx"
python "$NATIVE/main.py" faidx "$WORK/refs.fa"

# 基本断言
test -f "$WORK/reads.sorted.bam.bai"
grep -q "in total" "$WORK/flagstat.txt"

echo "ALL TESTS PASSED"
