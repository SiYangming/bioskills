#!/usr/bin/env bash
set -euo pipefail

# 可选：激活运行环境
# conda activate pacbio_iso_seq

# 配置参数（可通过环境变量覆盖）
DATA_DIR=${DATA_DIR:-"C8TF/all"}          # 指向包含样本子目录的路径
OUT_BASE=${OUT_BASE:-"ccs_output"}       # 输出根目录
CHUNK_TOTAL=${CHUNK_TOTAL:-40}            # 若不分块，将其设为 1
CPUS_PER_TASK=${CPUS_PER_TASK:-8}         # 每个 ccs 任务使用的线程数
PARA_CPU=${PARA_CPU:-28}                  # 并发任务数（总并发 = PARA_CPU * CPUS_PER_TASK 近似）
CMD_FILE=${CMD_FILE:-"${OUT_BASE}/ccs_commands.txt"}
CCS_BIN=${CCS_BIN:-"~/miniconda3/envs/pacbio_iso_seq/bin/ccs"}                   # 可选：ccs绝对路径，如 ~/miniconda3/envs/pacbio_iso_seq/bin/ccs

mkdir -p "$OUT_BASE"
> "$CMD_FILE"

echo "生成命令列表到: $CMD_FILE"
for bam in "$DATA_DIR"/*/*.subreads.bam; do
  sample_dir=$(basename "$(dirname "$bam")")
  for i in $(seq 1 "$CHUNK_TOTAL"); do
    cmd_line="python3 pyflow/ccs_analysis.py --subreads \"$bam\" --outdir \"$OUT_BASE/$sample_dir\" --chunk-num \"$i\" --chunk-total \"$CHUNK_TOTAL\" --cpus \"$CPUS_PER_TASK\""
    if [[ -n "$CCS_BIN" ]]; then
      cmd_line+=" --ccs-bin \"$CCS_BIN\""
    fi
    echo "$cmd_line" >> "$CMD_FILE"
  done
done

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

echo "全部任务提交完成，CCS分析完成"