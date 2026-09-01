#!/usr/bin/env bash

#This script uses RSEM to calculate isoform and gene level expression from deduplicated BAM file.
#该脚本使用 RSEM 根据去重后的 BAM 文件计算转录本和基因水平的表达量。
#--strandedness describes the strand of the genome that the sequencing reads should align to. For the CORALL kit this is forward, but for a lot of standed Illumina Tru-seq kits this will be reverse. If this is not known then it is best to try both and the alignment logs should tell you which is correct
#--strandedness 描述测序 reads 应该比对到基因组的哪条链。对于 CORALL 试剂盒为 forward，而很多 Illumina TruSeq 试剂盒为 reverse；如果不确定，最好都试一下，由比对日志判断哪一个更合适。
#--fragment-length-mean 300 --fragment-length-sd 100 sets the mean and standard deviation of the library fragment size. These do not need to be exact but best estimates. These are good starting values to use for the CORALL kit
#--fragment-length-mean 300 --fragment-length-sd 100 设置文库片段长度的均值和标准差，不需要特别精确，只要是合理估计即可；这些是 CORALL 文库的推荐起始值。

#read in variables
#读取公共变量
source common_variables.sh

#Run RSEM to quantify gene and isoform level expression
#运行 RSEM 以定量基因和转录本表达。
for filename in $Totals_filenames
do
rsem-calculate-expression --strandedness forward --fragment-length-mean 300 --fragment-length-sd 100 --alignments $BAM_dir/${filename}_pc_deduplicated.bam $rsem_index $rsem_dir/${filename} &
done
wait
