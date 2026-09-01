#!/bin/bash

# 定义 SRR 列表文件、SRA 输入目录和 FASTQ 输出目录
SRR_LIST="SRR_Acc_List.txt"
SRA_INPUT_DIR="."  # SRA 文件在当前目录的子文件夹中
FASTQ_OUTPUT_DIR="fastq_files"
FAILED_FILE="failed_conversions.txt"

# 检查 SRR 列表文件是否存在
if [ ! -f "$SRR_LIST" ]; then
    echo "错误：$SRR_LIST 文件不存在于当前目录。"
    exit 1
fi

# 创建输出目录（如果不存在）
mkdir -p "$FASTQ_OUTPUT_DIR"

# 清空之前的失败记录文件
> "$FAILED_FILE"

# 定义 fastq-dump 的路径和选项
# 根据你的目录结构，fastq-dump 在 sratoolkit.3.2.0-centos_linux64/bin/ 目录下
FASTQ_DUMP="./sratoolkit.3.2.0-centos_linux64/bin/fastq-dump"

# 选项说明：
# --split-3: 对于双端数据，会生成 *_1.fastq, *_2.fastq 和未配对的 *.fastq。对于单端数据，只生成一个 *.fastq。这是最安全的选项。
# --gzip: 直接生成 .fastq.gz 压缩文件，非常节省空间。
# -O: 指定输出目录。

# 读取 SRR ID 列表并进行转换
while IFS= read -r srr_id; do
    # 跳过空行
    if [ -z "$srr_id" ]; then
        continue
    fi

    echo "--------------------------------------------------"
    echo "正在处理: $srr_id"
    
    # 定义 SRA 文件路径和 FASTQ 输出前缀
    sra_file_path="${SRA_INPUT_DIR}/${srr_id}/${srr_id}.sra"
    fastq_output_prefix="${FASTQ_OUTPUT_DIR}/${srr_id}"

    # 检查 SRA 文件是否存在
    if [ ! -f "$sra_file_path" ]; then
        echo "错误：SRA 文件 $sra_file_path 不存在。"
        echo "$sra_id" >> "$FAILED_FILE"
        continue
    fi

    # 执行转换命令
    $FASTQ_DUMP --split-3 --gzip -O "$FASTQ_OUTPUT_DIR" "$sra_file_path"
    
    # 检查上一个命令是否成功执行
    if [ $? -eq 0 ]; then
        echo "$srr_id 转换成功。"
    else
        echo "错误：$srr_id 转换失败！"
        echo "$srr_id" >> "$FAILED_FILE"
    fi

done < "$SRR_LIST"

echo "--------------------------------------------------"
echo "所有转换任务已完成。"
if [ -s "$FAILED_FILE" ]; then
    echo "转换失败的 SRR ID 已记录在 $FAILED_FILE 文件中。"
else
    echo "所有文件均转换成功！"
    rm "$FAILED_FILE" # 删除空的失败记录文件
fi
