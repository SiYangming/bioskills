#!/usr/bin/env bash
# pbccs 目录批处理：扫描 DATA_DIR/*/*.subreads.bam，按 chunk 调用同目录包装器。
#
# 必填环境变量：
#   DATA_DIR   样本根目录（每样本一子目录，内含 *.subreads.bam）
#   OUT_BASE   输出根目录
# 可选：
#   CHUNK_TOTAL=1  CPUS_PER_TASK=4  PARA_CPU=<auto≤4>
#   CCS_BIN  WRAPPER  CMD_FILE  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/ccs_analysis.py}"
CHUNK_TOTAL="${CHUNK_TOTAL:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... [CHUNK_TOTAL=1] [CPUS_PER_TASK=4] [PARA_CPU=N] [CCS_BIN=...] \\
       bash modules/pbccs/native/batch_ccs.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required (dir of sample subdirs with *.subreads.bam)" >&2
  usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2
  usage; exit 1
fi
if [[ ! -f "$WRAPPER" ]]; then
  echo "[ERROR] wrapper not found: $WRAPPER" >&2
  exit 1
fi

CMD_FILE="${CMD_FILE:-${OUT_BASE}/ccs_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

found=0
shopt -s nullglob
for bam in "$DATA_DIR"/*/*.subreads.bam; do
  found=1
  sample_dir="$(basename "$(dirname "$bam")")"
  for i in $(seq 1 "$CHUNK_TOTAL"); do
    cmd=("$PYTHON" "$WRAPPER" --subreads "$bam" --outdir "$OUT_BASE/$sample_dir" \
      --chunk-num "$i" --chunk-total "$CHUNK_TOTAL" --cpus "$CPUS_PER_TASK")
    [[ -n "${CCS_BIN:-}" ]] && cmd+=(--ccs-bin "$CCS_BIN")
    printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
    printf '\n' >>"$CMD_FILE"
  done
done
shopt -u nullglob

if [[ "$found" -eq 0 ]]; then
  echo "[ERROR] no */*.subreads.bam under $DATA_DIR" >&2
  exit 1
fi

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] pbccs batch done → $OUT_BASE"
