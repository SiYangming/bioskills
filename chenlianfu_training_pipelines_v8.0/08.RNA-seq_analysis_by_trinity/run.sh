mkdir -p /home/train/08.RNA-seq_analysis_by_trinity
cd /home/train/08.RNA-seq_analysis_by_trinity


# 对PacBio转录组测序数据进行全长转录本序列分析
# https://github.com/PacificBiosciences/IsoSeq3/blob/master/README_v3.1.md
mkdir -p /home/train/08.RNA-seq_analysis_by_trinity/IsoSeq
cd /home/train/08.RNA-seq_analysis_by_trinity/IsoSeq

# 将subreads转换成ccs数据
export PATH=/home/train/smrtlink/smrtcmds/bin/:$PATH
samtools view -h ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/m54086_170204_081430.subreads.bam | head -n 10000 | samtools view -b > m54086_170204_081430.subreads.bam
pbindex m54086_170204_081430.subreads.bam
ccs --noPolish --minLength=300 --minPasses=1 --minZScore=-999 --maxDropFraction=0.8 --minPredictedAccuracy=0.8 --minSnr=4 m54086_170204_081430.subreads.bam m54086_170204_081430.ccs.bam

# 去除引物和barcode碱基信息。
echo '>NEB_5p
GCAATGAAGTCGCAGGGTTGGG
>Clontech_5p
AAGCAGTGGTATCAACGCAGAGTACATGGGG
>NEB_Clontech_3p
GTACTCTGCGTTGATACCACTGCTT' > barcoded_primers.fasta
lima m54086_170204_081430.ccs.bam barcoded_primers.fasta m54086_170204_081430.lima.bam --isoseq --no-pbi --peek-guess

# 去除PolyA和合体序列，得到FLNC序列
isoseq3 refine m54086_170204_081430*lima*.bam barcoded_primers.fasta m54086_170204_081430.flnc.bam --require-polya

# 对FLNC reads进行聚类，得到全长转录本序列信息
isoseq3 cluster m54086_170204_081430.flnc.bam unpolished.bam --verbose

# 对转录本序列进行修正
isoseq3 polish unpolished.bam m54086_170204_081430.subreads.bam polished.bam


# 使用Trinity软件对Illumina数据进行无参考基因组的转录组分析
cd /home/train/08.RNA-seq_analysis_by_trinity
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/?.?.fastq .
# 若笔记本计算性能较差，推荐减少数据量再进行计算
#for i in `ls /home/train/03.sequencing_data_quality_control/Trimmomatic/?.?.fastq`
#do
#    x=${i/*\//}
#    head -n 1000000 $i > $x
#done

# Trinity软件推荐Paired-End Fastq数据的序列名以/1和/2结尾。
# perl -e 'while (<>) { s/^(\@[^\s\/]+).*/$1\/1/; print; $_ = <>; print;  $_ = <>; print; $_ = <>; print; }' read.1.fastq > read_formatted.1.fastq
# perl -e 'while (<>) { s/^(\@[^\s\/]+).*/$1\/2/; print; $_ = <>; print;  $_ = <>; print; $_ = <>; print; }' read.2.fastq > read_formatted.2.fastq

# 使用 Trinity 进行 De novo 组装
Trinity --seqType fq --max_memory 2G --left `ls *.1.fastq | perl -pe 's/\n/,/' | perl -pe 's/,$//'` --right `ls *.2.fastq | perl -pe 's/\n/,/' | perl -pe 's/,$//'` --CPU 8 --jaccard_clip --normalize_reads --output trinity_denovo --bflyCalculateCPU &> trinity_denovo.log
# real	54m34.332s
# user	312m57.809s
# sys	67m20.243s

# 统计Trinity组装结果
/opt/biosoft/Trinity-v2.11.0/util/TrinityStats.pl trinity_denovo/Trinity.fasta > trinity_denovo/Trinity.fasta.stats
# 提取最长的Unigene
extract_longest_isoforms_from_TrinityFasta.pl trinity_denovo/Trinity.fasta > trinity_denovo/unigene.longest.fasta

# 使用 Trinity 进行有参考基因组的组装
samtools merge -@ 8 merged.bam ~/06.reads_aligment/hisat2/*.sam
samtools sort -@ 8 -O BAM -o merged.sort.bam merged.bam
Trinity --max_memory 2G --CPU 8 --jaccard_clip --normalize_reads --genome_guided_bam merged.sort.bam --genome_guided_max_intron 4000 --output trinity_genomeGuided --bflyCalculateCPU &> trinity_genomeGuided.log
# real	300m38.653s
# user	676m36.462s
# sys	39m30.345s
/opt/biosoft/Trinity-v2.11.0/util/TrinityStats.pl trinity_genomeGuided/Trinity-GG.fasta > trinity_genomeGuided/Trinity-GG.fasta.stats
#cp ~/08.RNA-seq_analysis_by_trinity/trinity_genomeGuided/Trinity-GG.fasta ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/
rm merged.*


# 进行表达量计算
mkdir -p /home/train/08.RNA-seq_analysis_by_trinity/exp_cal
cd /home/train/08.RNA-seq_analysis_by_trinity/exp_cal
ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Trinity.fasta ./
/opt/biosoft/Trinity-v2.11.0/util/support_scripts/get_Trinity_gene_to_trans_map.pl Trinity.fasta > Trinity.fasta.gene_trans_map

# 准备转录组序列的索引文件
/opt/biosoft/Trinity-v2.11.0/util/align_and_estimate_abundance.pl --transcripts Trinity.fasta --est_method RSEM --output_dir . --aln_method bowtie --prep_reference --gene_trans_map Trinity.fasta.gene_trans_map
# real	0m58.207s
# user	0m57.761s
# sys	0m0.426s

# 进行表达量计算
for i in `ls ../*.1.fastq`
do
    i=${i/*\//}
    i=${i/.1.fastq/}
    echo "/opt/biosoft/Trinity-v2.11.0/util/align_and_estimate_abundance.pl --transcripts Trinity.fasta --seqType fq --left ../$i.1.fastq --right ../$i.2.fastq --SS_lib_type RF --est_method RSEM --aln_method bowtie --thread_count 8 --gene_trans_map Trinity.fasta.gene_trans_map --output_dir $i &> $i.log"
done > command.align_and_estimate_abundance.list
sh command.align_and_estimate_abundance.list
# real	32m0.057s
# user	114m33.540s
# sys	8m22.277s

for i in `ls */RSEM.isoforms.results`
do
    x=${i/\/RSEM/}
    cp $i $x
done
# cp ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/RSEM_out/* ./

# 由各个样品的表达量，得到总的表达量矩阵，同时根据表达量去除假阳性序列 
extract_trinity_unigene_by_isofroms_expression_and_ORF.pl Trinity.fasta *.isoforms.results


# 差异表达分析
mkdir -p /home/train/08.RNA-seq_analysis_by_trinity/diff_exp
cd /home/train/08.RNA-seq_analysis_by_trinity/diff_exp
ln -s ../exp_cal/out.gene_rawCounts.matrix gene.rawCount.matrix
ln -s ../exp_cal/out.gene_TPM.not_cross.matrix gene.TPM.not_cross.matrix
/opt/biosoft/Trinity-v2.11.0/util/support_scripts/run_TMM_scale_matrix.pl --matrix gene.TPM.not_cross.matrix > gene.TPM.TMM.matrix

echo -e "S4\tA
S4\tB
S4\tC
S2\tD
S2\tE
S2\tF
S2\tG" > samples.txt
# 对两两样本counts总和 >= 40 的基因进行差异表达分析
#/opt/biosoft/trinityrnaseq-Trinity-v2.1.1/Analysis/DifferentialExpression/run_DE_analysis.pl --matrix genes.counts.matrix --method edgeR --samples_file samples.txt --min_rowSum_counts 40 --output edgeR.genes.dir
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/run_DE_analysis.pl --matrix gene.rawCount.matrix --method edgeR --samples_file samples.txt --output edgeR.genes.dir

cd edgeR.genes.dir
# 提取差异表达基因进行聚类分析和热图制作
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/analyze_diff_expr.pl --matrix ../gene.TPM.TMM.matrix -P 0.001 -C 2 --samples ../samples.txt
#/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/analyze_diff_expr.pl --matrix ../gene.TPM.TMM.matrix -P 0.01 -C 1 --samples ../samples.txt --order_columns_by_samples_file

# 根据距离结果进行分类
# 自动分类
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/define_clusters_by_cutting_tree.pl --Ptree 50 -R diffExpr.P0.001_C2.matrix.RData
# 手动分类
# R
# > load("diffExpr.P0.001_C2.matrix.RData")
# > source("/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/R/manually_define_clusters.R")
# > manually_define_clusters(hc_genes, data)
# 然后左键点击选择子类，右键结束选择。
# 结果生成了文件夹 manually_defined_clusters_4 。其中 4 表示手动分成了 4 类。
# cd manually_defined_clusters_4
# 对每类结果进行趋势线的绘制
# /opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/plot_expression_patterns.pl cluster_*


# 使用 transdecoder 进行ORF预测
mkdir -p /home/train/08.RNA-seq_analysis_by_trinity/transdecoder
cd /home/train/08.RNA-seq_analysis_by_trinity/transdecoder
#ln -s ../exp_cal/out.unigene.fasta Unigene.fasta
perl -e 'while (<>) { $num ++ if m/^>/; last if $num > 200; print; }' ../exp_cal/out.unigene.fasta > Unigene.fasta

# 首先，根据6个读码框翻译得到蛋白序列
TransDecoder.LongOrfs -t Unigene.fasta -m 100
# real	0m11.108s
# user	0m11.068s
# sys	0m0.042s
perl -pe 's/^>(\S+).*/>$1/' Unigene.fasta.transdecoder_dir/longest_orfs.pep > longest_orfs.pep

# 然后，将ORF蛋白序列比对到公共数据库，能比对上的则表示存在对应转录本序列
# 比对到SwissProt数据库
#wget ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz -P ~/software/
gzip -dc ~/software/uniprot_sprot.fasta.gz > uniprot_sprot.fasta
diamond makedb --threads 8 --db uniprot_sprot --in uniprot_sprot.fasta
diamond blastp --db uniprot_sprot --query longest_orfs.pep --out blast.xml --outfmt 5 --sensitive --max-target-seqs 20 --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
# real	0m38.761s
# user	4m55.936s
# sys	0m1.187s
parsing_blast_result.pl --no-header --max-hit-num 20 --query-coverage 0.2 --subject-coverage 0.1 blast.xml > blastp.outfmt6

# 比对到PFAM数据库
para_hmmscan.pl --cpu 4 --out pfam --chunk 30 --hmmscan " --cpu 2 -E 1e-5 --domE 1e-5" longest_orfs.pep
# real	3m47.525s
# user	15m25.310s
# sys	8m19.827s

# 最后，去除假阳性ORF，保留正确的ORF
TransDecoder.Predict -t Unigene.fasta --retain_pfam_hits pfam.domtbl --retain_blastp_hits blastp.outfmt6
# real	0m51.079s
# user	0m50.418s
# sys	0m0.671s
cd ..
