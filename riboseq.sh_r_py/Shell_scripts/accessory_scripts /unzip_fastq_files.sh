#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#unzip files
#解压 fastq 文件
for filename in $RPF_filenames
do
gunzip $fastq_dir/${filename}.fastq.gz &
done
wait
