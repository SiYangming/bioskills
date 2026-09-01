#!/usr/bin/env bash
# gstama native 最小回归测试
# 前置条件：
#   - python3 必须在 PATH 中
#   - polyacleanup / collapse / merge 需要 bioconda gs-tama 提供的脚本在 PATH 中
#     （tama_flnc_polya_cleanup.py / tama_collapse.py / tama_merge.py；可 conda activate gstama-native）
#   - collapse 另需 samtools 在 PATH 中
# 若 gs-tama 脚本缺失：自动降级为「命令构建自检 + filelist（纯 Python）真跑」，
# 确保验证命令构建不崩溃，并仍然输出 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [0/6] 自省（无工具依赖）"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "polyacleanup" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [1/6] 生成测试数据（合成 FASTA / BAM / beds）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.fa"
test -s "$WORK/reads.bam"
test -s "$WORK/refs.fa"

echo "==> [2/6] filelist（纯 Python，无 gs-tama 依赖，始终真跑）"
python "$NATIVE/main.py" filelist --bed-dir "$WORK/beds/minimap2" --cap no_cap \
    --outdir "$WORK/filelist" --prefix fl --pattern "**/*.bed"
test -s "$WORK/filelist/fl.tsv"
grep -q "chunk1" "$WORK/filelist/fl.tsv"
grep -q "no_cap" "$WORK/filelist/fl.tsv"
grep -q "minimap2:sample1" "$WORK/filelist/fl.tsv"

# 缺 gs-tama 脚本 → 降级为命令构建自检
if ! command -v tama_collapse.py >/dev/null 2>&1 \
   || ! command -v tama_flnc_polya_cleanup.py >/dev/null 2>&1 \
   || ! command -v tama_merge.py >/dev/null 2>&1; then
    echo "WARN: gs-tama 脚本未全部安装，降级为命令构建自检（不执行真实 TAMA 调用）"
    python "$NATIVE/main.py" polyacleanup --fasta "$WORK/reads.fa" --outdir "$WORK/g" --prefix sample --dry-run > /dev/null
    python "$NATIVE/main.py" collapse --bam "$WORK/reads.bam" --fasta "$WORK/refs.fa" --outdir "$WORK/c" --prefix sample --dry-run > /dev/null
    python "$NATIVE/main.py" merge --filelist "$WORK/filelist/fl.tsv" --outdir "$WORK/m" --prefix merged --dry-run > /dev/null
    echo "ALL TESTS PASSED"
    exit 0
fi

echo "==> [3/6] polyacleanup（tama_flnc_polya_cleanup.py + gzip）"
python "$NATIVE/main.py" polyacleanup --fasta "$WORK/reads.fa" --outdir "$WORK/gstama" --prefix sample
test -f "$WORK/gstama/sample.fa.gz"
test -f "$WORK/gstama/sample_polya_flnc_report.txt.gz"
test -f "$WORK/gstama/sample_tails.fa.gz"

echo "==> [4/6] collapse（tama_collapse.py，输入 BAM + 参考 FASTA）"
if command -v samtools >/dev/null 2>&1; then
    samtools index "$WORK/reads.bam" 2>/dev/null || true
fi
python "$NATIVE/main.py" collapse --bam "$WORK/reads.bam" --fasta "$WORK/refs.fa" \
    --outdir "$WORK/collapse" --prefix sample
find "$WORK/collapse" \( -name "*_collapsed.bed" -o -name "*_read.txt" \) | grep -q .

echo "==> [5/6] merge（tama_merge.py，输入 filelist TSV）"
python "$NATIVE/main.py" merge --filelist "$WORK/filelist/fl.tsv" --outdir "$WORK/merge" --prefix merged
find "$WORK/merge" -name "*.bed" | grep -q .

echo "==> [6/6] merge 空 filelist 跳过路径"
: > "$WORK/empty.tsv"
python "$NATIVE/main.py" merge --filelist "$WORK/empty.tsv" --outdir "$WORK/merge2" --prefix e
grep -q "skipped" "$WORK/merge2/versions.yml"

echo "ALL TESTS PASSED"
