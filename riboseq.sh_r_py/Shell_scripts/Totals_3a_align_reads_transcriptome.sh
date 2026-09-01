#!/usr/bin/env bash

#This script uses bowtie2 to align reads.
#该脚本使用 bowtie2 对 reads 进行比对。
#-S specifies the <.sam> output file name
#-S 指定输出的 <.sam> 文件名。
#-U specificies the input <.fastq> file.
#-U 指定输入的 <.fastq> 文件。
#-x specifies the index to use as a reference. This is the same one as used for rsem to calculate isoform expression
#-x 指定用作参考的索引，与后续 RSEM 计算 isoform 表达所用索引一致。
#--threads specifies the number of threads
#--threads 指定使用的线程数。
#"--sensitive --dpad 0 --gbar 99999999 --mp 1,1 --np 1 --score-min L,0,-0.1" are the arguments recommended if using rsem downstream
#\"--sensitive --dpad 0 --gbar 99999999 --mp 1,1 --np 1 --score-min L,0,-0.1\" 为推荐的参数组合，便于后续配合 RSEM 使用。

#it then uses samtools to sort and index the <.bam> file
#随后使用 samtools 对生成的 <.bam> 文件进行排序并建立索引。

#read in variables
#读取公共变量
source common_variables.sh

#Align to protein coding transcriptome
#比对到蛋白编码转录组
for filename in $Totals_filenames
do
bowtie2 -S $SAM_dir/${filename}_pc.sam -U $fastq_dir/${filename}_UMI_clipped.fastq -x $rsem_index --threads $threadN --sensitive --dpad 0 --gbar 99999999 --mp 1,1 --np 1 --score-min L,0,-0.1 2> $log_dir/${filename}_pc_log.txt
done

#convert sam to bam 
#将 sam 转换为 bam
for filename in $Totals_filenames
do
samtools view -b $SAM_dir/${filename}_pc.sam > $BAM_dir/${filename}_pc.bam &
done
wait

#sort bam
#排序 bam
for filename in $Totals_filenames
do
samtools sort $BAM_dir/${filename}_pc.bam -o $BAM_dir/${filename}_pc_sorted.bam -@ $threadN -m 1G
done

#index bam
#建立 bam 索引
for filename in $Totals_filenames
do
samtools index $BAM_dir/${filename}_pc_sorted.bam $BAM_dir/${filename}_pc_sorted.bai &
done
wait
