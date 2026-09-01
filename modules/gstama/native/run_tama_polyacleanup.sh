#!/usr/bin/env bash
set -euo pipefail

# 可选：激活运行环境
# conda activate pacbio_iso_seq

# 配置参数（可通过环境变量覆盖）
DATA_DIR=${DATA_DIR:-"bamtools_convert_output"}      # 指向包含样本子目录/ FASTA 的路径
OUT_BASE=${OUT_BASE:-"tama_polyacleanup_output"}     # 输出根目录
ARGS=${ARGS:-""}                                     # 透传给 TAMA 脚本的附加参数
PARA_CPU=${PARA_CPU:-28}                              # 并发任务数
CMD_FILE=${CMD_FILE:-"${OUT_BASE}/tama_polyacleanup_commands.txt"}
TAMA_SCRIPT=${TAMA_SCRIPT:-"/data2/liuqi/chaizengpu/pacbio/X101SC24054971-Z01-J001.Pacbio.Rawdata.20240625/pyflow/gs-tama-1.0.4/tama_go/sequence_cleanup/tama_flnc_polya_cleanup.py"}  # 可选：脚本绝对路径

mkdir -p "$OUT_BASE"
> "$CMD_FILE"

echo "生成 TAMA polyA 清理命令列表到: $CMD_FILE"

while IFS= read -r fasta; do
  sample_dir=$(basename "$(dirname "$fasta")")
  outdir="$OUT_BASE/$sample_dir"
  mkdir -p "$outdir"
  cmd_line="python3 pyflow/tama_polyacleanup.py --fasta \"$fasta\" --outdir \"$outdir\""
  if [[ -n "$ARGS" ]]; then
    cmd_line+=" --args \"$ARGS\""
  fi
  if [[ -n "$TAMA_SCRIPT" ]]; then
    cmd_line+=" --tama-script \"$TAMA_SCRIPT\""
  fi
  echo "$cmd_line" >> "$CMD_FILE"
done < <(find "$DATA_DIR" -type f \( -name "*.fa" -o -name "*.fasta" \))

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

echo "全部任务提交完成，TAMA polyA 清理完成"