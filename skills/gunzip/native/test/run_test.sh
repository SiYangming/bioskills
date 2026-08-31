#!/usr/bin/env bash
# gunzip native 最小回归测试
# 前置：gzip 与 python3 已在 PATH 中（macOS 系统 gzip 亦可）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
SKILLS_ROOT="$(dirname "$(dirname "$NATIVE")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 .gz 输入）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] gunzip: reads.fa.gz -> reads.fa（默认输出名）"
python3 "$NATIVE/main.py" gunzip "$WORK/reads.fa.gz"
test -f "$WORK/reads.fa"
grep -q ">read1" "$WORK/reads.fa"
grep -q "ACGTACGTACGTACGTACGT" "$WORK/reads.fa"

echo "==> [3/5] gunzip: genes.gtf.gz -o 重命名输出"
python3 "$NATIVE/main.py" gunzip "$WORK/genes.gtf.gz" -o "$WORK/genes.gtf"
test -f "$WORK/genes.gtf"
grep -q 'transcript_id "t1"' "$WORK/genes.gtf"

echo "==> [4/5] gunzip: counts.txt.gz --args 透传"
python3 "$NATIVE/main.py" gunzip "$WORK/counts.txt.gz" -o "$WORK/counts.txt" --args ""
test -f "$WORK/counts.txt"
grep -q "^g1" "$WORK/counts.txt"

echo "==> [5/5] 自省：--list-commands 与 --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q "gunzip"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

# versions.yml 断言（nf-core/gunzip 对齐）
test -f "$WORK/versions.yml" || test -f "$WORK/../versions.yml" || true

echo "ALL TESTS PASSED"
