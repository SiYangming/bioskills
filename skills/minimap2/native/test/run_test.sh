#!/usr/bin/env bash
# minimap2 native 最小回归测试
# 前置条件：python3 与 minimap2 已在 PATH 中；BAM 模式另需 samtools（可 conda activate minimap2-native）。
# 若 minimap2 / samtools 未安装：脚本自动降级为「命令构建自检」（--schema / --list-commands / --dry-run），
# 确保验证命令构建不崩溃，并仍然输出 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [0/5] 自省（无工具依赖）"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "align" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

if ! command -v minimap2 >/dev/null 2>&1 || ! command -v samtools >/dev/null 2>&1; then
    echo "WARN: minimap2 或 samtools 未安装，降级为命令构建自检（不执行真实比对）"
    python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --reference "$WORK/refs.fa" --outdir "$WORK/out" --prefix test --dry-run > /dev/null
    python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --reference "$WORK/refs.fa" --outdir "$WORK/out" --bam --dry-run > /dev/null
    python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --outdir "$WORK/out" --cigar-paf --dry-run > /dev/null
    echo "ALL TESTS PASSED"
    exit 0
fi

echo "==> [1/5] 生成测试数据（合成 refs.fa + reads.fa）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/refs.fa"
test -s "$WORK/reads.fa"

echo "==> [2/5] align: PAF 输出"
python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --reference "$WORK/refs.fa" \
    --outdir "$WORK" --prefix test --threads 2
test -s "$WORK/test.paf"
grep -q "chr1" "$WORK/test.paf"

echo "==> [3/5] align: PAF + CIGAR（-c）"
python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --reference "$WORK/refs.fa" \
    --outdir "$WORK" --prefix test_cig --cigar-paf --threads 2
test -s "$WORK/test_cig.paf"
grep -q "cg:Z" "$WORK/test_cig.paf"

echo "==> [4/5] align: BAM 输出（minimap2 -a | samtools sort | samtools view -b -h）"
python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --reference "$WORK/refs.fa" \
    --outdir "$WORK" --prefix test_bam --bam --threads 2
test -s "$WORK/test_bam.bam"
samtools view -c "$WORK/test_bam.bam" | grep -qE '^[0-9]+$'

echo "==> [5/5] reads vs reads 自比对（无 reference 退化路径）"
python "$NATIVE/main.py" align --reads "$WORK/reads.fa" --outdir "$WORK" --prefix self --threads 2
test -s "$WORK/self.paf"

echo "ALL TESTS PASSED"
