#!/bin/bash
set -euo pipefail  # 严格模式：报错即退出，避免未定义变量、管道错误

###########################################################################
# 1. 配置参数（根据实际情况修改，支持压缩参考基因组+BAM输出）
###########################################################################
MINIMAP2_PATH="$HOME/miniconda3/envs/pacbio_iso_seq/bin/minimap2"
SAMTOOLS_PATH="$HOME/miniconda3/envs/pacbio_iso_seq/bin/samtools"
REF_GENOME="./hg38.gz"  # 支持压缩版（.fa.gz/.fa.bz2）或非压缩版（.fa）
FASTQ_DIR="./fastq_files"  # FASTQ 文件目录（支持压缩版 .fastq.gz）
OUTPUT_DIR="./alignment_results_bam"  # 输出目录（BAM文件+统计结果+日志）
THREADS=9  # 并行任务数（对应9个文件，满负载运行）
SORT_THREADS=1  # 每个BAM排序任务的线程数（总线程=9*1=9，避免资源竞争）

###########################################################################
# 2. 依赖检查（避免运行中报错）
###########################################################################
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "ERROR: 工具 $1 未找到！请检查路径是否正确。"
        exit 1
    fi
}

# 检查核心工具
check_dependency "$MINIMAP2_PATH"
check_dependency "$SAMTOOLS_PATH"
check_dependency "parallel"  # 依赖 GNU Parallel 实现并行

# 检查参考基因组（支持压缩/非压缩）
if [ ! -f "$REF_GENOME" ]; then
    echo "ERROR: 参考基因组 $REF_GENOME 不存在！请确认文件路径。"
    exit 1
fi

# 检查 FASTQ 文件（支持 .fastq.gz 压缩）
FASTQ_FILES=("$FASTQ_DIR"/*.fastq.gz)
if [ ${#FASTQ_FILES[@]} -eq 0 ]; then
    echo "ERROR: $FASTQ_DIR 目录下未找到 .fastq.gz 文件！"
    exit 1
fi

###########################################################################
# 3. 创建输出目录（分类存储BAM、统计结果、日志）
###########################################################################
mkdir -p "$OUTPUT_DIR"/{bam,sorted_bam,flagstat,logs}
echo "===== 输出目录已创建：$OUTPUT_DIR ====="
echo "  - 未排序BAM：$OUTPUT_DIR/bam（可选保留，默认后续删除）"
echo "  - 坐标排序BAM：$OUTPUT_DIR/sorted_bam（推荐保留，方便后续分析）"
echo "  - 比对统计：$OUTPUT_DIR/flagstat"
echo "  - 运行日志：$OUTPUT_DIR/logs"

###########################################################################
# 4. 定义单个文件的处理函数（比对→直接转BAM→排序→统计）
###########################################################################
process_sample() {
    local fastq_file="$1"  # 输入FASTQ文件（.fastq.gz）
    local sample_name=$(basename "$fastq_file" .fastq.gz)  # 提取样本名（如 SRR36103949）
    local bam_file="$OUTPUT_DIR/bam/$sample_name.bam"  # 未排序BAM（临时）
    local sorted_bam="$OUTPUT_DIR/sorted_bam/$sample_name.sorted.bam"  # 坐标排序BAM
    local flagstat_file="$OUTPUT_DIR/flagstat/$sample_name.flagstat.txt"  # 统计结果
    local log_file="$OUTPUT_DIR/logs/$sample_name.log"  # 单样本日志

    echo "===== 开始处理样本：$sample_name（$(date +%Y-%m-%d_%H:%M:%S)）=====" >> "$log_file"

    # 步骤1：minimap2 比对 → 管道直接转BAM（不存中间SAM）
    echo "Running minimap2 alignment → 直接输出BAM..." >> "$log_file"
    "$MINIMAP2_PATH" \
        -ax splice -uf -k14 \
        "$REF_GENOME" \
        "$fastq_file" 2>> "$log_file" |  # minimap2 输出SAM到管道，错误日志写入文件
    "$SAMTOOLS_PATH" view -@ "$SORT_THREADS" -b -o "$bam_file" - 2>> "$log_file"  # 实时转BAM
    # samtools view 参数说明：
    # -@：排序线程数；-b：输出BAM格式；-o：输出文件；-：从管道读取SAM输入

    # 步骤2：BAM坐标排序（方便后续IGV可视化、变异检测等分析）
    echo "Sorting BAM file..." >> "$log_file"
    "$SAMTOOLS_PATH" sort -@ "$SORT_THREADS" -o "$sorted_bam" "$bam_file" 2>> "$log_file"
    # 生成BAM索引（.bai，可视化必需）
    "$SAMTOOLS_PATH" index "$sorted_bam" 2>> "$log_file"

    # 步骤3：samtools flagstat 统计（基于排序后BAM，结果更规范）
    echo "Running samtools flagstat..." >> "$log_file"
    "$SAMTOOLS_PATH" flagstat "$sorted_bam" > "$flagstat_file" 2>> "$log_file"

    # 步骤4：清理临时文件（删除未排序BAM，节省磁盘空间；如需保留，注释此行）
    rm -f "$bam_file"
    echo "Deleted temporary unsorted BAM: $bam_file" >> "$log_file"

    echo "===== 样本 $sample_name 处理完成（$(date +%Y-%m-%d_%H:%M:%S)）=====" >> "$log_file"
}

# 导出函数和变量（让 GNU Parallel 能调用）
export -f process_sample
export MINIMAP2_PATH SAMTOOLS_PATH REF_GENOME OUTPUT_DIR SORT_THREADS

###########################################################################
# 5. 并行执行所有样本（同时运行 THREADS=9 个任务）
###########################################################################
echo "===== 开始并行处理 ${#FASTQ_FILES[@]} 个样本（并行任务数：$THREADS）====="
echo "参考基因组：$REF_GENOME（支持压缩格式，自动生成索引）"
echo "任务启动时间：$(date +%Y-%m-%d_%H:%M:%S)"

# 用 GNU Parallel 批量执行，--progress 显示进度
printf "%s\n" "${FASTQ_FILES[@]}" | \
    parallel -j "$THREADS" \
    --progress \
    --bar \
    process_sample {}

###########################################################################
# 6. 任务完成总结
###########################################################################
echo "===== 所有样本处理完成！（$(date +%Y-%m-%d_%H:%M:%S)）====="
echo "结果汇总："
echo "  - 坐标排序BAM：$OUTPUT_DIR/sorted_bam（含 .bai 索引，共 ${#FASTQ_FILES[@]} 对）"
echo "  - 比对统计：$OUTPUT_DIR/flagstat（共 ${#FASTQ_FILES[@]} 个 flagstat 文件）"
echo "  - 运行日志：$OUTPUT_DIR/logs（单样本详细日志）"
echo "  - 总览统计：可执行命令查看所有样本的比对率："
echo "    cat $OUTPUT_DIR/flagstat/*.flagstat.txt | grep 'mapped (' | awk -F ' ' '{print FILENAME, $1, $2}' "
