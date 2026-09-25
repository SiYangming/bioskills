#!/usr/bin/env bash
# gstama polyA cleanup 目录批处理：递归查找 DATA_DIR 下 *.fa / *.fasta。
#
# 必填：DATA_DIR  OUT_BASE
# 可选：ARGS  PARA_CPU  TAMA_SCRIPT  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/tama_polyacleanup.py}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... [ARGS=...] [PARA_CPU=N] [TAMA_SCRIPT=...] \\
       bash modules/gstama/native/batch_polyacleanup.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

CMD_FILE="${CMD_FILE:-${OUT_BASE}/polyacleanup_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

while IFS= read -r -d '' fasta; do
  sample_dir="$(basename "$(dirname "$fasta")")"
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd=("$PYTHON" "$WRAPPER" --fasta "$fasta" --outdir "$outdir")
  [[ -n "${ARGS:-}" ]] && cmd+=(--args "$ARGS")
  [[ -n "${TAMA_SCRIPT:-}" ]] && cmd+=(--tama-script "$TAMA_SCRIPT")
  printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
  printf '\n' >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( -name '*.fa' -o -name '*.fasta' \) -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no *.fa/*.fasta under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] gstama polyacleanup batch done → $OUT_BASE"
