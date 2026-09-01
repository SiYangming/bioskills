#!/bin/bash
set -euo pipefail  # 严格模式：报错即退出，避免未定义变量

###########################################################################
# 1. 配置参数（用户需根据实际情况修改以下项）
###########################################################################
# 工具路径
FLAIR_PATH="$HOME/miniconda3/envs/flair/bin/flair"
BAM2BED12_PATH="$HOME/miniconda3/envs/flair/bin/bam2Bed12"
IDENTIFY_GENE_SCRIPT="$HOME/miniconda3/envs/flair/bin/identify_gene_isoform"
MINIMAP2_PATH="$HOME/miniconda3/envs/pacbio_iso_seq/bin/minimap2"  # 需用`which minimap2`验证路径

# 数据文件路径
GTF_ANNOTATION="./gencode.v49.annotation.gtf"
GENOME_FASTA="./hg38"  # 确保文件存在且有读权限

# 输入输出目录
INPUT_BAM_DIR="./alignment_results_bam/sorted_bam"
RAW_READS_DIR="./fastq_files"
OUTPUT_DIR="./flair_consensus"
MASTER_LOG="./flair_nohup_master.log"
PID_FILE="./flair_nohup.pid"

# 运行参数
THREADS=9
FLAIR_THREADS=20
MIN_SUPPORT=3
INTPRIMING_THRESHOLD=30
END_WINDOW=100

###########################################################################
# 2. 后台运行封装（保持不变）
###########################################################################
if [ "${1:-}" != "run" ]; then
    echo "===== 启动Flair批量处理（人类direct RNA-seq模式）====="
    echo "主日志文件：$MASTER_LOG"
    echo "进程ID文件：$PID_FILE"
    echo "输出结果目录：$OUTPUT_DIR"
    echo "注意：脚本已自动配置目录权限，请确保当前用户有读写权限"
    echo "======================================"

    nohup "$0" run > "$MASTER_LOG" 2>&1 &
    echo $! > "$PID_FILE"
    echo "后台任务已启动！进程ID：$(cat "$PID_FILE")"
    echo "查看实时进度：tail -f $MASTER_LOG"
    exit 0
fi

###########################################################################
# 3. 依赖检查（补充权限验证）
###########################################################################
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: 工具 $1 未找到！请检查路径是否正确。"
        exit 1
    fi
}

echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始依赖检查（人类direct RNA-seq模式）..."
# 检查核心工具
check_dependency "$FLAIR_PATH"
check_dependency "$BAM2BED12_PATH"
check_dependency "parallel"
check_dependency "$MINIMAP2_PATH"  # 直接检查minimap2路径

# 检查数据文件权限
if [ ! -r "$GTF_ANNOTATION" ]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: GTF注释文件无读权限！$GTF_ANNOTATION"
    exit 1
fi
if [ ! -r "$GENOME_FASTA" ]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: 参考基因组无读权限！$GENOME_FASTA"
    exit 1
fi

# 检查BAM和reads文件
BAM_FILES=("$INPUT_BAM_DIR"/*.sorted.bam)
if [ ${#BAM_FILES[@]} -eq 0 ]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: $INPUT_BAM_DIR 下未找到 .sorted.bam 文件！"
    exit 1
fi
for bam in "${BAM_FILES[@]}"; do
    sample=$(basename "$bam" .sorted.bam)
    reads_file="$RAW_READS_DIR/$sample.fastq.gz"
    if [ ! -r "$reads_file" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: 样本 $sample 缺少reads或无读权限：$reads_file"
        exit 1
    fi
done
echo "[$(date +%Y-%m-%d_%H:%M:%S)] 依赖检查通过！"

###########################################################################
# 4. 创建输出目录（关键修复：添加权限配置）
###########################################################################
# 强制创建目录并赋予读写执行权限（解决权限不足问题）
mkdir -p "$OUTPUT_DIR"/{bed12,annotated_bed,consensus_fasta,logs}
chmod -R 755 "$OUTPUT_DIR"  # 关键：递归赋予目录权限，所有用户可读写执行
echo "[$(date +%Y-%m-%d_%H:%M:%S)] 输出目录已创建并配置权限：$OUTPUT_DIR"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - Bed12文件：$OUTPUT_DIR/bed12"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 带注释Bed：$OUTPUT_DIR/annotated_bed"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 一致性序列：$OUTPUT_DIR/consensus_fasta"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 运行日志：$OUTPUT_DIR/logs"

###########################################################################
# 5. 单个样本处理函数（核心修复：命令语法+权限）
###########################################################################
process_flair() {
    local bam_file="$1"
    local sample_name=$(basename "$bam_file" .sorted.bam)
    
    # 关联文件路径
    local raw_reads="$RAW_READS_DIR/$sample_name.fastq.gz"
    local bed12_file="$OUTPUT_DIR/bed12/$sample_name.bed12"
    local annotated_bed="$OUTPUT_DIR/annotated_bed/$sample_name.annotated.bed"
    local consensus_prefix="$OUTPUT_DIR/consensus_fasta/$sample_name"
    local log_file="$OUTPUT_DIR/logs/$sample_name.log"

    echo "===== 开始处理样本：$sample_name（人类direct RNA-seq）=====" >> "$log_file"

    # 步骤1：BAM→Bed12（修复权限：确保输出文件可写）
    echo "Step 1: BAM→Bed12格式转换..." >> "$log_file"
    if ! "$BAM2BED12_PATH" -i "$bam_file" > "$bed12_file" 2>> "$log_file"; then
        echo "ERROR: BAM→Bed12转换失败！请检查bam文件权限和格式" >> "$log_file"
        exit 1
    fi
    if [ ! -s "$bed12_file" ]; then
        echo "ERROR: Bed12文件为空！可能BAM文件无有效reads" >> "$log_file"
        exit 1
    fi

    # 步骤2：基因注释（修复：确保脚本可执行+权限）
    echo "Step 2: 运行identify_gene_isoform添加基因注释..." >> "$log_file"
    # 先给注释脚本添加执行权限
    chmod +x "$IDENTIFY_GENE_SCRIPT" 2>/dev/null
    if ! "$IDENTIFY_GENE_SCRIPT" \
        "$bed12_file" \
        "$GTF_ANNOTATION" \
        "$annotated_bed" \
        2>> "$log_file"; then
        echo "ERROR: 基因注释步骤失败！请检查GTF文件格式" >> "$log_file"
        exit 1
    fi
    if [ ! -s "$annotated_bed" ]; then
        echo "ERROR: 带注释Bed文件为空！可能无匹配的基因注释" >> "$log_file"
        exit 1
    fi

    # 步骤3：Flair collapse（核心修复：命令语法+权限）
    echo "Step 3: Flair collapse聚类去冗余（direct RNA-seq优化参数）..." >> "$log_file"
    # 配置minimap2路径+权限
    export PATH=$(dirname "$MINIMAP2_PATH"):$PATH
    chmod +x "$MINIMAP2_PATH" 2>/dev/null  # 确保minimap2可执行

    # 修复命令语法：反斜杠后无多余空格，参数连续（关键！）
    if ! "$FLAIR_PATH" collapse \
        -q "$annotated_bed" \
        -g "$GENOME_FASTA" \
        -r "$raw_reads" \
        -o "$consensus_prefix" \
        -t "$FLAIR_THREADS" \
        -f "$GTF_ANNOTATION" \
        -s "$MIN_SUPPORT" \
        -w "$END_WINDOW" \
        --trust_ends \
        --remove_internal_priming \
        --intprimingthreshold "$INTPRIMING_THRESHOLD" \
        --stringent \
        --check_splice \
        --mm2_args="-I8g,--MD" \
        --quiet 2>> "$log_file"; then
        echo "ERROR: Flair collapse步骤失败！请查看日志详情" >> "$log_file"
        exit 1
    fi

    # 验证结果
    local consensus_fasta="$consensus_prefix.flair.collapse.fasta"
    if [ ! -s "$consensus_fasta" ]; then
        echo "ERROR: 一致性序列文件为空！可能无有效isoform（支持数≥$MIN_SUPPORT）" >> "$log_file"
        exit 1
    fi

    echo "===== 样本 $sample_name 处理完成（人类direct RNA-seq）=====" >> "$log_file"
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 样本 $sample_name 处理完成！"
}

# 导出函数和变量
export -f process_flair
export FLAIR_PATH BAM2BED12_PATH IDENTIFY_GENE_SCRIPT PYTHON_PATH MINIMAP2_PATH
export GTF_ANNOTATION GENOME_FASTA RAW_READS_DIR OUTPUT_DIR
export FLAIR_THREADS MIN_SUPPORT END_WINDOW INTPRIMING_THRESHOLD

###########################################################################
# 6. 并行执行所有样本（保持不变）
###########################################################################
echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始并行处理 ${#BAM_FILES[@]} 个人类direct RNA-seq样本 ====="
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 并行任务数：$THREADS"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - Flair线程数：$FLAIR_THREADS"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 参考基因组：$GENOME_FASTA"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 原始reads目录：$RAW_READS_DIR"

printf "%s\n" "${BAM_FILES[@]}" | \
    parallel -j "$THREADS" --progress --bar process_flair {}

###########################################################################
# 7. 任务完成总结
###########################################################################
echo "[$(date +%Y-%m-%d_%H:%M:%S)] ===== 所有人类direct RNA-seq样本处理完成！====="
echo "[$(date +%Y-%m-%d_%H:%M:%S)] 结果汇总："
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - Bed12文件：$OUTPUT_DIR/bed12（共 ${#BAM_FILES[@]} 个）"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 带注释Bed：$OUTPUT_DIR/annotated_bed（共 ${#BAM_FILES[@]} 个）"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 一致性序列：$OUTPUT_DIR/consensus_fasta（每个样本1个fasta文件）"
echo "[$(date +%Y-%m-%d_%H:%M:%S)]   - 运行日志：$OUTPUT_DIR/logs（单样本详细日志）"

# 快速验证第一个样本
first_sample=$(basename "${BAM_FILES[0]}" .sorted.bam)
first_fasta="$OUTPUT_DIR/consensus_fasta/$first_sample.flair.collapse.fasta"
if [ -s "$first_fasta" ]; then
    seq_count=$(grep -c ">" "$first_fasta")
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 快速验证：样本 $first_sample 一致性序列条数 = $seq_count"
else
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 警告：样本 $first_sample 序列文件为空！请检查日志"
fi

echo "[$(date +%Y-%m-%d_%H:%M:%S)] 任务全部结束！"
