#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

for filename in $RPF_filenames
do
counts_to_csv.py ${filename}_pc_final.counts $most_abundant_fasta -one_csv -in_dir $counts_dir -out_dir $csv_counts_dir &
done
wait
