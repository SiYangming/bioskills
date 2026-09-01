#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

#run cutadapt
#运行 cutadapt
for filename in $RPF_filenames
do
cutadapt $fastq_dir/${filename}.fastq -a $RPF_adaptor --nextseq-trim=20 -m 30 -M 50 --cores=0 -o $fastq_dir/${filename}_cutadapt.fastq 1> $log_dir/${filename}_cutadapt_log.txt
done

#extract UMIs
#提取 UMI
for filename in $RPF_filenames
do
umi_tools extract -I $fastq_dir/${filename}_cutadapt.fastq --extract-method=regex --bc-pattern='^(?P<umi_1>.{4}).+(?P<umi_2>.{4})$' -S $fastq_dir/${filename}_UMI_clipped.fastq --log=$log_dir/${filename}_extracted_UMIs.log &
done
wait

#Align to rRNA
#比对到 rRNA
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_UMI_clipped.fastq ref=$rRNA_fasta outm=$fastq_dir/${filename}_rRNA.fastq outu=$fastq_dir/${filename}_non_rRNA.fastq ambiguous=best nodisk threads=$threadN 2> $log_dir/${filename}_rRNA_log.txt
done

#Align to tRNA fasta
#比对到 tRNA fasta
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_non_rRNA.fastq ref=$tRNA_fasta outm=$fastq_dir/${filename}_tRNA.fastq outu=$fastq_dir/${filename}_non_rRNA_tRNA.fastq ambiguous=best nodisk threads=$threadN 2> $log_dir/${filename}_tRNA_log.txt
done

#Align to protein coding transcriptome
#比对到蛋白编码转录组
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_non_rRNA_tRNA.fastq out=$BAM_dir/${filename}_pc.bam ref=$most_abundant_fasta outm=$fastq_dir/${filename}_pc.fastq outu=$fastq_dir/${filename}_unaligned.fastq ambiguous=best nodisk trimreaddescription=t threads=$threadN 2> $log_dir/${filename}_pc_log.txt
done

#sort bam
#排序 bam
for filename in $RPF_filenames
do
samtools sort $BAM_dir/${filename}_pc.bam -o $BAM_dir/${filename}_pc_sorted.bam -@ $threadN -m 1G
done

#index bam
#建立 bam 索引
for filename in $RPF_filenames
do
samtools index $BAM_dir/${filename}_pc_sorted.bam $BAM_dir/${filename}_pc_sorted.bai &
done
wait

#run UMI tools deduplication function
#运行 UMI-tools 去重复功能
for filename in $RPF_filenames
do
umi_tools dedup -I $BAM_dir/${filename}_pc_sorted.bam -S $BAM_dir/${filename}_pc_deduplicated.bam --output-stats=$log_dir/${filename}_deduplication 1> $log_dir/${filename}_deduplication_log.txt &
done
wait

#sort bam
#排序 bam
for filename in $RPF_filenames
do
samtools sort $BAM_dir/${filename}_pc_deduplicated.bam -o $BAM_dir/${filename}_pc_deduplicated_sorted.bam -@ $threadN -m 1G
done

#index bam
#建立 bam 索引
for filename in $RPF_filenames
do
samtools index $BAM_dir/${filename}_pc_deduplicated_sorted.bam $BAM_dir/${filename}_pc_deduplicated_sorted.bai &
done
wait

#make an fai (fasta index) file from the fasta using samtools. This is required for the counting script and needs to exist before running counting_script.py
#使用 samtools 为 fasta 生成 fai（fasta 索引）文件。这是计数脚本所需，在运行 counting_script.py 之前必须存在。
samtools faidx $most_abundant_fasta

#run the counting_script.py with a range of read lengths (adjust below if required, currently set to 25-35)
#在一系列 read 长度上运行 counting_script.py（可根据需要调整，目前为 25–35）。
for filename in $RPF_filenames
do
for length in $(seq 25 35)
do
counting_script.py -bam $BAM_dir/${filename}_pc_deduplicated_sorted.bam -fasta $most_abundant_fasta -len $length -out_file ${filename}_pc_L${length}_Off0.counts -out_dir $counts_dir &
done
done
wait

#set offset
#设置 offset
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

#set number of nt to splice
#设置要剪切的碱基数 nt
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

#Extract the read counts from the log files for each sample
#从每个样本的日志文件中提取读数。
for filename in $RPF_filenames
do
extract_read_counts.py ${filename} RPFs -log_dir $log_dir &
done
wait
