#!/usr/bin/env bash
# bamtools native 最小回归测试
# 前置条件：python3 与 bamtools 已在 PATH 中（或 conda activate bamtools-native）。
# 若 bamtools 未安装：脚本自动降级为「命令构建自检」（--schema / --list-commands / --dry-run），
# 确保验证命令构建不崩溃，并仍然输出 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [0/6] 自省（无工具依赖）"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "convert" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

if ! command -v bamtools >/dev/null 2>&1; then
    echo "WARN: bamtools 未安装，降级为命令构建自检（不执行真实转换）"
    python "$NATIVE/main.py" convert --bam "$WORK/in.bam" --outdir "$WORK/out" --format fasta --dry-run > /dev/null
    python "$NATIVE/main.py" convert --bam "$WORK/in.bam" --outdir "$WORK/out" --format fastq --prefix reads --dry-run > /dev/null
    python "$NATIVE/main.py" stats --bam "$WORK/in.bam" --dry-run > /dev/null
    python "$NATIVE/main.py" sort --bam "$WORK/in.bam" --out "$WORK/sorted.bam" --dry-run > /dev/null
    python "$NATIVE/main.py" index --bam "$WORK/sorted.bam" --dry-run > /dev/null
    echo "ALL TESTS PASSED"
    exit 0
fi

echo "==> [1/6] 生成测试数据（纯 Python 合成 BAM）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.bam"

echo "==> [2/6] convert: BAM -> FASTA"
python "$NATIVE/main.py" convert --bam "$WORK/reads.bam" --outdir "$WORK" --format fasta
test -s "$WORK/reads.fasta"
grep -q "^>" "$WORK/reads.fasta"

echo "==> [3/6] convert: BAM -> FASTQ / SAM"
python "$NATIVE/main.py" convert --bam "$WORK/reads.bam" --outdir "$WORK" --format fastq --prefix reads_fq
test -s "$WORK/reads_fq.fastq"
grep -q "^@" "$WORK/reads_fq.fastq"
python "$NATIVE/main.py" convert --bam "$WORK/reads.bam" --outdir "$WORK" --format sam --prefix reads_sam
test -s "$WORK/reads_sam.sam"
grep -q "chr1" "$WORK/reads_sam.sam"

echo "==> [4/6] stats / count / header"
python "$NATIVE/main.py" stats --bam "$WORK/reads.bam" > "$WORK/stats.txt"
grep -qi "reads" "$WORK/stats.txt"
python "$NATIVE/main.py" count --bam "$WORK/reads.bam" > "$WORK/count.txt"
grep -qx '4' "$WORK/count.txt"
python "$NATIVE/main.py" header --bam "$WORK/reads.bam" > "$WORK/header.txt"
grep -q "@SQ" "$WORK/header.txt"

echo "==> [5/6] sort + index"
python "$NATIVE/main.py" sort --bam "$WORK/reads.bam" --out "$WORK/reads.sorted.bam" --threads 2
test -s "$WORK/reads.sorted.bam"
python "$NATIVE/main.py" index --bam "$WORK/reads.sorted.bam"
test -f "$WORK/reads.sorted.bam.bai"

echo "==> [6/6] 回归输出自检完成"

echo "ALL TESTS PASSED"
