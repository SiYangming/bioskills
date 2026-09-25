#!/usr/bin/env bash
# bamtools convert 目录批处理：递归查找 DATA_DIR 下 *.bam。
#
# 必填：DATA_DIR  OUT_BASE
# 可选：FORMAT=fasta  ARGS  PARA_CPU  BAMTOOLS_BIN  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/bamtools_convert.py}"
FORMAT="${FORMAT:-fasta}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... [FORMAT=fasta] [ARGS=...] [PARA_CPU=N] [BAMTOOLS_BIN=...] \\
       bash modules/bamtools/native/batch_convert.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

CMD_FILE="${CMD_FILE:-${OUT_BASE}/convert_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

while IFS= read -r -d '' bam; do
  sample_dir="$(basename "$(dirname "$bam")")"
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd=("$PYTHON" "$WRAPPER" --bam "$bam" --outdir "$outdir" --format "$FORMAT")
  [[ -n "${ARGS:-}" ]] && cmd+=(--args "$ARGS")
  [[ -n "${BAMTOOLS_BIN:-}" ]] && cmd+=(--bamtools-bin "$BAMTOOLS_BIN")
  printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
  printf '\n' >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f -name '*.bam' -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no *.bam under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] bamtools convert batch done → $OUT_BASE"
