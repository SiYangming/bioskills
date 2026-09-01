#!/usr/bin/env bash

#This script uses STAR to align reads to a genome, which may be neccessary to check for specific knockouts, where specific exons have been removed etc
#该脚本使用 STAR 将 reads 比对到基因组，用于检查特定外显子缺失等基因敲除情况。
#It is worth creating a new conda environment just for STAR
#建议为 STAR 单独创建一个 conda 环境。
#for more info on STAR see https://physiology.med.cornell.edu/faculty/skrabanek/lab/angsd/lecture_notes/STARmanual.pdf
#更多 STAR 说明见 https://physiology.med.cornell.edu/faculty/skrabanek/lab/angsd/lecture_notes/STARmanual.pdf。

#"--outFilterMultimapNmax" sets maximum number of loci the read is allowed to map to (default is 20, but we set to 5 to be more stringent)
#\"--outFilterMultimapNmax\" 设置 read 允许比对的最大位点数（默认 20，此处设为 5 更为严格）。
#"--outFilterMismatchNmax" sets the maximum number of mismatches (default is 10, but we set to 5 to be more stringent)
#\"--outFilterMismatchNmax\" 设置允许的最大错配数（默认 10，此处设为 5 更为严格）。
#"--outSAMprimaryFlag AllBestScore" will output all alignments with the best score as primary alignments, rather than default behaviour which will only mark one alignment as primary
#\"--outSAMprimaryFlag AllBestScore\" 会将所有得分最好的比对都标记为主比对，而不是默认只标记一个。
#"--alignEndsType EndToEnd" forces end-to-end read alignment, do not soft-clip
#\"--alignEndsType EndToEnd\" 强制端到端比对，不进行软剪切。
#"--outSAMtype BAM Unsorted" outputs an unsorted <.bam> file
#\"--outSAMtype BAM Unsorted\" 输出未排序的 <.bam> 文件。
#"--outSAMunmapped None" means unmapped reads are not output (set as default)
#\"--outSAMunmapped None\" 表示不输出未比对的 reads（此处作为默认设置）。

#samtools then sorts and indexes the <.bam> file
#随后使用 samtools 对 <.bam> 文件进行排序和建索引。

#read in variables
#读取公共变量
source common_variables.sh

#Align to genome
#比对到基因组
for filename in $Totals_filenames
do
STAR --readFilesIn $fastq_dir/${filename}_UMI_clipped.fastq --runThreadN $threadN --genomeDir $STAR_index --outFilterMultimapNmax 5 --outFilterMismatchNmax 5 --outSAMprimaryFlag AllBestScore --alignEndsType EndToEnd --outSAMtype BAM Unsorted --outSAMunmapped None --sjdbGTFfile $STAR_GTF --outFileNamePrefix $STAR_dir/${filename}
done

#sort bam
#排序 bam
for filename in $Totals_filenames
do
samtools sort $STAR_dir/${filename}Aligned.out.bam -o $BAM_dir/${filename}_genome_sorted.bam -@ $threadN -m 1G
done

#index bam
#建立 bam 索引
for filename in $Totals_filenames
do
samtools index $BAM_dir/${filename}_genome_sorted.bam $BAM_dir/${filename}_genome_sorted.bai &
done
wait
