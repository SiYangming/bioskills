#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#rename the totals files
#重命名 totals fastq 文件
mv ${fastq_dir}/SRR00001.fastq ${fastq_dir}/RPFs_1.fastq
mv ${fastq_dir}/SRR00002.fastq ${fastq_dir}/RPFs_2.fastq
