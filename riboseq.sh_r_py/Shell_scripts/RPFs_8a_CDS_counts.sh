#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#run summing_CDS_counts.py script to count all reads for each CDS for use with DEseq2
#the -remove_end_codons doesn't count any reads which correspond to A-site occupation within the first 20 or last 10 codons
#运行 summing_CDS_counts.py 以统计每个 CDS 的所有 reads，用于 DESeq2；-remove_end_codons 选项会排除位于 CDS 前 20 个和后 10 个密码子（A 位点）的 reads。

for filename in $RPF_filenames
do
summing_CDS_counts.py ${filename}_pc_final.counts $region_lengths -remove_end_codons -in_dir $counts_dir -out_dir $cds_counts_dir &
done
wait
