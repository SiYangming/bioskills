#!/usr/bin/env bash

#This script uses UMItools to deduplicate the genome <.bam> file
#该脚本使用 UMItools 对基因组 <.bam> 文件进行去重。
#It then uses samtools to sort and index the deduplicated <.bam> file (this deduplicated and sorted <.bam> file is what you would load into IGV)
#随后使用 samtools 对去重后的 <.bam> 文件进行排序和建索引（在 IGV 中查看的就是该去重且排序后的 <.bam> 文件）。

#read in variables
#读取公共变量
source common_variables.sh

#run UMI tools deduplication function
#运行 UMI-tools 去重复功能
for filename in $Totals_filenames
do
umi_tools dedup -I $BAM_dir/${filename}_genome_sorted.bam -S $BAM_dir/${filename}_genome_deduplicated.bam --output-stats=$log_dir/${filename}_genome_deduplication 1> $log_dir/${filename}_genome_deduplication_log.txt &
done
wait

#sort bam
#排序 bam
for filename in $Totals_filenames
do
samtools sort $BAM_dir/${filename}_genome_deduplicated.bam -o $BAM_dir/${filename}_genome_deduplicated_sorted.bam -@ $threadN -m 1G
done

#index bam
#建立 bam 索引
for filename in $Totals_filenames
do
samtools index $BAM_dir/${filename}_genome_deduplicated_sorted.bam $BAM_dir/${filename}_genome_deduplicated_sorted.bai &
done
wait
