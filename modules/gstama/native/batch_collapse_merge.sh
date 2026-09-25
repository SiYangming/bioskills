#!/usr/bin/env bash
# gstama：collapse → filelist → merge（多 BAM 源可选）。
#
# 必填：
#   GENOME_FA          参考基因组 FASTA
#   COLLAPSE_BAM_DIRS  空格分隔的 BAM 根目录列表（每个目录递归找 *.bam/*.sam）
#   COLLAPSE_OUT_BASE  collapse 输出根
#   FILELIST_OUT_BASE  filelist 输出根
#   MERGE_OUT_BASE     merge 输出根
# 可选：
#   COLLAPSE_LABELS    与 COLLAPSE_BAM_DIRS 一一对应的标签（默认用目录 basename）
#   COLLAPSE_ARGS  COLLAPSE_CPU  FILELIST_CAP=no_cap  FILELIST_PREFIX
#   BED_PATTERN='**/*collapsed.bed'  MERGE_ARGS  SAMTOOLS_BIN
#   TAMA_COLLAPSE_SCRIPT  TAMA_MERGE_SCRIPT  WRAPPER  PYTHON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/batch_parallel.sh
source "${SCRIPT_DIR}/../../../scripts/batch_parallel.sh"

PYTHON="${PYTHON:-python3}"
WRAPPER="${WRAPPER:-${SCRIPT_DIR}/gs_tama.py}"
: "${COLLAPSE_ARGS:=-b BAM}"
COLLAPSE_CPU="${COLLAPSE_CPU:-$(batch_default_jobs)}"
FILELIST_CAP="${FILELIST_CAP:-no_cap}"
FILELIST_PREFIX="${FILELIST_PREFIX:-tama_merge_sources}"
BED_PATTERN="${BED_PATTERN:-**/*collapsed.bed}"

usage() {
  cat >&2 <<'EOF'
Usage:
  GENOME_FA=genome.fa \\
  COLLAPSE_BAM_DIRS="align_a align_b" \\
  [COLLAPSE_LABELS="ultra minimap2"] \\
  COLLAPSE_OUT_BASE=... FILELIST_OUT_BASE=... MERGE_OUT_BASE=... \\
  bash modules/gstama/native/batch_collapse_merge.sh
EOF
}

if [[ -z "${GENOME_FA:-}" || ! -e "$GENOME_FA" ]]; then
  echo "[ERROR] GENOME_FA required" >&2; usage; exit 1
fi
if [[ -z "${COLLAPSE_BAM_DIRS:-}" ]]; then
  echo "[ERROR] COLLAPSE_BAM_DIRS required (space-separated BAM roots)" >&2; usage; exit 1
fi
if [[ -z "${COLLAPSE_OUT_BASE:-}" || -z "${FILELIST_OUT_BASE:-}" || -z "${MERGE_OUT_BASE:-}" ]]; then
  echo "[ERROR] COLLAPSE_OUT_BASE, FILELIST_OUT_BASE, MERGE_OUT_BASE required" >&2
  usage; exit 1
fi
[[ -f "$WRAPPER" ]] || { echo "[ERROR] wrapper not found: $WRAPPER" >&2; exit 1; }

mkdir -p "$COLLAPSE_OUT_BASE" "$FILELIST_OUT_BASE" "$MERGE_OUT_BASE"
COLLAPSE_CMD_FILE="${COLLAPSE_CMD_FILE:-${COLLAPSE_OUT_BASE}/collapse_commands.txt}"
: >"$COLLAPSE_CMD_FILE"

# shellcheck disable=SC2206
dirs=($COLLAPSE_BAM_DIRS)
if [[ -n "${COLLAPSE_LABELS:-}" ]]; then
  # shellcheck disable=SC2206
  labels=($COLLAPSE_LABELS)
else
  labels=()
  for d in "${dirs[@]}"; do labels+=("$(basename "$d")"); done
fi
if [[ ${#labels[@]} -ne ${#dirs[@]} ]]; then
  echo "[ERROR] COLLAPSE_LABELS count must match COLLAPSE_BAM_DIRS" >&2
  exit 1
fi

for i in "${!dirs[@]}"; do
  src_dir="${dirs[$i]}"
  label="${labels[$i]}"
  [[ -d "$src_dir" ]] || { echo "[WARN] skip missing BAM dir: $src_dir"; continue; }
  mkdir -p "$COLLAPSE_OUT_BASE/$label"
  while IFS= read -r -d '' bam; do
    sample="$(basename "${bam%.*}")"
    outdir="$COLLAPSE_OUT_BASE/$label/$sample"
    mkdir -p "$outdir"
    cmd=("$PYTHON" "$WRAPPER" collapse --bam "$bam" --fasta "$GENOME_FA" --outdir "$outdir")
    [[ -n "$COLLAPSE_ARGS" ]] && cmd+=(--args="$COLLAPSE_ARGS")
    [[ -n "${TAMA_COLLAPSE_SCRIPT:-}" ]] && cmd+=(--tama-collapse-script "$TAMA_COLLAPSE_SCRIPT")
    [[ -n "${SAMTOOLS_BIN:-}" ]] && cmd+=(--samtools-bin "$SAMTOOLS_BIN")
    printf '%q ' "${cmd[@]}" >>"$COLLAPSE_CMD_FILE"
    printf '\n' >>"$COLLAPSE_CMD_FILE"
  done < <(find "$src_dir" -type f \( -name '*.bam' -o -name '*.sam' \) -print0)
done

if [[ -s "$COLLAPSE_CMD_FILE" ]]; then
  batch_run_cmdfile "$COLLAPSE_CMD_FILE" "$COLLAPSE_CPU"
else
  echo "[WARN] no BAM/SAM found under COLLAPSE_BAM_DIRS"
fi

FILELIST_TSV="${FILELIST_OUT_BASE}/${FILELIST_PREFIX}.tsv"
: >"$FILELIST_TSV"
for label in "${labels[@]}"; do
  bed_root="$COLLAPSE_OUT_BASE/$label"
  [[ -d "$bed_root" ]] || continue
  prefix="${FILELIST_PREFIX}_${label}"
  if "$PYTHON" "$WRAPPER" filelist \
    --bed-dir "$bed_root" \
    --cap "$FILELIST_CAP" \
    --outdir "$FILELIST_OUT_BASE" \
    --prefix "$prefix" \
    --pattern "$BED_PATTERN"; then
    tmp="${FILELIST_OUT_BASE}/${prefix}.tsv"
    [[ -s "$tmp" ]] && cat "$tmp" >>"$FILELIST_TSV"
  else
    echo "[WARN] filelist failed for label=$label"
  fi
done

if [[ ! -s "$FILELIST_TSV" ]]; then
  echo "[WARN] empty filelist; skip merge"
  printf 'gstama_merge:\n    gstama: skipped (empty filelist)\n' >"$MERGE_OUT_BASE/versions.yml"
else
  merge_cmd=("$PYTHON" "$WRAPPER" merge --filelist "$FILELIST_TSV" --outdir "$MERGE_OUT_BASE" --prefix merged)
  [[ -n "${MERGE_ARGS:-}" ]] && merge_cmd+=(--args="$MERGE_ARGS")
  [[ -n "${TAMA_MERGE_SCRIPT:-}" ]] && merge_cmd+=(--tama-merge-script "$TAMA_MERGE_SCRIPT")
  "${merge_cmd[@]}"
fi

echo "[INFO] gstama collapse→filelist→merge done"
