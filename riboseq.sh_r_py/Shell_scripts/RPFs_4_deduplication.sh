#!/usr/bin/env bash

#This script uses UMItools to deduplicate the protein coding <.bam> file
#该脚本使用 UMItools 对蛋白编码 <.bam> 文件进行去重复。
#It then uses samtools to sort the <.bam> files and make <.bai> index files.
#随后使用 samtools 对 <.bam> 文件排序并生成对应的 <.bai> 索引文件。
#When using the sorted <.bam> file as input to the counting_script.py script, ensure the corresponding <.bai> (index file) is in the same directory
#在将排序后的 <.bam> 作为 counting_script.py 的输入时，请确保对应的 <.bai> 索引文件与其位于同一目录。

#read in variables
#读取公共变量
source common_variables.sh

#run UMI tools deduplication function
#运行 UMItools 的去重复功能
for filename in $RPF_filenames
do
umi_tools dedup -I $BAM_dir/${filename}_pc_sorted.bam -S $BAM_dir/${filename}_pc_deduplicated.bam --output-stats=$log_dir/${filename}_deduplication 1> $log_dir/${filename}_deduplication_log.txt &
done
wait

#sort bam
for filename in $RPF_filenames
do
samtools sort $BAM_dir/${filename}_pc_deduplicated.bam -o $BAM_dir/${filename}_pc_deduplicated_sorted.bam -@ $threadN -m 1G
done

#index bam
for filename in $RPF_filenames
do
samtools index $BAM_dir/${filename}_pc_deduplicated_sorted.bam $BAM_dir/${filename}_pc_deduplicated_sorted.bai &
done
wait
