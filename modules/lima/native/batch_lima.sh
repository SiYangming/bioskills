#!/usr/bin/env bash
# lima 目录批处理：递归查找 DATA_DIR 下 bam/fasta/fastq，调用同目录包装器。
#
# 必填：DATA_DIR  OUT_BASE  PRIMERS
# 可选：CPUS_PER_TASK=4  PARA_CPU  LIMA_BIN  LIMA_ARGS  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/lima_analysis.py}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"
: "${LIMA_ARGS:=--isoseq --peek-guess}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... PRIMERS=primers.fa [CPUS_PER_TASK=4] [PARA_CPU=N] [LIMA_BIN=...] \\
       bash modules/lima/native/batch_lima.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
if [[ -z "${PRIMERS:-}" || ! -f "$PRIMERS" ]]; then
  echo "[ERROR] PRIMERS required (primer FASTA)" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

CMD_FILE="${CMD_FILE:-${OUT_BASE}/lima_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

while IFS= read -r -d '' reads; do
  sample_dir="$(basename "$(dirname "$reads")")"
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd=("$PYTHON" "$WRAPPER" --reads "$reads" --primers "$PRIMERS" --outdir "$outdir" \
    --cpus "$CPUS_PER_TASK")
  [[ -n "$LIMA_ARGS" ]] && cmd+=(--args "$LIMA_ARGS")
  [[ -n "${LIMA_BIN:-}" ]] && cmd+=(--lima-bin "$LIMA_BIN")
  printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
  printf '\n' >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( -name '*.bam' -o -name '*.fasta' -o -name '*.fastq' \
  -o -name '*.fasta.gz' -o -name '*.fastq.gz' \) -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no input reads under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] lima batch done → $OUT_BASE"
