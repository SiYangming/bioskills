#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#set offset
#设置 offset（偏移量）
offset=15

#run summing_region_counts.py script
#运行 summing_region_counts.py 脚本
for filename in $RPF_filenames
do
for length in $(seq 25 35)
do
summing_region_counts.py ${filename}_pc_L${length}_Off0.counts $offset $region_lengths -in_dir $counts_dir -out_dir $region_counts_dir &
done
done
wait
