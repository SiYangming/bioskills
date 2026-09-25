#!/usr/bin/env bash
# minimap2 目录批处理：递归查找 DATA_DIR 下 fa/fq（含 .gz）。
#
# 必填：DATA_DIR  OUT_BASE  REFERENCE
# 可选：OUTPUT_FORMAT=bam|paf  MINIMAP2_ARGS  CPUS_PER_TASK  PARA_CPU
#       MINIMAP2_BIN  SAMTOOLS_BIN  CIGAR_PAF=1  CIGAR_BAM=1  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/minimap2_align.py}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-bam}"
: "${MINIMAP2_ARGS:=-x splice -uf -k14}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... REFERENCE=genome.fa [OUTPUT_FORMAT=bam] \\
       [MINIMAP2_ARGS="-x splice -uf -k14"] [CPUS_PER_TASK=4] [PARA_CPU=N] \\
       bash modules/minimap2/native/batch_align.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
if [[ -z "${REFERENCE:-}" || ! -e "$REFERENCE" ]]; then
  echo "[ERROR] REFERENCE required (genome FASTA path)" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

CMD_FILE="${CMD_FILE:-${OUT_BASE}/minimap2_commands.txt}"
mkdir -p "$OUT_BASE"
: >"$CMD_FILE"

while IFS= read -r -d '' reads; do
  sample_dir="$(basename "$(dirname "$reads")")"
  cmd=("$PYTHON" "$WRAPPER" --reads "$reads" --reference "$REFERENCE" \
    --outdir "$OUT_BASE/$sample_dir" --cpus "$CPUS_PER_TASK")
  [[ "$OUTPUT_FORMAT" == "bam" ]] && cmd+=(--bam)
  [[ -n "$MINIMAP2_ARGS" ]] && cmd+=(--args "$MINIMAP2_ARGS")
  [[ -n "${CIGAR_PAF:-}" ]] && cmd+=(--cigar-paf)
  [[ -n "${CIGAR_BAM:-}" ]] && cmd+=(--cigar-bam)
  [[ -n "${MINIMAP2_BIN:-}" ]] && cmd+=(--minimap2-bin "$MINIMAP2_BIN")
  [[ -n "${SAMTOOLS_BIN:-}" ]] && cmd+=(--samtools-bin "$SAMTOOLS_BIN")
  printf '%q ' "${cmd[@]}" >>"$CMD_FILE"
  printf '\n' >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( \
  -name '*.fa' -o -name '*.fa.gz' -o -name '*.fasta' -o -name '*.fasta.gz' \
  -o -name '*.fastq' -o -name '*.fastq.gz' \) -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no reads under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] minimap2 batch done → $OUT_BASE"
