#!/usr/bin/env bash
# isoseq3 refine 目录批处理：递归查找 DATA_DIR 下 *.bam。
#
# 必填：DATA_DIR  OUT_BASE  PRIMERS
# 可选：CPUS_PER_TASK=4  PARA_CPU  ISOSEQ3_BIN  REFINE_ARGS  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/isoseq3_refine.py}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"
: "${REFINE_ARGS:=--require-polya}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... PRIMERS=primers.fa [CPUS_PER_TASK=4] [PARA_CPU=N] [ISOSEQ3_BIN=...] \\
       bash modules/isoseq3/native/batch_refine.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
if [[ -z "${PRIMERS:-}" || ! -f "$PRIMERS" ]]; then
  echo "[ERROR] PRIMERS required" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

CMD_FILE="${CMD_FILE:-${OUT_BASE}/refine_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

while IFS= read -r -d '' bam; do
  sample_dir="$(basename "$(dirname "$bam")")"
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd=("$PYTHON" "$WRAPPER" --bam "$bam" --primers "$PRIMERS" --outdir "$outdir" \
    --cpus "$CPUS_PER_TASK")
  [[ -n "$REFINE_ARGS" ]] && cmd+=(--args "$REFINE_ARGS")
  [[ -n "${ISOSEQ3_BIN:-}" ]] && cmd+=(--isoseq3-bin "$ISOSEQ3_BIN")
  printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
  printf '\n' >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f -name '*.bam' -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no *.bam under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] isoseq3 refine batch done → $OUT_BASE"
