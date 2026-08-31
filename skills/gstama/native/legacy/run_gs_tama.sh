#!/usr/bin/env bash
set -euo pipefail

# gs-TAMA 批处理封装：collapse => filelist => merge
# 说明：polyA 清理已改为单独执行模式，请手动运行：
#   python3 pyflow/gs_tama.py polyacleanup --fasta <FLNC.fasta> --outdir <outdir> [--args=...] [--tama-script /abs/path/to/tama_flnc_polya_cleanup.py]
# 参考 ULTRA_align.py 的封装风格，后续三步保持并发/顺序逻辑不变。

# 可选：激活运行环境
# conda activate pacbio_iso_seq

# 1) collapse（输入为每个样本的 BAM，需指定参考基因组 FASTA）
# 支持同时从两个目录收集：ultra_align_output 与 minimap2_align_output
COLLAPSE_BAM_DIR=${COLLAPSE_BAM_DIR:-"ULTRA_align_output"}
COLLAPSE_BAM_DIR_SECOND=${COLLAPSE_BAM_DIR_SECOND:-"minimap2_align_output"}
GENOME_FA=${GENOME_FA:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/Oryza_rufipogon.OR_W1943.dna.toplevel.fa.gz"}  # 必填：参考基因组 FASTA，用于 tama_collapse
COLLAPSE_OUT_BASE=${COLLAPSE_OUT_BASE:-"gstama_collapse_output"}
COLLAPSE_ARGS=${COLLAPSE_ARGS:-"-b BAM"}
TAMA_COLLAPSE_SCRIPT=${TAMA_COLLAPSE_SCRIPT:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/gs-tama-1.0.4/tama_collapse.py"}  # 可选：tama_collapse.py 绝对路径
COLLAPSE_CPU=${COLLAPSE_CPU:-28}
COLLAPSE_CMD_FILE=${COLLAPSE_CMD_FILE:-"${COLLAPSE_OUT_BASE}/collapse_commands.txt"}
SAMTOOLS_BIN=${SAMTOOLS_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/samtools"}

# 2) filelist（聚合 collapse 的 *.bed 为 TSV）
FILELIST_BED_DIR=${FILELIST_BED_DIR:-"${COLLAPSE_OUT_BASE}"}
FILELIST_CAP=${FILELIST_CAP:-"no_cap"}
FILELIST_ORDER=${FILELIST_ORDER:-"1"}
FILELIST_OUT_BASE=${FILELIST_OUT_BASE:-"gstama_filelist_output"}
FILELIST_PREFIX=${FILELIST_PREFIX:-"tama_merge_sources"}

# 3) merge（根据 filelist 合并）
MERGE_OUT_BASE=${MERGE_OUT_BASE:-"gstama_merge_output"}
MERGE_ARGS=${MERGE_ARGS:-""}
TAMA_MERGE_SCRIPT=${TAMA_MERGE_SCRIPT:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/gs-tama-1.0.4/tama_merge.py"}  # 可选：tama_merge.py 绝对路径

mkdir -p "$COLLAPSE_OUT_BASE" "$FILELIST_OUT_BASE" "$MERGE_OUT_BASE"
############################################
# Step 1: 生成并发执行的 collapse 命令
############################################
if [[ -z "$GENOME_FA" ]]; then
  echo "[ERROR] 未设置 GENOME_FA。请导出参考基因组 FASTA: export GENOME_FA=/path/to/genome.fa" >&2
  exit 1
fi

> "$COLLAPSE_CMD_FILE"
echo "生成 collapse 命令列表到: $COLLAPSE_CMD_FILE"

# 收集两个来源的 BAM：ultra 与 minimap2，并将输出分源存放到子目录，避免同名覆盖
for SRC_DIR in "$COLLAPSE_BAM_DIR" "$COLLAPSE_BAM_DIR_SECOND"; do
  [[ -d "$SRC_DIR" ]] || continue
  if [[ "$SRC_DIR" == *minimap2* ]]; then
    SRC_LABEL="minimap2"
  elif [[ "$SRC_DIR" == *ULTRA* ]]; then
    SRC_LABEL="ultra"
  else
    SRC_LABEL=$(basename "$SRC_DIR")
  fi
  mkdir -p "$COLLAPSE_OUT_BASE/$SRC_LABEL"
  while IFS= read -r bam; do
    sample=$(basename "$bam")
    outdir="$COLLAPSE_OUT_BASE/$SRC_LABEL/${sample%.bam}"
    mkdir -p "$outdir"
    cmd_line="python3 pyflow/gs_tama.py collapse --bam \"$bam\" --fasta \"$GENOME_FA\" --outdir \"$outdir\""
    if [[ -n "$COLLAPSE_ARGS" ]]; then
      cmd_line+=" --args=\"$COLLAPSE_ARGS\""
    fi
    if [[ -n "$TAMA_COLLAPSE_SCRIPT" ]]; then
      cmd_line+=" --tama-collapse-script \"$TAMA_COLLAPSE_SCRIPT\""
    fi
    if [[ -n "$SAMTOOLS_BIN" ]]; then
      cmd_line+=" --samtools-bin \"$SAMTOOLS_BIN\""
    fi
    echo "$cmd_line" >> "$COLLAPSE_CMD_FILE"
  done < <(find "$SRC_DIR" -type f \( -name "*.bam" -o -name "*.sam" \))
done

echo "collapse 命令数量: $(wc -l < "$COLLAPSE_CMD_FILE")"

if [[ -s "$COLLAPSE_CMD_FILE" ]]; then
  if command -v ParaFly >/dev/null 2>&1; then
    echo "使用 ParaFly 并发执行 collapse, CPU=$COLLAPSE_CPU"
    ParaFly -c "$COLLAPSE_CMD_FILE" -CPU "$COLLAPSE_CPU"
  elif command -v parallel >/dev/null 2>&1; then
    echo "使用 GNU parallel 并发执行 collapse, -j=$COLLAPSE_CPU"
    parallel -j "$COLLAPSE_CPU" --delay 0.2 --bar < "$COLLAPSE_CMD_FILE"
  else
    echo "使用 xargs 并发执行 collapse, -P=$COLLAPSE_CPU"
    xargs -I CMD -P "$COLLAPSE_CPU" bash -c 'CMD' < "$COLLAPSE_CMD_FILE"
  fi
fi

############################################
# Step 2: 生成合并 filelist TSV（同时聚合 ultra 与 minimap2 的 collapse 结果）
############################################
FILELIST_TSV="${FILELIST_OUT_BASE}/${FILELIST_PREFIX}.tsv"
echo "生成合并 filelist TSV 到: $FILELIST_TSV"

# 每个来源分别生成 TSV，然后合并
FILELIST_CAP_ULTRA=${FILELIST_CAP_ULTRA:-"$FILELIST_CAP"}
FILELIST_ORDER_ULTRA=${FILELIST_ORDER_ULTRA:-"$FILELIST_ORDER"}
FILELIST_CAP_MINIMAP2=${FILELIST_CAP_MINIMAP2:-"$FILELIST_CAP"}
FILELIST_ORDER_MINIMAP2=${FILELIST_ORDER_MINIMAP2:-"$FILELIST_ORDER"}

TSV_TMP_ULTRA="${FILELIST_OUT_BASE}/${FILELIST_PREFIX}_ultra.tsv"
TSV_TMP_MINIMAP2="${FILELIST_OUT_BASE}/${FILELIST_PREFIX}_minimap2.tsv"

> "$FILELIST_TSV"

if [[ -d "$COLLAPSE_OUT_BASE/ultra" ]]; then
  if python3 pyflow/gs_tama.py filelist \
    --bed-dir "$COLLAPSE_OUT_BASE/ultra" \
    --cap "$FILELIST_CAP_ULTRA" \
    --order "$FILELIST_ORDER_ULTRA" \
    --outdir "$FILELIST_OUT_BASE" \
    --prefix "${FILELIST_PREFIX}_ultra" \
    --pattern "**/*tama_collapsed.bed"; then
    cat "$TSV_TMP_ULTRA" >> "$FILELIST_TSV"
  else
    echo "[WARN] 未检测到 ultra collapse 的 bed 文件，跳过 ultra 源。"
  fi
else
  echo "[WARN] 未检测到 ultra collapse 输出目录，跳过 ultra 源。"
fi

if [[ -d "$COLLAPSE_OUT_BASE/minimap2" ]]; then
  if python3 pyflow/gs_tama.py filelist \
    --bed-dir "$COLLAPSE_OUT_BASE/minimap2" \
    --cap "$FILELIST_CAP_MINIMAP2" \
    --order "$FILELIST_ORDER_MINIMAP2" \
    --outdir "$FILELIST_OUT_BASE" \
    --prefix "${FILELIST_PREFIX}_minimap2" \
    --pattern "**/*tama_collapsed.bed"; then
    cat "$TSV_TMP_MINIMAP2" >> "$FILELIST_TSV"
  else
    echo "[WARN] 未检测到 minimap2 collapse 的 bed 文件，跳过 minimap2 源。"
  fi
else
  echo "[WARN] 未检测到 minimap2 collapse 输出目录，跳过 minimap2 源。"
fi

############################################
# Step 3: 运行 merge（单次执行）
############################################
if [[ ! -s "$FILELIST_TSV" ]] || ! grep -q '[^[:space:]]' "$FILELIST_TSV"; then
  echo "[WARN] filelist TSV 为空或不存在，将跳过 merge：$FILELIST_TSV"
  if [[ ! -e "$FILELIST_TSV" ]]; then
    STATUS="skipped (no filelist)"
  else
    STATUS="skipped (empty filelist)"
  fi
  printf "gstama_merge:\n    gstama: %s\n" "$STATUS" > "$MERGE_OUT_BASE/versions.yml"
else
  echo "运行 TAMA merge 到目录: $MERGE_OUT_BASE"
  MERGE_CMD=(python3 pyflow/gs_tama.py merge --filelist "$FILELIST_TSV" --outdir "$MERGE_OUT_BASE" --prefix "merged")
  if [[ -n "$MERGE_ARGS" ]]; then
    MERGE_CMD+=("--args=$MERGE_ARGS")
  fi
  if [[ -n "$TAMA_MERGE_SCRIPT" ]]; then
    MERGE_CMD+=("--tama-merge-script" "$TAMA_MERGE_SCRIPT")
  fi
  "${MERGE_CMD[@]}"
fi

echo "gs-TAMA 批处理完成：collapse => filelist => merge（polyA 清理请单独执行）"