#!/bin/bash

# --- 配置区 ---
SRR_LIST="SRR_Acc_List.txt"
SRA_INPUT_DIR="."
FASTQ_OUTPUT_DIR="fastq_files"
FAILED_FILE="failed_conversions.txt"
# 设置最大并行任务数。建议设置为你服务器的 CPU 核心数。
# 你可以通过 `nproc` 命令查看核心数。例如：MAX_PARALLEL=$(nproc)
MAX_PARALLEL=10 
# --- 配置区结束 ---

# 定义 fastq-dump 的路径
FASTQ_DUMP="./sratoolkit.3.2.0-centos_linux64/bin/fastq-dump"

# 检查必要文件和目录
if [ ! -f "$SRR_LIST" ]; then
    echo "错误：$SRR_LIST 文件不存在于当前目录。"
    exit 1
fi
mkdir -p "$FASTQ_OUTPUT_DIR"
> "$FAILED_FILE"

# 定义一个函数，用于处理单个 SRR ID
process_srr() {
    local srr_id="$1"
    
    # 跳过空行（虽然 parallel 通常不会传递空行，但为安全起见）
    if [ -z "$srr_id" ]; then
        return 0
    fi

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] 开始处理: $srr_id"
    
    local sra_file_path="${SRA_INPUT_DIR}/${srr_id}/${srr_id}.sra"

    if [ ! -f "$sra_file_path" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] 错误: SRA 文件 $sra_file_path 不存在。"
        echo "$srr_id" >> "$FAILED_FILE"
        return 1
    fi

    # 执行转换命令
    $FASTQ_DUMP --split-3 --gzip -O "$FASTQ_OUTPUT_DIR" "$sra_file_path"
    
    if [ $? -eq 0 ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] 成功: $srr_id"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] 失败: $srr_id"
        echo "$srr_id" >> "$FAILED_FILE"
    fi
}

# 导出函数，使其能被 parallel 调用
export -f process_srr
export FASTQ_DUMP FASTQ_OUTPUT_DIR SRA_INPUT_DIR FAILED_FILE

# 使用 parallel 并行处理 SRR 列表
# -a: 指定输入文件
# -P: 指定并行数
# {}: 代表从文件中读取的每一行（即每个 SRR ID）
echo "开始并行处理，最大并行数: $MAX_PARALLEL"
cat "$SRR_LIST" | parallel -a - -P "$MAX_PARALLEL" process_srr {}

echo "--------------------------------------------------"
echo "所有并行任务已完成。"
if [ -s "$FAILED_FILE" ]; then
    echo "转换失败的 SRR ID 已记录在 $FAILED_FILE 文件中。"
else
    echo "所有文件均转换成功！"
    rm "$FAILED_FILE"
fi
