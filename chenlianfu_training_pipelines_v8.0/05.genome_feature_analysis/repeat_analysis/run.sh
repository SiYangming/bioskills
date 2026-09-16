#!/bin/bash

# 使用 RepeatMasker 进行基因组重复序列分析
mkdir -p /home/train/05.genome_feature_analysis/repeat_analysis
cd /home/train/05.genome_feature_analysis/repeat_analysis

fasta_no_blank.pl ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta > genome.fasta

mkdir repeatMasker
/opt/biosoft/RepeatMasker/util/queryRepeatDatabase.pl -tree > species.txt
/opt/biosoft/RepeatMasker/RepeatMasker -pa 4 -e ncbi -species fungi -dir repeatMasker/ -gff genome.fasta
# real	1m36.154s
# user	7m17.298s
# sys	1m7.740s

# 使用 repeatModeler 寻找本物种重复序列
mkdir repeatModeler
cd repeatModeler
/opt/biosoft/RepeatModeler-2.0.1/BuildDatabase -name species -engine ncbi ../genome.fasta
/opt/biosoft/RepeatModeler-2.0.1/RepeatModeler -engine ncbi -pa 4 -database species
# real 33min
/opt/biosoft/RepeatMasker/RepeatMasker -pa 4 -e ncbi -lib ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/RepeatModeler_database.consensi.fa -dir ./ -gff ../genome.fasta 
cd ..

# 将 repeatMasker 和 repeatModeler 的统计结果合并
merge_repeatMasker_out.pl repeatMasker/genome.fasta.out repeatModeler/genome.fasta.out > genome.repeat.stats
# 根据合并后的结果，来得到 masked genome
maskedByGff.pl genome.repeat.gff3 genome.fasta --mask_type softmask > genome.softmask.fasta
maskedByGff.pl genome.repeat.gff3 genome.fasta --mask_type hardmaskX > genome.hardmaskX.fasta
maskedByGff.pl genome.repeat.gff3 genome.fasta --mask_type hardmaskN > genome.hardmaskN.fasta
