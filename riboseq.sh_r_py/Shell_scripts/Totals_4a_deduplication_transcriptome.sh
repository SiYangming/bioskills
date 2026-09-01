#!/usr/bin/env bash

#This script uses UMItools to deduplicate the protein coding <.bam> file
#该脚本使用 UMItools 对蛋白编码 <.bam> 文件进行去重。

#read in variables
#读取公共变量
source common_variables.sh

#run UMI tools deduplication function
#运行 UMI-tools 去重复功能
for filename in $Totals_filenames
do
umi_tools dedup -I $BAM_dir/${filename}_pc_sorted.bam -S $BAM_dir/${filename}_pc_deduplicated.bam --output-stats=$log_dir/${filename}_deduplication 1> $log_dir/${filename}_deduplication_log.txt &
done
wait
