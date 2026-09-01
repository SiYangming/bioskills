#!/usr/bin/env bash
# gnu_sort native 最小回归测试
# 前置：sort 与 python3 已在 PATH 中（GNU coreutils 或 macOS BSD sort 均可）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
SKILLS_ROOT="$(dirname "$(dirname "$NATIVE")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 GTF/SAM/文本）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] sort: SAM 排序（默认输出 <input>.sorted）"
python3 "$NATIVE/main.py" sort "$WORK/reads.sam"
test -f "$WORK/reads.sam.sorted"
grep -q "^@HD" "$WORK/reads.sam.sorted"
# SAM 按坐标排序后 read1 应在 read2 之前
first_aln="$(grep -v '^@' "$WORK/reads.sam.sorted" | head -n1 | cut -f1)"
test "$first_aln" = "read1"

echo "==> [3/5] sort: GTF 排序 --args '-k1,1 -k4,4n' -o 指定输出"
python3 "$NATIVE/main.py" sort "$WORK/genes.gtf" --args "-k1,1 -k4,4n" -o "$WORK/genes.sorted.gtf"
test -f "$WORK/genes.sorted.gtf"
grep -q 'transcript_id "t1"' "$WORK/genes.sorted.gtf"
# 数值列排序断言：chr2(501) 应排在 chr1 之后、且 -k4,4n 生效
test "$(grep '^chr2' "$WORK/genes.sorted.gtf" | head -n1 | cut -f4)" = "501"

echo "==> [4/5] sort: 文本 --args '-n -k1' 数值排序"
python3 "$NATIVE/main.py" sort "$WORK/counts.txt" --args "-n -k1" -o "$WORK/counts.sorted.txt"
test -f "$WORK/counts.sorted.txt"
test "$(head -n1 "$WORK/counts.sorted.txt")" = "10"

echo "==> [5/5] 自省：--list-commands 与 --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q "sort"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "ALL TESTS PASSED"
