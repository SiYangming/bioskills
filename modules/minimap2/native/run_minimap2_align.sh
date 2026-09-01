#!/usr/bin/env bash
set -euo pipefail

# 并发批处理：minimap2 比对（PAF 或 BAM 输出）

# 参数（可通过环境变量覆盖）
DATA_DIR=${DATA_DIR:-"tama_polyacleanup_output"}   # 输入序列目录（包含样本子目录）
OUT_BASE=${OUT_BASE:-"minimap2_align_output"}      # 输出根目录
REFERENCE=${REFERENCE:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/Oryza_rufipogon.OR_W1943.dna.toplevel.fa.gz"}                          # 必填：参考基因组 FASTA 路径
OUTPUT_FORMAT=${OUTPUT_FORMAT:-"bam"}               # 选择输出格式：paf 或 bam
# 转录组长读段的推荐参数
MINIMAP2_ARGS=${MINIMAP2_ARGS:-"-x splice -uf -k14"}                  # 透传 minimap2 参数，例如 "-x splice -uf -k14"
CPUS_PER_TASK=${CPUS_PER_TASK:-8}                    # 每个比对任务的线程数
PARA_CPU=${PARA_CPU:-28}                             # 并发任务数
CMD_FILE=${CMD_FILE:-"${OUT_BASE}/minimap2_commands.txt"}
MINIMAP2_BIN=${MINIMAP2_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/minimap2"}                    # 可选：minimap2 绝对路径
SAMTOOLS_BIN=${SAMTOOLS_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/samtools"}                    # 可选：samtools 绝对路径（BAM 输出时使用）
CIGAR_PAF=${CIGAR_PAF:-""}                          # 若非空，则在 PAF 中写 CIGAR（-c）
CIGAR_BAM=${CIGAR_BAM:-""}                          # 若非空，则在 BAM 中写 CG 标签（-L）

if [[ -z "${REFERENCE}" ]]; then
  echo "ERROR: 未设置 REFERENCE。请导出参考基因组FASTA路径，例如："
  echo "  export REFERENCE=/path/to/genome.fa"
  exit 1
fi

mkdir -p "${OUT_BASE}"
> "${CMD_FILE}"

echo "生成命令列表到: ${CMD_FILE}"

# 遍历支持的输入扩展名
while IFS= read -r reads; do
  sample_dir=$(basename "$(dirname "${reads}")")
  cmd_line="python3 pyflow/minimap2_align.py --reads \"${reads}\" --reference \"${REFERENCE}\" --outdir \"${OUT_BASE}/${sample_dir}\" --cpus \"${CPUS_PER_TASK}\""

  if [[ "${OUTPUT_FORMAT}" == "bam" ]]; then
    cmd_line+=" --bam"
  fi

  if [[ -n "${MINIMAP2_ARGS}" ]]; then
    cmd_line+=" --args \"${MINIMAP2_ARGS}\""
  fi

  if [[ -n "${CIGAR_PAF}" ]]; then
    cmd_line+=" --cigar-paf"
  fi

  if [[ -n "${CIGAR_BAM}" ]]; then
    cmd_line+=" --cigar-bam"
  fi

  if [[ -n "${MINIMAP2_BIN}" ]]; then
    cmd_line+=" --minimap2-bin \"${MINIMAP2_BIN}\""
  fi

  if [[ -n "${SAMTOOLS_BIN}" ]]; then
    cmd_line+=" --samtools-bin \"${SAMTOOLS_BIN}\""
  fi

  echo "${cmd_line}" >> "${CMD_FILE}"
done < <(find "${DATA_DIR}" -type f \( -name "*.fa" -o -name "*.fa.gz" -o -name "*.fasta" -o -name "*.fasta.gz" -o -name "*.fastq" -o -name "*.fastq.gz" \))

echo "命令数量: $(wc -l < "${CMD_FILE}")"

# 并发执行：优先 ParaFly，其次 GNU parallel，最后 xargs
if command -v ParaFly >/dev/null 2>&1; then
  echo "使用 ParaFly 并发执行, CPU=${PARA_CPU}"
  ParaFly -c "${CMD_FILE}" -CPU "${PARA_CPU}"
elif command -v parallel >/dev/null 2>&1; then
  echo "使用 GNU parallel 并发执行, -j=${PARA_CPU}"
  parallel -j "${PARA_CPU}" --delay 0.2 --bar < "${CMD_FILE}"
else
  echo "使用 xargs 并发执行, -P=${PARA_CPU}"
  xargs -I CMD -P "${PARA_CPU}" bash -c 'CMD' < "${CMD_FILE}"
fi

echo "全部任务提交完成，minimap2 比对完成"