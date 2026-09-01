#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#set number of nt to splice
#设置要裁剪（splice）的碱基数	n=50
n=50

#run summing_spliced_counts.py script
#运行 summing_spliced_counts.py 脚本
for filename in $RPF_filenames
do
for length in $(seq 25 35)
do
summing_spliced_counts.py ${filename}_pc_L${length}_Off0.counts $n $region_lengths -in_dir $counts_dir -out_dir $spliced_counts_dir &
done
done
wait
