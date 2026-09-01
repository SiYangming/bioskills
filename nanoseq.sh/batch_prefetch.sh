#!/bin/bash

# 检查 SRR 列表文件是否存在
if [ ! -f "SRR_Acc_List.txt" ]; then
    echo "错误：SRR_Acc_List.txt 文件不存在于当前目录。"
    exit 1
fi

# 定义要使用的 prefetch 选项
# -f yes: 强制重新下载，如果文件已存在且完整，也会重新下载
# -t http: 仅使用 HTTP 协议下载 (如果 ascp 有问题，可以用这个)
# 你可以根据需要修改或添加其他选项，例如 -a 指定 ascp 路径
PREFETCH_OPTIONS="-f yes -t http"

# 读取 SRR_Acc_List.txt 文件的每一行
while IFS= read -r srr_id; do
    # 跳过空行
    if [ -z "$srr_id" ]; then
        continue
    fi

    echo "--------------------------------------------------"
    echo "正在下载: $srr_id"
    echo "--------------------------------------------------"
    
    # 执行 prefetch 命令
    ./sratoolkit.3.2.0-centos_linux64/bin/prefetch $PREFETCH_OPTIONS "$srr_id"
    
    # 检查上一个命令是否成功执行
    if [ $? -eq 0 ]; then
        echo "$srr_id 下载成功。"
    else
        echo "$srr_id 下载失败！"
        # 将失败的 ID 记录到文件中
        echo "$srr_id" >> failed_downloads.txt
    fi

done < "SRR_Acc_List.txt"

echo "--------------------------------------------------"
echo "所有任务已完成。"
if [ -f "failed_downloads.txt" ]; then
    echo "下载失败的 SRR ID 已记录在 failed_downloads.txt 文件中。"
fi
