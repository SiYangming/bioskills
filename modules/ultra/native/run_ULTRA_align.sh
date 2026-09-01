#!/usr/bin/env bash
set -euo pipefail

# 并发批处理：基于 TAMA polyA cleanup 输出，运行 gunzip → GTF sort → ULTRA index → ULTRA align

# 目录与参考
DATA_DIR=${DATA_DIR:-"tama_polyacleanup_output"}           # 输入目录（包含样本子目录，内有 *.fa.gz）
OUT_BASE=${OUT_BASE:-"ULTRA_align_output"}                 # 输出根目录
INDEX_DIR=${INDEX_DIR:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/INDEX"}                # 索引输出目录（统一一次）
REFERENCE_FA=${REFERENCE_FA:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/Oryza_rufipogon.OR_W1943.dna.toplevel.fa.gz"}                           # 参考基因组 FASTA（必填）
GTF=${GTF:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/Oryza_rufipogon.OR_W1943.62.gtf.gz"}               # 参考注释 GTF（默认仓库内示例路径）

# 运行参数
ULTRA_INDEX_ARGS=${ULTRA_INDEX_ARGS:-"--disable_infer"}                   # 透传到 uLTRA index 的参数
ULTRA_ALIGN_ARGS=${ULTRA_ALIGN_ARGS:-""}                   # 透传到 uLTRA align 的参数
SAMTOOLS_SORT_ARGS=${SAMTOOLS_SORT_ARGS:-""}               # 透传到 samtools sort 的参数
GZIP_ARGS=${GZIP_ARGS:-""}                                 # 透传到 gzip 的参数（gunzip 子模块）
GNU_SORT_ARGS=${GNU_SORT_ARGS:-""}                         # 透传到 GNU sort 的参数（index 前对 GTF 排序）
CPUS_PER_TASK=${CPUS_PER_TASK:-8}                           # 每个对齐任务线程数
PARA_CPU=${PARA_CPU:-1}                                    # 并发任务数
CMD_FILE=${CMD_FILE:-"${OUT_BASE}/ULTRA_commands.txt"}
ULTRA_BIN=${ULTRA_BIN:-"~/miniconda3/envs/ultra_bioinformatics/bin/uLTRA"}                                  # 可选：uLTRA 绝对路径
SAMTOOLS_BIN=${SAMTOOLS_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/samtools"}                            # 可选：samtools 绝对路径
MINIMAP2_BIN=${MINIMAP2_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/minimap2"}                                                                     # 可选：minimap2 绝对路径
NAMFINDER_BIN=${NAMFINDER_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/namfinder"}                                                           # 可选：namfinder 绝对路径

if [[ -z "${REFERENCE_FA}" ]]; then
  echo "ERROR: 未设置 REFERENCE_FA。请导出参考基因组FASTA路径，例如："
  echo "  export REFERENCE_FA=/data/genome/hg38.fa"
  exit 1
fi

if [[ ! -f "${GTF}" ]]; then
  echo "ERROR: 未找到 GTF: ${GTF}。请设置有效路径（export GTF=/path/to/annotation.gtf），例如 Ensembl/RefSeq 的基因组注释。"
  exit 1
fi

mkdir -p "${OUT_BASE}" "${INDEX_DIR}"
> "${CMD_FILE}"

########################################
# 先同步执行索引（一次性），避免并发依赖问题
########################################
if [[ -z "$(ls -1 ${INDEX_DIR}/*.pickle 2>/dev/null || true)" ]] || [[ -z "$(ls -1 ${INDEX_DIR}/*.db 2>/dev/null || true)" ]]; then
  echo "索引不存在或不完整，先对 GTF 排序并生成 uLTRA index 到 ${INDEX_DIR}"

  # 对 GTF 排序到 INDEX_DIR，下游 index 使用该排序结果（自动去除 .gtf/.gtf.gz 双扩展）
  base_name=$(basename "${GTF}")
  if [[ "${base_name}" == *.gtf.gz ]]; then
    stem="${base_name%.gtf.gz}"
  elif [[ "${base_name}" == *.gtf ]]; then
    stem="${base_name%.gtf}"
  else
    stem="${base_name%.*}"
  fi
  sorted_gtf="${INDEX_DIR}/${stem}.sorted.gtf"
  sort_cmd=(python3 pyflow/ULTRA_align.py sort --gtf "${GTF}" --outdir "${INDEX_DIR}" --prefix "${stem}")
  if [[ -n "${GNU_SORT_ARGS}" ]]; then sort_cmd+=(--args="${GNU_SORT_ARGS}"); fi
  "${sort_cmd[@]}"

  # 生成索引
  idx_cmd=(python3 pyflow/ULTRA_align.py index --fasta "${REFERENCE_FA}" --gtf "${sorted_gtf}" --outdir "${INDEX_DIR}")
  if [[ -n "${ULTRA_INDEX_ARGS}" ]]; then idx_cmd+=(--args="${ULTRA_INDEX_ARGS}"); fi
  if [[ -n "${ULTRA_BIN}" ]]; then idx_cmd+=(--ultra-bin "${ULTRA_BIN}"); fi
  "${idx_cmd[@]}"
else
  echo "检测到已存在索引文件 (*.pickle, *.db)，跳过 index"
fi

########################################
# 构建并发命令：gunzip → align 链式执行
########################################
echo "生成命令列表到: ${CMD_FILE}"
while IFS= read -r gz; do
  sample_dir=$(basename "$(dirname "${gz}")")
  outdir_sample="${OUT_BASE}/${sample_dir}"
  mkdir -p "${outdir_sample}"

  # 推断解压后的输出文件名（去掉 .gz）
  base=$(basename "${gz}")
  out_read="${outdir_sample}/$(echo "${base}" | sed 's/\.gz$//')"

  # 组合链式命令，确保本样本 gunzip 完成后再 align
  cmd_line="python3 pyflow/ULTRA_align.py gunzip --archive \"${gz}\" --outdir \"${outdir_sample}\" --args=\"${GZIP_ARGS}\" && "
  cmd_line+="python3 pyflow/ULTRA_align.py align --reads \"${out_read}\" --genome \"${REFERENCE_FA}\" --index-dir \"${INDEX_DIR}\" --outdir \"${outdir_sample}\" --cpus \"${CPUS_PER_TASK}\""

  if [[ -n "${ULTRA_ALIGN_ARGS}" ]]; then
    cmd_line+=" --args=\"${ULTRA_ALIGN_ARGS}\""
  fi
  if [[ -n "${SAMTOOLS_SORT_ARGS}" ]]; then
    cmd_line+=" --args2=\"${SAMTOOLS_SORT_ARGS}\""
  fi
  if [[ -n "${ULTRA_BIN}" ]]; then
    cmd_line+=" --ultra-bin \"${ULTRA_BIN}\""
  fi
  if [[ -n "${SAMTOOLS_BIN}" ]]; then
    cmd_line+=" --samtools-bin \"${SAMTOOLS_BIN}\""
  fi
  if [[ -n "${MINIMAP2_BIN}" ]]; then
    cmd_line+=" --minimap2-bin \"${MINIMAP2_BIN}\""
  fi
  if [[ -n "${NAMFINDER_BIN}" ]]; then
    cmd_line+=" --namfinder-bin \"${NAMFINDER_BIN}\""
  fi

  echo "${cmd_line}" >> "${CMD_FILE}"
done < <(find "${DATA_DIR}" -type f \( -name "*.fa.gz" -o -name "*.fasta.gz" \))

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

echo "全部任务提交完成，ULTRA 对齐完成"