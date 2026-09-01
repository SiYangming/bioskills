#!/usr/bin/env bash

#This script extracts the read counts at each stage of the pipeline from the log files. It is paired with the Totals_read_counts.R, which will will then make plots for this QC.
#该脚本从日志文件中提取流程各阶段的读数信息，并与 Totals_read_counts.R 配合使用，对这些 QC 指标进行可视化。

#read in variables
#读取公共变量
source common_variables.sh

#Extract the read counts from the log files for each sample
#从每个样本的日志文件中提取读数。
for filename in $Totals_filenames
do
extract_read_counts.py ${filename} Totals -log_dir $log_dir &
done
wait
