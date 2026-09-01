#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#uses the flat text file containing the most abundant transcripts per gene created with calculate_most_abundant_transcript.R to filter the protein coding fasta
#使用 calculate_most_abundant_transcript.R 生成的“每个基因最丰度转录本”文本文件来过滤蛋白编码 fasta。

	filter_FASTA.py $pc_fasta $most_abundant_transcripts_dir/most_abundant_transcripts.txt $most_abundant_fasta

