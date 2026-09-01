#!/usr/bin/env bash

#This script uses bbmap to align reads.
#该脚本使用 bbmap 对 reads 进行比对。
#in specificies the input <.fastq> file.
#in 参数指定输入的 <.fastq> 文件。
#out specificies the output <.SAM> file.
#out 参数指定输出的 <.SAM> 或 <.bam> 文件。
#ref specifies the <.fasta> file to use as a reference. bbmap will use this to make an index. As this is much quicker than other alignment programs, we use the nodisk option so that this isn't written to file
#ref 参数指定用于比对的 <.fasta> 参考序列。bbmap 会基于该文件构建索引；由于其构建速度较快，这里使用 nodisk 选项避免将索引写入磁盘。
#outm and outu specificies filenames to write <.fastq> files for all reads that either align or do not align respectively
#outm 和 outu 分别指定对齐和未对齐 reads 的 <.fastq> 输出文件名。
#ambigous specifies how to treat multimapped reads. We use best (keeps the highest scored alignment).
#ambigous 参数用于设置多重比对 reads 的处理方式；这里使用 best（保留得分最高的比对）。
#trimreaddescription=t removes any white space and following text from the fastq files when writing the <.bam> files. This is important for using UMItools downstream if any samples have come from more than one sequencing run
#trimreaddescription=t 会在写出 <.bam> 时移除 fastq 头部中的空格及其后续文字，这在某些样本来自多个测序批次且需下游使用 UMItools 时尤为重要。
#2> stores the text that is printed to the screen as a log
#2> 将标准错误输出重定向为日志文件。
#We first align to rRNA and then tRNA, spliting the reads into aligned and unaligned <.fastq> files (without outputting a <.sam> file).
#脚本首先将 reads 比对到 rRNA 和 tRNA，将其拆分为对齐与未对齐的 <.fastq> 文件（此时不输出 <.sam> 文件）。
#All non-rRNA and non-tRNA reads are then aligned to a protein coding transcriptome (prefarably a <.fasta> containing the most abundant transcripts created in the total RNA-seq pipeline).
#所有非 rRNA、非 tRNA 的 reads 随后被比对到蛋白编码转录组（推荐使用 totals 流程中生成的“最丰转录本” FASTA）。

#fastQC is then ran on all the output <.fastq> files
#随后对所有输出 <.fastq> 文件运行 fastQC。

#samtools is then used to sort and index the <.bam> file
#最后使用 samtools 对 <.bam> 文件进行排序并建立索引。

#read in variables
#读取公共变量
source common_variables.sh

#Align to rRNA
#比对到 rRNA
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_UMI_clipped.fastq ref=$rRNA_fasta outm=$fastq_dir/${filename}_rRNA.fastq outu=$fastq_dir/${filename}_non_rRNA.fastq ambiguous=best nodisk threads=$threadN 2> $log_dir/${filename}_rRNA_log.txt
done

#Align to tRNA fasta
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_non_rRNA.fastq ref=$tRNA_fasta outm=$fastq_dir/${filename}_tRNA.fastq outu=$fastq_dir/${filename}_non_rRNA_tRNA.fastq ambiguous=best nodisk threads=$threadN 2> $log_dir/${filename}_tRNA_log.txt
done

#Align to protein coding transcriptome
for filename in $RPF_filenames
do
bbmap.sh in=$fastq_dir/${filename}_non_rRNA_tRNA.fastq out=$BAM_dir/${filename}_pc.bam ref=$most_abundant_fasta outm=$fastq_dir/${filename}_pc.fastq outu=$fastq_dir/${filename}_unaligned.fastq ambiguous=best nodisk trimreaddescription=t threads=$threadN 2> $log_dir/${filename}_pc_log.txt
done

#sort bam
for filename in $RPF_filenames
do
samtools sort $BAM_dir/${filename}_pc.bam -o $BAM_dir/${filename}_pc_sorted.bam -@ $threadN -m 1G
done

#index bam
for filename in $RPF_filenames
do
samtools index $BAM_dir/${filename}_pc_sorted.bam $BAM_dir/${filename}_pc_sorted.bai &
done
wait

#run fastqc on mapped reads
for filename in $RPF_filenames
do
fastqc $fastq_dir/${filename}_rRNA.fastq --outdir=$fastqc_dir &
fastqc $fastq_dir/${filename}_tRNA.fastq --outdir=$fastqc_dir &
fastqc $fastq_dir/${filename}_pc.fastq --outdir=$fastqc_dir &
fastqc $fastq_dir/${filename}_unaligned.fastq --outdir=$fastqc_dir &
done
wait
