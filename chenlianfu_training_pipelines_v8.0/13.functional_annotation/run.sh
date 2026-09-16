# 1. NR 注释

# 本地化基因组数据库构建和wwwblast搭建
mkdir /opt/biosoft/wwwblast/db/
cd /opt/biosoft/wwwblast/db/
# 构建核酸数据库
makeblastdb -in ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta -dbtype nucl -title Malassezia_sympodialis_V01.genome -parse_seqids -out Malassezia_sympodialis_V01.genome -logfile Malassezia_sympodialis_V01.genome.log
# 构建蛋白质数据库
makeblastdb -in ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.protein.fasta -dbtype prot -title Malassezia_sympodialis_V01.protein -parse_seqids -out Malassezia_sympodialis_V01.protein -logfile protein.log
# 更新wwwblast数据库设置
update_wwwblast_config.pl
# wwwblast密码访问设置
echo 'AuthName     "Protected!"
Authtype     Basic
AuthUserFile /var/www/apache.passwd
require user train' > /opt/biosoft/wwwblast/.htaccess
sudo htpasswd -c -b /var/www/apache.passwd train 123456

# 本地化运行 blast 程序
mkdir -p ~/13.functional_annotation/nr/blast_to_genome
cd ~/13.functional_annotation/nr/blast_to_genome
# 在https://www.ncbi.nlm.nih.gov/gene/数据库搜索"3-phytase a"，点击Send to，选择File，在Format中选择UI List，下载文件保存为gi.ncbi_gene_phyA.list
cp ~/00.incipient_data/data_for_functional_annotation/gi.ncbi_gene_phyA.list ./
ncbi_acc_or_gi_to_fasta.pl gi.ncbi_gene_phyA.list 20 > phyA.nucl.fasta
perl -p -e 's/>(\S+).*/>$1/; s/\|/_/g' ~/00.incipient_data/data_for_functional_annotation/phyA.nucl.fasta > phyA.nucl.fasta
blastn -query phyA.nucl.fasta -db Malassezia_sympodialis_V01.genome -out blastn.out -evalue 1e-5 -outfmt 7 -num_threads 4

# 在https://www.uniprot.org/uniprot/搜索"3-phytase a" AND reviewed:yes，并下载数据
perl -p -e 's/>(\S+).*/>$1/; s/\|/_/g' ~/00.incipient_data/data_for_functional_annotation/uniprot-_3-phytase+a_-filtered-reviewed_yes.fasta > phyA.pep.fasta
blastp -query phyA.pep.fasta -db Malassezia_sympodialis_V01.protein -out blastp.out -evalue 1e-5 -outfmt 7 -num_threads 4


# 准备基因组蛋白质序列文件
mkdir -p ~/13.functional_annotation
cd ~/13.functional_annotation
perl -p -e 's/\*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.protein.fasta > proteins.fasta

# 对基因组蛋白质序列进行Nr注释
mkdir -p /home/train/13.functional_annotation/nr
cd /home/train/13.functional_annotation/nr
diamond blastp --db /opt/biosoft/wwwblast/db/nr_fungi --query ../proteins.fasta --out nr.xml --outfmt 5 --sensitive --max-target-seqs 20 --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
# 160线程2.4G Hz CPU下计算
# real	12m57.783s
# user	713m2.268s
# sys	244m35.499s

gzip -dc ~/00.incipient_data/data_for_functional_annotation/nr.xml.gz > nr.xml
parsing_blast_result.pl --evalue 1e-5 --HSP-num 1 --out-hit-confidence --suject-annotation nr.xml > nr.tab
nr_species_distribution.pl nr.tab > species_distribution.txt
gene_annotation_from_Nr.pl nr.tab > Nr.txt
cd ..


# 2. 进行 Swiss-Prot 注释
mkdir -p /home/train/13.functional_annotation/swiss-prot
cd /home/train/13.functional_annotation/swiss-prot
# 构建 Swiss-Prot 数据库
gzip -dc ~/software/uniprot_sprot.fasta.gz > /opt/biosoft/wwwblast/db/uniprot_sprot.fasta
makeblastdb -in /opt/biosoft/wwwblast/db/uniprot_sprot.fasta -dbtype prot -title uniprot_sprot -parse_seqids -out /opt/biosoft/wwwblast/db/uniprot_sprot -logfile /opt/biosoft/wwwblast/db/uniprot_sprot.log
cat /opt/biosoft/ncbi-blast+/db/uniprot_sprot.log
# 使用 ncbi-blast+ 进行 Swiss-Prot 注释
head -n 200 ../proteins.fasta > test.fasta
~/bin/blast.pl --CPU 8 --outfmt 5 -clean uniprot_sprot test.fasta > blast.xml
# real	0m47.846s
# user	4m53.512s
# sys	0m0.752s

# 使用diamond进行分析
diamond makedb --db /opt/biosoft/wwwblast/db/uniprot_sprot --in /opt/biosoft/wwwblast/db/uniprot_sprot.fasta
diamond blastp --db /opt/biosoft/wwwblast/db/uniprot_sprot --query ../proteins.fasta --out uniprot_sprot.xml --outfmt 5 --sensitive --max-target-seqs 20 --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
# real	0m50.636s
# user	6m29.161s
# sys	0m1.372s
parsing_blast_result.pl --evalue 1e-5 --HSP-num 1 --out-hit-confidence --suject-annotation uniprot_sprot.xml > uniprot_sprot.tab
gene_annotation_from_SwissProt.pl uniprot_sprot.tab > SwissProt.txt


# 3. 进行 COG / KOG 注释
# 构建 COG / KOG 数据库
makeblastdb -in /home/train/00.incipient_data/data_for_functional_annotation/myva -dbtype prot -title cog -parse_seqids -out /opt/biosoft/wwwblast/db/cog -logfile /opt/biosoft/wwwblast/db/cog.log
makeblastdb -in /home/train/00.incipient_data/data_for_functional_annotation/kyva -dbtype prot -title kog -parse_seqids -out /opt/biosoft/wwwblast/db/kog -logfile /opt/biosoft/wwwblast/db/kog.log
diamond makedb --db /opt/biosoft/wwwblast/db/cog --in /home/train/00.incipient_data/data_for_functional_annotation/myva
diamond makedb --db /opt/biosoft/wwwblast/db/kog --in /home/train/00.incipient_data/data_for_functional_annotation/kyva

mkdir -p /home/train/13.functional_annotation/cog
cd /home/train/13.functional_annotation/cog
diamond blastp --db /opt/biosoft/wwwblast/db/kog --query ../proteins.fasta --out kog.xml --outfmt 5 --sensitive --max-target-seqs 200 --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
# real	0m14.567s
# user	1m52.251s
# sys	0m0.483s
cog_from_xml.pl --coverage 0.2 --evalue 1e-5  --db-fasta /opt/biosoft/wwwblast/db/kog.fasta --db-class ~/bin/cog/kog --fun-txt ~/bin/cog/fun.kog.txt kog.xml
cut -f 1,3,4 out.annot | gene_annotation_from_table.pl - > KOG.txt
cog_R.pl --title "KOG Function Classification of Whole Genome Genes of Malassezia sympodialis" --y-name "Number of Genes" out.class


# 4. eggNOG 注释
mkdir -p /home/train/13.functional_annotation/eggNOG
cd /home/train/13.functional_annotation/eggNOG
# http://eggnog-mapper.embl.de/提交蛋白序列
# one-to-one orthology only; evalue: 0.001; score 60; query coverage: 20%; subject coverage: 20%
# http://eggnog-mapper.embl.de/job_status?jobname=MM_1revx_hu
# 耗时2h19min
# wget http://eggnog-mapper.embl.de/MM_1revx_hu/query_seqs.fa.emapper.annotations
# wget http://eggnog-mapper.embl.de/MM_1revx_hu/query_seqs.fa.emapper.seed_orthologs
cp ~/00.incipient_data/data_for_functional_annotation/query_seqs.fa.emapper.* ./
ln -s query_seqs.fa.emapper.annotations eggNOG.annot
cd ..


# 5. CDD 注释
mkdir -p /home/train/13.functional_annotation/cdd
cd /home/train/13.functional_annotation/cdd
#将序列分割并分别提交到https://www.ncbi.nlm.nih.gov/Structure/bwrpsb/bwrpsb.cgi
split_fasta_file_averagely.pl ../proteins.fasta 2
#QM3-qcdsearch-44A314E4A2BF766
#QM3-qcdsearch-F191E3C68C750E2
#Data mode选择Concise，会去除调non-specific的结果，保留更可信的结果；勾选Include domain defline，然后下载结果数据
cp ~/00.incipient_data/data_for_functional_annotation/?_hitdata.txt ./
grep -P "^#" -v 1_hitdata.txt | perl -pe 's/^\s*$//' | head -n 1 > cdd.tab
grep -P "^#" -v 1_hitdata.txt | perl -pe 's/^\s*$//' | perl -e '<>; print <>' | perl -pe 's/.*?\>//' > aa
grep -P "^#" -v 2_hitdata.txt | perl -pe 's/^\s*$//' | perl -e '<>; print <>' | perl -pe 's/.*?\>//' >> aa
sort aa >> cdd.tab
rm aa
#fasta2cddAnotation.pl ../proteins.fasta 20


# 6. Interpro 注释
mkdir -p /home/train/13.functional_annotation/interpro
cd /home/train/13.functional_annotation/interpro
#interProScan5.pl ../proteins.fasta chenllianfu@gmail.com interpro5 30
tar zxf ~/00.incipient_data/data_for_functional_annotation/interpro5.tar.gz
cat interpro5/*gff* > interpro.gff
cat interpro5/*tsv* > interpro.tsv
grep IPR interpro.tsv | cut -f 1,12,13 | gene_annotation_from_table.pl - > Interpro.txt
cd ..


# 7. GO 注释
mkdir -p /home/train/13.functional_annotation/go
cd /home/train/13.functional_annotation/go

# 整合eggNOG和InterPro中的GO注释结果
go_from_eggNOG_and_interpro.pl ../eggNOG/eggNOG.annot ../interpro/interpro.tsv > go.annot
go_reducing_go_number_para.pl /opt/biosoft/go_class/bin/go.obo go.annot 8 > go_reduced.annot
sort go_reduced.annot > go.annot; rm go_reduced.annot
#cp ~/00.incipient_data/data_for_functional_annotation/go.annot ./
annot2gaf.pl /opt/biosoft/go_class/bin/go.obo go.annot > gene_association.gaf2
cut -f 2,5,9 gene_association.gaf2 | gene_annotation_from_table.pl - > GO.txt

# GO功能注释分类
mkdir -p /home/train/13.functional_annotation/go/go_class
cd /home/train/13.functional_annotation/go/go_class
annot2wego.pl ../go.annot > go.wego
get_Genes_From_GO.pl /opt/biosoft/go_class/bin/go.obo go.wego > go_class.tab
go_svg.pl --outdir ./ --name out --color "green" --mark "Whole Genome Genes" --note "GO Class of whole genome genes of Malassezia sympodialis" go.wego
perl -p -i -e 's/MovePer:0.125/MovePer:0.5/' out.lst
/opt/biosoft/go_class/svg/distributing_svg.pl out.lst out.svg
changsvgsize.pl out.svg 150 -100
convert out.svg out.png

# go enrichment
mkdir -p /home/train/13.functional_annotation/go/enrichment
cd /home/train/13.functional_annotation/go/enrichment
cp /opt/biosoft/go_class/bin/go.obo ./
cp ~/00.incipient_data/data_for_functional_annotation/enrichment_example/gene_association.gaf2 ./
cp ~/00.incipient_data/data_for_functional_annotation/enrichment_example/*.list ./

# 使用 Ontologizer 进行富集分析
/opt/sysoft/jre1.7.0_05/bin/javaws http://compbio.charite.de/tl_files/ontologizer/webstart/ontologizer.jnlp
# 点击 New Project, 随便输入一个名称，例如：MS，点击下一步。
# 在 Ontology 栏中 browse，寻找并选择 go.obo 文件。
# 在 Annotations 栏中 browse，寻找并选择 gene_association.gaf2 文件。
# 点击下一步，选择 population 文件。一般以全基因组作为背景，此处点击 Take them all。点击 Finish 。
# 回到 Ontology 主界面，选中 Study 1, 点击 Append Set, 寻找并选择S1_vs_S3_S1_UP.list文件。
# 在右上角两个复选框选择 Parent-Child_Union 和 Bonferroni 。
# 点击 Ontologize，进行富集分析。

ontologizer2enriched_GOs_and_GeneID.pl go.obo gene_association.gaf2 S1_vs_S3_S1_UP.GoEnrichment.txt S1_vs_S3_S1_UP.list > S1_vs_S3_S1_UP.GoEnrichment.tab
ontologizer2enriched_GOs_and_GeneID.pl go.obo gene_association.gaf2 S1_vs_S3_S3_UP.GoEnrichment.txt S1_vs_S3_S3_UP.list > S1_vs_S3_S3_UP.GoEnrichment.tab
cd ..


# 8. KAAS 注释
mkdir -p /home/train/13.functional_annotation/kaas
cd /home/train/13.functional_annotation/kaas
# 在 http://www.genome.jp/kaas-bin/kaas_main 网页工具中提交序列进行注释。需要填写邮箱信息，在网页中提交后需要再进入邮箱，点击邮件中的提交链接，才能开始计算。
# Selected organisms: hsa, mmu, rno, dre, dme, cel, ath, sce, cal, spo, ecu, pfa, cho, ehi, eco, nme, hpy, bsu, lla, mge, mtu, syn, aae, mja, ape, sce, dha, ncr, fox, ssl, afm, cpw, bze, tml, uma, mrt, cgi, hir
# 注释完毕后，从填写的邮箱中进入注释完毕后的网页，下载注释结果 query.ko 文件。
#wget https://www.genome.jp/tools/kaas/files/dl/1597321919/query.ko

cp ~/00.incipient_data/data_for_functional_annotation/query.ko ./
cp ~/00.incipient_data/data_for_functional_annotation/ko00001.keg ./
gene_annotation_from_kaas.pl query.ko > KEGG.txt

#kaas2pathwayEnrichmentAnalysis.pl query.ko ~/00.incipient_data/data_for_functional_annotation/study.1.txt

#perl -e '<>; while (<>) {@_ = split /\t/; print "$_[0]\t$_[5]\n";}' ~/09.RNA-seq_analysis_by_cufflinks/cuffnorm/edgeR_DESeq2/rawCount.matrix.S2_vs_S4.P0.001.C2.S2-UP.subset > study.1.txt
#perl -e '<>; while (<>) {@_ = split /\t/; print "$_[0]\t$_[5]\n";}' ~/09.RNA-seq_analysis_by_cufflinks/cuffnorm/edgeR_DESeq2/rawCount.matrix.S2_vs_S4.P0.001.C2.S4-UP.subset > study.2.txt
cp ~/00.incipient_data/data_for_functional_annotation/study.?.txt ./
pathview.pl query.ko study.1.txt study.2.txt 8

# 由于没有结果为空，选取了一个正常的示例
# rm down_regulated_genes_enrichment pathview up_regulated_genes_enrichment -rf
# tar zxf ~/00.incipient_data/data_for_functional_annotation/KEGG_Pathway_Enrichment.S1_vs_S3.tar.gz 
cd ..


# 9. Transcription Fatcor 注释
mkdir -p /home/train/13.functional_annotation/TF
cd /home/train/13.functional_annotation/TF
interpro2tf_for_Fungi.pl ../interpro/interpro.tsv --out_prefix TF
cd ..


# 10. 整合各种注释结果到一个表格中
cd /home/train/13.functional_annotation/
gene_annotation_from_all.pl --html nr/Nr.txt swiss-prot/SwissProt.txt cog/KOG.txt go/GO.txt interpro/Interpro.txt kaas/KEGG.txt > annot.html 2> annot.stats
gene_annotation_from_all.pl nr/Nr.txt swiss-prot/SwissProt.txt cog/KOG.txt go/GO.txt interpro/Interpro.txt kaas/KEGG.txt > annot.txt 2> annot.stats


# 11. CAZY annotation
mkdir -p /home/train/13.functional_annotation/cazyme
cd /home/train/13.functional_annotation/cazyme
# 使用 HMM 方法进行注释
para_hmmscan.pl --out hmmscan --cpu 8 --hmmscan " --cpu 1 -E 1e-3 --domE 1e-3" --hmm_db /opt/biosoft/dbCAN_v9.0/dbCAN-fam-HMMs.txt ../proteins.fasta
# real	0m24.270s
# user	1m10.534s
# sys	1m40.529s

# 使用 Blastp 方法进行注释
diamond blastp --db /opt/biosoft/dbCAN_v9.0/CAZyDB.07312020 --query ../proteins.fasta --out diamond.xml --outfmt 5 --sensitive --max-target-seqs 500 --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
# real	1m48.956s
# user	13m57.829s
# sys	0m2.708s
parsing_blast_result.pl --no-header --evalue 1e-5 --HSP-num 1 diamond.xml > blastp.outfmt6

# 合并两者结果
dbcan_combine.pl --query ../proteins.fasta --CAZy_blastDB /opt/biosoft/dbCAN_v9.0/CAZyDB.07312020.fa --threshold_file_in /opt/biosoft/dbCAN_v9.0/out90.threshold.tab hmmscan.domtbl blastp.outfmt6


# 12. secreted protein annotation
mkdir -p /home/train/13.functional_annotation/secreted_protein
cd /home/train/13.functional_annotation/secreted_protein

# 首先，进行信号肽分析。分泌蛋白都具有信号肽。
mkdir singalp
cd singalp
/opt/biosoft/signalp-5.0/bin/signalp -batch 30000 -org euk -fasta ../../proteins.fasta -gff3 -mature 
cd ..

# 再进行跨膜区分析。若具有跨膜区，则蛋白会和膜进行结合，从而固定到膜上，不会成为分泌蛋白。
mkdir TMHMM
cd TMHMM
/opt/biosoft/tmhmm-2.0c/bin/tmhmm ../singalp/proteins_mature.fasta > tmhmm.out
grep "Number of predicted TMHs:  0" tmhmm.out | perl -p -e 's/#\s+(\S+).*/$1/' > genes_without_TMHs.list
fasta_extract_subseqs_from_list.pl ../../proteins.fasta genes_without_TMHs.list > ../candidate_secreted_proteins.fasta
cd ..

# 再分析GPI锚定位点。GPI锚定蛋白和膜结合，从而固定到膜上，不会成为分泌蛋白。
mkdir PredGPI
cd PredGPI
# http://gpcr.biocomp.unibo.it/predgpi/pred.htm
# 一次最多允许提交500条序列。提交后点击download。
# 结果文件是fasta格式文件，其头部包含结果信息。
# PredGPI.fasta
# 取阈值FDR 0.5%。
# FDR <= 0.1%    GPI-anchored: highly probable
# FDR <= 0.5%    GPI-anchored: probable
# FDR <= 1.0%    GPI-anchored: lowly probable
cp ~/00.incipient_data/data_for_functional_annotation/GPIPE_query_results__tmp_tmpK2S4a2.txt PredGPI.fasta
perl -e 'while (<>) { if (m/^>(\S+).*FPrate:(\S+)/ && $2 <= 0.01) { print "$1\n"; } }' PredGPI.fasta > GPI_gene.list
# 31个基因有GPI锚定位点
fasta_extract_subseqs_from_list.pl --reverse ../candidate_secreted_proteins.fasta GPI_gene.list > ../candidate_secreted_proteins.NO_GPI.fasta
cd ..

# 最后，进行亚细胞定位，选取定位到胞外的蛋白作为分泌蛋白基因
mkdir BUSCA
cd BUSCA
# http://busca.biocomp.unibo.it/
# 一次最多允许提交500条序列。选择Fungi类型，点击Start prediction。
# http://busca.biocomp.unibo.it/edd1b732-e20b-49a5-aae4-441656912fc0/showresult/
# 下载表格格式结果：BUSCA_JOB_edd1b732-e20b-49a5-aae4-441656912fc0.csv
cp ~/00.incipient_data/data_for_functional_annotation/BUSCA_JOB_edd1b732-e20b-49a5-aae4-441656912fc0.csv BUSCA.out.csv
perl -e '<>; while (<>) { @_ = split /,/; $stats{$_[2]}{$_[0]} = 1; } foreach (sort keys %stats) { @gene = sort keys %{$stats{$_}}; my $gene_number = 0; $gene_number = @gene; print STDERR "$_\t$gene_number\n"; if ($_ eq "C:extracellular space") { foreach (@gene) { print "$_\n"; } } }' BUSCA.out.csv > extracellular_gene.list 2> BUSCA.out.csv.stats
# 117个蛋白定位于胞外

fasta_extract_subseqs_from_list.pl ../candidate_secreted_proteins.NO_GPI.fasta extracellular_gene.list > ../candidate_secreted_proteins.NO_GPI.extracellular.fasta
cd ..
ln -s candidate_secreted_proteins.NO_GPI.extracellular.fasta secreted_proteins.fasta
# 分泌蛋白最终结果是 secreted_proteins.fasta
cd ..
