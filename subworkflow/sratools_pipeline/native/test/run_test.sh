#!/usr/bin/env bash
# sratools_pipeline 档案静态自检（不真实下载/转换）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SH="$HERE/../sra_pipeline.sh"

echo "==> [1/3] bash -n sra_pipeline.sh"
bash -n "$PIPELINE_SH"
echo "  OK"

echo "==> [2/3] --help 自检"
"$PIPELINE_SH" --help | grep -q "download" || { echo "[FAIL] --help 缺 download"; exit 1; }
"$PIPELINE_SH" --help | grep -q "convert" || { echo "[FAIL] --help 缺 convert"; exit 1; }
echo "  OK"

echo "==> [3/3] yaml 可解析 + 占位列表可生成"
python3 -c "import yaml; yaml.safe_load(open('$HERE/../../sratools_pipeline.yaml'))"
python3 "$HERE/generate_data.py" "$(mktemp -d)" >/dev/null
echo "  OK"

echo "ALL TESTS PASSED"
