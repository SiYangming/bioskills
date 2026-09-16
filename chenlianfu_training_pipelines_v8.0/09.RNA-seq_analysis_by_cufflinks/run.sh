# 1. 使用cufflinks进行有参考基因组的基因表达量分析
mkdir -p /home/train/09.RNA-seq_analysis_by_cufflinks
cd /home/train/09.RNA-seq_analysis_by_cufflinks

# 1.1 准备参考基因组数据和HISAT2比对结果文件
# 参考基因组数据必须包含基因组序列和编码蛋白结果注释文件。
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gtf > genome.gtf
# 为了有利于差异表达基因分析，推荐去除比对到多个位点且具有相同最佳比对得分的reads。
for i in `ls ~/06.reads_aligment/hisat2/*.sam`
do
    x=${i/.sam/}
    x=${x/*\//}
    echo "perl -e 'while (<>) { unless (/^\@/) { @_ = split /\t/; next if \$_[4] < 10; } next if (/NH:i:(\d+)/ && \$1 > 1); print; }' $i > $x.sam; samtools sort -o $x.bam -O BAM $x.sam"
done > command.extract_unique.list
ParaFly -c command.extract_unique.list -CPU 2


# 1.2 使用cuffquant进行表达量计算，给出二进制结果文件
cd /home/train/09.RNA-seq_analysis_by_cufflinks
for i in `ls *.bam`
do
    i=${i/.bam/}
    echo "cuffquant --no-update-check -o cuffquant/$i -p 8 -b genome.fasta -u genome.gtf $i.bam"
done > command.cuffquant.list
sh command.cuffquant.list
# real	4m23.970s
# user	20m27.926s
# sys	0m3.277s


# 1.3 使用cuffnorm进行表达量计算，给出文本结果文件
# 单独对每个样品进行raw count表达量分析，raw count数据可以后续用于其它软件（例如，DESeq2和edgeR）进行差异分析。
cd /home/train/09.RNA-seq_analysis_by_cufflinks
for i in `ls *.bam`
do
    i=${i/.bam/}
    echo "cuffnorm --no-update-check -o cuffnorm/$i -p 8 -L ${i},${i} --library-norm-method classic-fpkm genome.gtf cuffquant/$i/abundances.cxb cuffquant/$i/abundances.cxb"
done > command.cuffnorm.list
sh command.cuffnorm.list
# real	0m12.749s
# user	0m13.514s
# sys	0m4.693s

# 合并所有样品的raw count数据，得到raw count表达量矩阵文件
cd /home/train/09.RNA-seq_analysis_by_cufflinks/cuffnorm
matrix_constructed_from_cuffnorm.pl ?/genes.count_table > genes.count_table.matrix
# 将raw counts标准化，转换为TPM数据
perl -p -i -e 's/tracking_id//;' genes.count_table.matrix
get_gene_max_cDNA_length_from_gtf.pl ../genome.gtf > gene_max_cDNA_length.txt
filter_raw_count_matrix.pl genes.count_table.matrix gene_max_cDNA_length.txt 10 3 > genes.count_table.filtered.matrix 2> genes.count_table.filtered.stats
rawCounts2TPM.pl genes.count_table.filtered.matrix ../genome.gtf > genes.TPM_notCross.matrix
/opt/biosoft/Trinity-v2.11.0/util/support_scripts/run_TMM_scale_matrix.pl --matrix genes.TPM_notCross.matrix > genes.TPM_Cross.matrix
# 计算样品间的相关系数
matrix_correlation_cal.pl genes.TPM_Cross.matrix

# cufflinks也可以一次性对所有样品的表达量进行标准化，但是无法得到raw count数据
cd /home/train/09.RNA-seq_analysis_by_cufflinks
cuffnorm --no-update-check --no-update-check -o cuffnorm/cuffnorm_geometric -p 8 -L A,B,C,D,E,F,G genome.gtf cuffquant/A/abundances.cxb cuffquant/B/abundances.cxb cuffquant/C/abundances.cxb cuffquant/D/abundances.cxb cuffquant/E/abundances.cxb cuffquant/F/abundances.cxb cuffquant/G/abundances.cxb
# real	0m5.503s
# user	0m6.707s
# sys	0m2.183s


# 2.1 使用cuffdiff进行差异表达分析
cd /home/train/09.RNA-seq_analysis_by_cufflinks/
cuffdiff --no-update-check -o cuffdiff -p 8 -L S4,S2 -b genome.fasta -u genome.gtf cuffquant/A/abundances.cxb,cuffquant/B/abundances.cxb,cuffquant/C/abundances.cxb cuffquant/D/abundances.cxb,cuffquant/E/abundances.cxb,cuffquant/F/abundances.cxb,cuffquant/G/abundances.cxb
# real	2m40.145s
# user	4m39.031s
# sys	0m0.844s

parsing_cuffdiff_out.pl cuffdiff/gene_exp.diff cuffdiff/DEG
cd cuffdiff/DEG
perl -e 'open IN, "DEG.matrix"; <IN>; while (<IN>) { m/^(\S+)/; $hash{$1} = 1; } close IN; open IN, "../../cuffnorm/genes.TPM_Cross.matrix"; $_ = <IN>; print; while (<IN>) { if (m/^(\S+)/ && exists $hash{$1}) { print } }' > 11; mv 11 DEG.matrix
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/PtR --matrix DEG.matrix --heatmap --heatmap_scale_limits "-3,3" --log2 --center_rows --heatmap_colorscheme 'green,black,red'


# 2.2 (推荐) 制作raw counts表达量矩阵和TPM表达量矩阵，使用edegeR和DEseq2进行差异分析，并取两者交集结果进行聚类分析
cd /home/train/09.RNA-seq_analysis_by_cufflinks/cuffnorm
ln -s genes.count_table.filtered.matrix gene.rawCount.matrix
ln -s genes.TPM_Cross.matrix gene.TPM.TMM.matrix
echo -e "S4\tA
S4\tB
S4\tC
S2\tD
S2\tE
S2\tF
S2\tG" > samples.txt

/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/run_DE_analysis.pl --matrix gene.rawCount.matrix --method edgeR --samples samples.txt --output edgeR_out
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/run_DE_analysis.pl --matrix gene.rawCount.matrix --method DESeq2 --samples samples.txt --output DESeq2_out
combine_multi_DEG_results.pl --out_dir edgeR_DESeq2 --matrix gene.TPM.TMM.matrix --sample_file samples.txt edgeR_out/ DESeq2_out/ 
#combine_multi_DEG_results.pl --fold_change 1 --FDR 0.01 --out_dir edgeR_DESeq2_logFC1_PDR0.01 --matrix gene.TPM.TMM.matrix --sample_file samples.txt edgeR_out/ DESeq2_out/
cd edgeR_DESeq2/
cat *.subset | cut -f 1 | sort | uniq | perl -e '<>; while (<>) { print }' > all_DEG.list
perl -e 'open IN, "all_DEG.list"; while (<IN>) { chomp; $gene{$_} = 1; } $_ = <>; print; while (<>) { print if (m/^(\S+)/ && exists $gene{$1}) }' ../gene.TPM.TMM.matrix > DEG.TPM.TMM.matrix
/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/PtR --matrix DEG.TPM.TMM.matrix --samples ../samples.txt --heatmap --heatmap_scale_limits "-3,3" --heatmap_colorscheme 'green,black,red' --log2 --center_rows --save

# R
# > load("DEG.TPM.TMM.matrix.RData")
# > source("/opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/R/manually_define_clusters.R")
# > manually_define_clusters(hc_genes, data)
# cd manually_defined_clusters_3
# /opt/biosoft/Trinity-v2.11.0/Analysis/DifferentialExpression/plot_expression_patterns.pl cluster_*


# 3. 使用StringTie进行有参考基因组的基因表达量分析
# 3.1 使用StringTie进行转录组组装
cd /home/train/09.RNA-seq_analysis_by_cufflinks/
for i in `ls *.bam`
do
    i=${i/.bam/}
    echo "stringtie $i.bam -l $i -o $i.gtf -p 8"
done > command.stringtie01.list
sh command.stringtie01.list
# real	0m28.971s
# user	0m33.877s
# sys	0m1.505s

# 将多个gtf文件整合成一个gtf
stringtie --merge -o merged.gtf ?.gtf

# 3.2 使用StringTie进行基因表达量分析
cd /home/train/09.RNA-seq_analysis_by_cufflinks/
for i in `ls *.bam`
do
    i=${i/.bam/}
    echo "stringtie $i.bam -G genome.gtf -e -p 8 -b $i -o $i.gtf"
done > command.stringtie02.list
sh command.stringtie02.list
# real	0m19.424s
# user	0m25.082s
# sys	0m1.131s

# 3.3 得到表达量counts矩阵文件，可以用于DESeq2和edgeR等差异分析软件。
echo -e "A\tA.gtf
B\tB.gtf
C\tC.gtf
D\tD.gtf
E\tE.gtf
F\tF.gtf
G\tG.gtf" > gtf.list
prepDE.py -i gtf.list -l 200
perl -p -e 's/,/\t/g; s/^.*\|//' gene_count_matrix.csv | sort > gene_count_matrix.tab


# 4. 使用HTSeq进行表达量计算
mkdir -p /home/train/09.RNA-seq_analysis_by_cufflinks/HTSeq
cd /home/train/09.RNA-seq_analysis_by_cufflinks/HTSeq
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gtf > genome.gtf

for i in `ls ~/06.reads_aligment/hisat2/*.sam`
do
    i=${i/.sam/}
    i=${i/*\//}
    echo "htseq-count -f sam -r name -s no -a 10 -t exon -i gene_id ~/06.reads_aligment/hisat2/$i.sam genome.gtf > $i.rawCounts.txt"
done > command.htseq-count.list
ParaFly -c command.htseq-count.list -CPU 7
# real	1m30.180s
# user	9m29.508s
# sys	0m3.596s

htseq_outs2matrix.pl A,B,C,D,E,F,G *.txt > raw_counts.matrix
rawCounts2TPM.pl raw_counts.matrix genome.gtf > TPM_notCross.matrix
/opt/biosoft/Trinity-v2.11.0/util/support_scripts/run_TMM_scale_matrix.pl --matrix TPM_notCross.matrix > TPM_Cross.matrix
