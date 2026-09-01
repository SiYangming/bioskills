#!/usr/bin/env bash

#This script runs fastQC on all your raw fastq files and outputs them in the fastQC directory
#该脚本对所有原始 fastq 文件运行 fastQC，并将结果输出到 fastQC 目录。

#read in variables
#读取公共变量
source common_variables.sh

#run fastQC
#运行 fastQC
for filename in $RPF_filenames
do
fastqc $fastq_dir/${filename}.fastq --outdir=$fastqc_dir &
done
wait
