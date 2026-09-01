#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#concatenate seperate fastq files into one
#将多个 fastq 文件合并为一个
cat ${fastq_dir}/RPFs_1a.fastq ${fastq_dir}/RPFs_1b.fastq > ${fastq_dir}/RPFs_1.fastq
cat ${fastq_dir}/RPFs_2a.fastq ${fastq_dir}/RPFs_2b.fastq > ${fastq_dir}/RPFs_2.fastq

