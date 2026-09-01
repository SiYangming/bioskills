#!/usr/bin/env bash

#This script extracts the read counts at each stage of the pipeline from the log files. It is paired with the RPF_read_counts.R, which will will then make plots for this QC.
#该脚本从各步骤生成的日志文件中提取 reads 计数，与 RPF_read_counts.R 配套使用，用于绘制对应的 QC 图。

#read in variables
#读取公共变量
source common_variables.sh

#Extract the read counts from the log files for each sample
#为每个样本从日志文件中提取 reads 计数
for filename in $RPF_filenames
do
extract_read_counts.py ${filename} RPFs -log_dir $log_dir &
done
wait
