#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#set offset
#设置 offset（偏移量）
offset=15

#run periodicity.py script
#运行 periodicity.py 脚本
for filename in $RPF_filenames
do
for length in $(seq 25 35)
do
periodicity.py ${filename}_pc_L${length}_Off0.counts $region_lengths -offset $offset -in_dir $counts_dir -out_dir $periodicity_dir &
done
done
wait
