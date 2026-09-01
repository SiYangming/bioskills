#!/usr/bin/env bash
set -euo pipefail

# 可选：激活运行环境
# conda activate pacbio_iso_seq

# 配置参数（可通过环境变量覆盖）
DATA_DIR=${DATA_DIR:-"ccs_output"}            # 指向包含样本子目录/ccs结果的路径
OUT_BASE=${OUT_BASE:-"lima_output"}          # 输出根目录
CPUS_PER_TASK=${CPUS_PER_TASK:-8}             # 每个 lima 任务使用的线程数
PARA_CPU=${PARA_CPU:-28}                      # 并发任务数（近似总并发 = PARA_CPU * CPUS_PER_TASK）
CMD_FILE=${CMD_FILE:-"${OUT_BASE}/lima_commands.txt"}
PRIMERS=${PRIMERS:-"pyflow/primers.fasta"}   # 引物fasta文件
LIMA_BIN=${LIMA_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/lima"}                     # 可选：lima绝对路径，如 ~/miniconda3/envs/pacbio_iso_seq/bin/lima

mkdir -p "$OUT_BASE"
> "$CMD_FILE"

echo "生成Lima命令列表到: $CMD_FILE"

# 搜索支持的输入后缀
while IFS= read -r reads; do
  sample_dir=$(basename "$(dirname "$reads")")
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd_line="python3 pyflow/lima_analysis.py --reads \"$reads\" --primers \"$PRIMERS\" --outdir \"$outdir\" --cpus \"$CPUS_PER_TASK\""
  if [[ -n "$LIMA_BIN" ]]; then
    cmd_line+=" --lima-bin \"$LIMA_BIN\""
  fi
  echo "$cmd_line" >> "$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( -name "*.bam" -o -name "*.fasta" -o -name "*.fastq" -o -name "*.fasta.gz" -o -name "*.fastq.gz" \))

echo "命令数量: $(wc -l < "$CMD_FILE")"

# 优先使用 ParaFly，其次 GNU parallel，最后 xargs 作为降级方案
if command -v ParaFly >/dev/null 2>&1; then
  echo "使用 ParaFly 并发执行, CPU=$PARA_CPU"
  ParaFly -c "$CMD_FILE" -CPU "$PARA_CPU"
elif command -v parallel >/dev/null 2>&1; then
  echo "使用 GNU parallel 并发执行, -j=$PARA_CPU"
  parallel -j "$PARA_CPU" --delay 0.2 --bar < "$CMD_FILE"
else
  echo "使用 xargs 并发执行, -P=$PARA_CPU (如遇到复杂引号问题，建议安装 ParaFly 或 parallel)"
  xargs -I CMD -P "$PARA_CPU" bash -c 'CMD' < "$CMD_FILE"
fi

echo "全部任务提交完成，Lima分析完成"