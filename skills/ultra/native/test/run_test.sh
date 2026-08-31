#!/usr/bin/env bash
# ultra native 最小回归测试
# 前置：python3 在 PATH；gunzip/sort 依赖系统 gzip/sort（GNU 或 BSD 均可）；
#       index/align 执行断言需要 uLTRA + minimap2 + namfinder + samtools（未安装则跳过执行断言）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
SKILLS_ROOT="$(dirname "$(dirname "$NATIVE")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成基因组/GTF/reads）"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands 与 --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q "index"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] gunzip: genome.fa.gz -> genome.plain.fa"
python3 "$NATIVE/main.py" gunzip "$WORK/genome.fa.gz" -o "$WORK/genome.plain.fa"
test -f "$WORK/genome.plain.fa"
grep -q "^>chr1" "$WORK/genome.plain.fa"

echo "==> [4/6] sort: GTF 排序（-k1,1 -k4,4n）"
python3 "$NATIVE/main.py" sort "$WORK/genes.gtf" --outdir "$WORK" --prefix genes
test -f "$WORK/genes.sorted.gtf"
grep -q "^chr1" "$WORK/genes.sorted.gtf"

if command -v uLTRA >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 \
   && command -v minimap2 >/dev/null 2>&1 && command -v namfinder >/dev/null 2>&1; then
    echo "==> [5/6] index: uLTRA index (--disable_infer)"
    python3 "$NATIVE/main.py" index "$WORK/genome.fa" "$WORK/genes.sorted.gtf" "$WORK/idx" --args "--disable_infer"
    ls "$WORK"/idx/*.pickle >/dev/null
    ls "$WORK"/idx/*.db >/dev/null

    echo "==> [6/6] align: uLTRA align + samtools sort -> BAM"
    python3 "$NATIVE/main.py" align "$WORK/genome.fa" "$WORK/reads.fa" "$WORK/aln" \
        --index-dir "$WORK/idx" --prefix sample --threads 2
    test -f "$WORK/aln/sample.bam"
    echo "==> ultra index/align 执行断言全部通过"
else
    echo "==> [5-6/6] [SKIP] uLTRA/minimap2/namfinder/samtools 未全部安装，跳过 index/align 执行断言"
    echo "    安装：mamba env create -f environment.yml && conda activate ultra-native"
fi

echo "ALL TESTS PASSED"
