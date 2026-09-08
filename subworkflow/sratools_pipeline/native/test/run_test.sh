#!/usr/bin/env bash
# sratools_pipeline 编排最小回归测试（--list-stages / dry-run 形态断言，不真实下载/转换）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$HERE/../main.py"
PIPELINE_SH="$HERE/../sra_pipeline.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 语法检查与 --list-stages"
python3 -m py_compile "$MAIN"
bash -n "$PIPELINE_SH"
OUT=$(python3 "$MAIN" --list-stages)
echo "$OUT" | grep -q "sra_prefetch" || { echo "[FAIL] stages 缺 sra_prefetch"; exit 1; }
echo "$OUT" | grep -q "sra_to_fastq" || { echo "[FAIL] stages 缺 sra_to_fastq"; exit 1; }
echo "  OK"

echo "==> [2/7] 依赖文件在位"
for f in "$MAIN" "$PIPELINE_SH" "$HERE/generate_data.py" \
         "$HERE/../../sratools_pipeline.md" "$HERE/../../meta.yaml"; do
    test -f "$f" || { echo "[FAIL] 缺少 $f"; exit 1; }
done
test -f "$HERE/../../../../modules/sra-tools/native/main.py" \
    || { echo "[FAIL] 缺 modules/sra-tools/native/main.py"; exit 1; }
echo "  OK"

echo "==> [3/7] dry-run（默认 fasterq-dump）委托命令断言"
python3 "$HERE/generate_data.py" "$WORK" >/dev/null
OUT=$(python3 "$MAIN" --srr-list "$WORK/SRR_Acc_List.txt")
echo "$OUT" | grep -q "sra-tools/native/main.py prefetch" || { echo "[FAIL] 缺 prefetch 委托"; exit 1; }
echo "$OUT" | grep -q -- "--prefetch-options -f yes -t http" || { echo "[FAIL] 缺 prefetch 默认选项"; exit 1; }
echo "$OUT" | grep -q "sra-tools/native/main.py fasterq-dump" || { echo "[FAIL] 缺 fasterq-dump 委托"; exit 1; }
echo "$OUT" | grep -q -- "--split-3" || { echo "[FAIL] 缺 --split-3"; exit 1; }
echo "$OUT" | grep -q -- "--gzip" || { echo "[FAIL] 缺 --gzip"; exit 1; }
echo "$OUT" | grep -q "SRR10000002" || { echo "[FAIL] 未覆盖全部 accession"; exit 1; }
echo "  OK"

echo "==> [4/7] dry-run（fastq-dump + --no-gzip + 自定义目录）断言"
OUT=$(python3 "$MAIN" --srr-list "$WORK/SRR_Acc_List.txt" \
    --dump-method fastq-dump --no-gzip --download-dir "$WORK/sra" --fastq-dir "$WORK/fq")
echo "$OUT" | grep -q "sra-tools/native/main.py fastq-dump" || { echo "[FAIL] 缺 fastq-dump 委托"; exit 1; }
if echo "$OUT" | grep -q -- "--gzip"; then
    echo "[FAIL] --no-gzip 后仍出现 --gzip"; exit 1
fi
echo "$OUT" | grep -q "$WORK/sra" || { echo "[FAIL] 缺 download-dir 传递"; exit 1; }
echo "$OUT" | grep -q "$WORK/fq" || { echo "[FAIL] 缺 fastq-dir 传递"; exit 1; }
echo "  OK"

echo "==> [5/7] dry-run（PE 无依赖 + .sra 缺失告警不阻断）"
OUT=$(python3 "$MAIN" --srr-list "$WORK/SRR_Acc_List.txt" --download-dir "$WORK/nonexistent_sra" 2>&1 || true)
echo "$OUT" | grep -q "sra_to_fastq:SRR10000001" || { echo "[FAIL] dump stage 缺 accession 标注"; exit 1; }
echo "$OUT" | grep -q "warn" || { echo "[FAIL] 缺 .sra 缺失告警"; exit 1; }
echo "  OK"

echo "==> [6/7] 经典脚本 help 自检（无外部依赖）"
"$PIPELINE_SH" --help | grep -q "download" || { echo "[FAIL] sra_pipeline.sh --help 缺子命令说明"; exit 1; }
echo "  OK"

echo "==> [7/7] meta.yaml YAML 解析"
python3 -c "import yaml,sys; yaml.safe_load(open('$HERE/../../meta.yaml')); print('  OK: meta.yaml 解析通过')"

echo "ALL TESTS PASSED"
