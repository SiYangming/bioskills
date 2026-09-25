#!/usr/bin/env bash
# uLTRA 目录批处理：先（如需）建共享 index，再对 DATA_DIR 下 *.fa.gz/*.fasta.gz 做 gunzip→align。
#
# 必填：DATA_DIR  OUT_BASE  REFERENCE_FA  GTF
# 可选：INDEX_DIR=$OUT_BASE/INDEX  CPUS_PER_TASK  PARA_CPU
#       ULTRA_INDEX_ARGS  ULTRA_ALIGN_ARGS  SAMTOOLS_SORT_ARGS  GZIP_ARGS  GNU_SORT_ARGS
#       ULTRA_BIN  SAMTOOLS_BIN  MINIMAP2_BIN  NAMFINDER_BIN  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/ULTRA_align.py}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
PARA_CPU="${PARA_CPU:-$(batch_default_jobs)}"
: "${ULTRA_INDEX_ARGS:=--disable_infer}"

usage() {
  cat >&2 <<'EOF'
Usage: DATA_DIR=... OUT_BASE=... REFERENCE_FA=genome.fa GTF=annot.gtf \\
       [INDEX_DIR=...] [CPUS_PER_TASK=4] [PARA_CPU=N] \\
       bash modules/ultra/native/batch_align.sh
EOF
}

if [[ -z "${DATA_DIR:-}" || ! -d "$DATA_DIR" ]]; then
  echo "[ERROR] DATA_DIR required" >&2; usage; exit 1
fi
if [[ -z "${OUT_BASE:-}" ]]; then
  echo "[ERROR] OUT_BASE required" >&2; usage; exit 1
fi
if [[ -z "${REFERENCE_FA:-}" || ! -e "$REFERENCE_FA" ]]; then
  echo "[ERROR] REFERENCE_FA required" >&2; usage; exit 1
fi
if [[ -z "${GTF:-}" || ! -e "$GTF" ]]; then
  echo "[ERROR] GTF required" >&2; usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

INDEX_DIR="${INDEX_DIR:-${OUT_BASE}/INDEX}"
CMD_FILE="${CMD_FILE:-${OUT_BASE}/ultra_commands.txt}"
mkdir -p "$OUT_BASE" "$INDEX_DIR"
: >"$CMD_FILE"

need_index=0
shopt -s nullglob
pickles=("$INDEX_DIR"/*.pickle)
dbs=("$INDEX_DIR"/*.db)
shopt -u nullglob
[[ ${#pickles[@]} -eq 0 || ${#dbs[@]} -eq 0 ]] && need_index=1

if [[ "$need_index" -eq 1 ]]; then
  echo "[INFO] building uLTRA index → $INDEX_DIR"
  base_name="$(basename "$GTF")"
  case "$base_name" in
    *.gtf.gz) stem="${base_name%.gtf.gz}" ;;
    *.gtf)    stem="${base_name%.gtf}" ;;
    *)        stem="${base_name%.*}" ;;
  esac
  sorted_gtf="${INDEX_DIR}/${stem}.sorted.gtf"
  sort_cmd=("$PYTHON" "$WRAPPER" sort --gtf "$GTF" --outdir "$INDEX_DIR" --prefix "$stem")
  [[ -n "${GNU_SORT_ARGS:-}" ]] && sort_cmd+=(--args="$GNU_SORT_ARGS")
  "${sort_cmd[@]}"

  idx_cmd=("$PYTHON" "$WRAPPER" index --fasta "$REFERENCE_FA" --gtf "$sorted_gtf" --outdir "$INDEX_DIR")
  [[ -n "$ULTRA_INDEX_ARGS" ]] && idx_cmd+=(--args="$ULTRA_INDEX_ARGS")
  [[ -n "${ULTRA_BIN:-}" ]] && idx_cmd+=(--ultra-bin "$ULTRA_BIN")
  "${idx_cmd[@]}"
else
  echo "[INFO] reuse existing index in $INDEX_DIR"
fi

while IFS= read -r -d '' gz; do
  sample_dir="$(basename "$(dirname "$gz")")"
  outdir_sample="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir_sample"
  base="$(basename "$gz")"
  out_read="${outdir_sample}/${base%.gz}"

  # 单行链式命令，保证同一样本 gunzip 后再 align
  line="$PYTHON $(printf '%q' "$WRAPPER") gunzip --archive $(printf '%q' "$gz") --outdir $(printf '%q' "$outdir_sample")"
  [[ -n "${GZIP_ARGS:-}" ]] && line+=" --args=$(printf '%q' "$GZIP_ARGS")"
  line+=" && $PYTHON $(printf '%q' "$WRAPPER") align --reads $(printf '%q' "$out_read") --genome $(printf '%q' "$REFERENCE_FA") --index-dir $(printf '%q' "$INDEX_DIR") --outdir $(printf '%q' "$outdir_sample") --cpus $(printf '%q' "$CPUS_PER_TASK")"
  [[ -n "${ULTRA_ALIGN_ARGS:-}" ]] && line+=" --args=$(printf '%q' "$ULTRA_ALIGN_ARGS")"
  [[ -n "${SAMTOOLS_SORT_ARGS:-}" ]] && line+=" --args2=$(printf '%q' "$SAMTOOLS_SORT_ARGS")"
  [[ -n "${ULTRA_BIN:-}" ]] && line+=" --ultra-bin $(printf '%q' "$ULTRA_BIN")"
  [[ -n "${SAMTOOLS_BIN:-}" ]] && line+=" --samtools-bin $(printf '%q' "$SAMTOOLS_BIN")"
  [[ -n "${MINIMAP2_BIN:-}" ]] && line+=" --minimap2-bin $(printf '%q' "$MINIMAP2_BIN")"
  [[ -n "${NAMFINDER_BIN:-}" ]] && line+=" --namfinder-bin $(printf '%q' "$NAMFINDER_BIN")"
  printf '%s\n' "$line" >>"$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( -name '*.fa.gz' -o -name '*.fasta.gz' \) -print0)

[[ -s "$CMD_FILE" ]] || { echo "[ERROR] no *.fa.gz/*.fasta.gz under $DATA_DIR" >&2; exit 1; }

batch_run_cmdfile "$CMD_FILE" "$PARA_CPU"
echo "[INFO] ultra batch done → $OUT_BASE"
