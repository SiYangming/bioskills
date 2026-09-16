# Circos 画图
mkdir -p /home/train/12.genome_visualization/circos
cd /home/train/12.genome_visualization/circos
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gff3 genome.gff3

# 准备用于circos画图的数据文件
# 通过基因组序列，生成染色体组型文件
circos_create_karyotype_by_genome.pl genome.fasta > karyotype.txt
# band 信息使用MCScanX的共线性区块信息
# circos_create_karyotype_band_by_MCScanX.pl data/nc_cp.gff data/nc_cp.collinearity_interspecific 15 1 > karyotype.band_for_circos.txt
cat ~/00.incipient_data/data_for_circos/karyotype.band_for_circos.txt >> karyotype.txt

# 通过基因组序列，生成GC含量结果文件，用于画直方图
circos_create_gc_histogram.pl genome.fasta 10000 > gc.histogram.txt

# 生成SNP密度结果文件，用于画直方图
VCF_get_variants_density_for_circos.pl ~/00.incipient_data/data_for_variants_calling/variants.vcf genome.fasta > variant_density.histogram_for_circos.txt

# 通过转录组数据，得到基因表达量的结果文件，用于画热图
cut -f 1,2,5 ~/09.RNA-seq_analysis_by_cufflinks/cuffnorm/gene.TPM.TMM.matrix > gene.TPM.TMM.matrix
circos_create_expression_heatmap.pl gene.TPM.TMM.matrix genome.gff3 > gene_expression.heatmap.txt

# 通过基因组自身比较，用于画links图
makeblastdb -in genome.fasta -dbtype nucl -title genome -parse_seqids -out genome 
blastn -query genome.fasta -db genome -out blast.out -evalue 1e-5 -outfmt 6 -num_threads 8
# 计算耗时~2min。
perl -e 'while (<>) { @_ = split /\t/; print if $_[6] ne $_[8] && $_[2] >= 90 && $_[3] >= 1000 }' blast.out | sort -k 1.13n -k 7n > similarity.txt
perl -e 'while (<>) { @_ = split /\t/; if ($_[3] >= 3000) { print } else { print STDERR } }' similarity.txt > similarity_3000.txt 2> similarity_1000.txt
perl -e 'while (<>) { @_ = split /\t/; print "$_[0]\t$_[6]\t$_[7]\t$_[1]\t$_[8]\t$_[9]\n"; }' similarity_1000.txt > similarity_1000.links.txt
perl -e 'while (<>) { @_ = split /\t/; print "$_[0]\t$_[6]\t$_[7]\t$_[1]\t$_[8]\t$_[9]\n"; }' similarity_3000.txt > similarity_3000.links.txt
rm genome* similarity_1000.txt similarity_3000.txt similarity.txt blast.out

# 准备circos配置文件
cp ~/00.incipient_data/data_for_circos/*.conf ./

# 运行circos程序画图
circos -noparanoid -conf circos.conf 
# real	0m17.757s
# user	0m17.693s
# sys	0m0.064s

gthumb circos.png


## GBrowse2
mkdir -p /home/train/12.genome_visualization/GBrowse2
cd /home/train/12.genome_visualization/GBrowse2

# 准备需要展示的基因组文件
#cd ~/00.incipient_data/data_for_gbrowse/
#cp ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
#cp ~/10.gene_prediction/augustus/augustus.gff3 ./
#perl -pe 's/\t\S+\t/\tgenemarkES\t/' ~/10.gene_prediction/genemark_es_et/genemarkES.gff3 > genemarkES.gff3
#perl -pe 's/\t\S+\t/\tgenemarkET\t/' ~/10.gene_prediction/genemark_es_et/genemarkET.gff3 > genemarkET.gff3
#perl -pe 's/\t\S+\t/\tSNAP\t/' ~/10.gene_prediction/snap/snap.gff3 > snap.gff3
#cp ~/10.gene_prediction/maker/maker.gff3 ./
#perl -pe 's/\t\S+\t/\tBRAKER\t/' ~/10.gene_prediction/braker/braker.gff3 > braker.gff3
#perl -pe 's/ID=([^;\s]+);/ID=$1;Name=$1;/ if (m/\tgene\t/ or m/\tmRNA\t/);' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gff3 > Malassezia_sympodialis_V01.GeneModels.gff3
#perl -pe 's/ID=([^;\s]+);/ID=$1;Name=$1;/ if (m/\tgene\t/ or m/\tmRNA\t/);' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gff3 > Malassezia_sympodialis_V01.BestGeneModels.gff3
#perl -pe 's/\t\S+\t/\tPASA\t/' ~/10.gene_prediction/pasa/pasa.gff3 > pasa.gff3 
#perl -pe 's/\t\S+\t/\tGeneWise\t/' ~/10.gene_prediction/homolog/genewise.gff3 > homolog.gff3
#cp ~/10.gene_prediction/evm/transcript_alignments.gff3 pasa_align.gff3
#cp ~/10.gene_prediction/evm/protein_alignments.gff3 homolog_align.gff3
#cp ~/05.genome_feature_analysis/Rfam/rRNA_out.gff3 rRNA.gff3
#cp ~/05.genome_feature_analysis/tRNAscan-SE/tRNA.gff3 ./
#cp ~/05.genome_feature_analysis/SSR_detecting_and_primer_design/misa_primer3.gff3 SSR.gff3
#cp ~/05.genome_feature_analysis/repeat_analysis/genome.repeat.gff3 ./
#gbrowse2_create_genome_scaffold_gff3.pl genome.fasta > genome.gff3
#cd /home/train/12.genome_visualization/GBrowse2

cp ~/00.incipient_data/data_for_gbrowse/* ./
gbrowse2_create_genome_scaffold_gff3.pl genome.fasta > genome.gff3

# 创建mysql数据库malassezia_sympodialis_gbrowse2
echo "CREATE DATABASE IF NOT EXISTS malassezia_sympodialis_gbrowse2" | mysql -utrain -p123456
# 或者，在mysql命令行界面输入
# mysql -utrain -p123456
# mysql> CREATE DATABASE malassezia_sympodialis_gbrowse2;
# 若 Mysql 数据库无 train 用户，则进行下面的命令：
# mysql -uroot -p
# mysql> GRANT ALL ON *.* TO ‘train’@’%’ IDENTIFIED BY ‘123456’;
# mysql> FLASH PRIVILEGES;
# mysql> CREATE DATABASE IF NOT EXISTS malassezia_sympodialis_gbrowse2;

# 导入数据，下面命令会先清空数据库，再导入数据
bp_seqfeature_load -c -a DBI::mysql -d malassezia_sympodialis_gbrowse2 -u train -p 123456 genome.fasta *.gff3
# real	18m10.981s
# user	5m28.514s
# sys	1m9.785s
# 若需要追加 GFF3 数据到已存在的 Mysql 数据库中，则不需要加 -c 参素
# bp_seqfeature_load.pl -a DBI::mysql -d Malassezia_sympodialis_gbrowse2 -u train -p 123456 file.gff3

# 展示bam文件
ln -s ~/09.RNA-seq_analysis_by_cufflinks/A.bam .
ln -s ~/09.RNA-seq_analysis_by_cufflinks/D.bam .
samtools index A.bam 
samtools index D.bam 

# GBrowse2 数据源配置文件
# 修改 /etc/gbrowse2/GBrowse.conf 文件
cat /etc/gbrowse2/GBrowse.conf > GBrowse.conf
echo "[MS]
description = Malassezia sympodialis
path        = malassezia_sympodialis.conf" >> GBrowse.conf
sudo mv GBrowse.conf /etc/gbrowse2/GBrowse.conf
# 本物种的配置文件
sudo cp ~/00.incipient_data/data_for_gbrowse/malassezia_sympodialis.conf /etc/gbrowse2/

# Browse 设置用户访问
gbrowse_create_account.pl train
sudo perl -p -i -e 's/^#restrict/restrict/' /etc/gbrowse2/malassezia_sympodialis.conf
# 现在查看 malassezia_sympodialis 的基因组浏览器则需要登录了。
# 修改还原
sudo perl -p -i -e 's/^restrict/#restrict/' /etc/gbrowse2/malassezia_sympodialis.conf


## WebApollo
mkdir -p /home/train/12.genome_visualization/WebApollo
cd /home/train/12.genome_visualization/WebApollo

# 准备数据文件
ln -s ../GBrowse2/genome.fasta ./
ln -s ../GBrowse2/*.gff3 ./
rm pasa_align.gff3 homolog_align.gff3
ln -s ../GBrowse2/*.bam* ./
bam2wig A.bam > A.wig
bam2wig D.bam > D.wig
cal_seq_length.pl genome.fasta > chrom.sizes
wigToBigWig.pl A.wig chrom.sizes A.bw
wigToBigWig.pl D.wig chrom.sizes D.bw

# 设置 PostGres 和 Web Apollo 的用户，数据库和权限
# 创建 posGresql 的用户 train, 密码为 123456
sudo su - postgres
createuser -h localhost -p 5432 -d -R -S train
# Enter password for new role：123456
# Enter it again: 123456
# 创建 PostGres 数据库
createdb -h localhost -p 5432 -U train apollo_malassezia_sympodialis
logout
# 建立数据库的表 (以下使用 train 用户执行)
psql -U train apollo_malassezia_sympodialis < /opt/biosoft/WebApollo-2014-04-03/tools/user/user_database_postgresql.sql
# 创建 Web Apollo 用户 apollo，密码 123456
/opt/biosoft/WebApollo-2014-04-03/tools/user/add_user.pl -D apollo_malassezia_sympodialis -U train -P 123456 -u apollo -p 123456
# 提取基因组序列名，将序列名导入到 postgres 数据库，并使 apollo 用户具有访问这些序列的权限
/opt/biosoft/WebApollo-2014-04-03/tools/user/extract_seqids_from_fasta.pl -p Annotations- -i genome.fasta -o seqids.txt
/opt/biosoft/WebApollo-2014-04-03/tools/user/add_tracks.pl -D apollo_malassezia_sympodialis -U train -P 123456 -t seqids.txt
/opt/biosoft/WebApollo-2014-04-03/tools/user/set_track_permissions.pl -D apollo_malassezia_sympodialis -U train -P 123456 -u apollo -t seqids.txt -a

# 部署 Web Apollo
mkdir annotations data temp
mkdir /opt/biosoft/WebApollo-2014-04-03/apache-tomcat-7.0.57/webapps/webApollo_Malassezia_sympodialis
cd /opt/biosoft/WebApollo-2014-04-03/apache-tomcat-7.0.57/webapps/webApollo_Malassezia_sympodialis
jar -xvf /opt/biosoft/WebApollo-2014-04-03/war/WebApollo.war 
cd jbrowse
chmod 777 bin/*
export PATH=/opt/biosoft/WebApollo-2014-04-03/apache-tomcat-7.0.57/webapps/webApollo_Malassezia_sympodialis/jbrowse/bin/:$PATH
ln -s /home/train/12.genome_visualization/WebApollo/data ./
cd ../config
# modify the files config.xml and blat_config.xml
cp ~/00.incipient_data/data_for_webApollo/config.xml ./

# 将需要展示的数据格式化，构建Track，放入 data 文件夹中
cd ~/12.genome_visualization/WebApollo/
prepare-refseqs.pl --fasta genome.fasta 
add-webapollo-plugin.pl -i data/trackList.json
for i in `ls *.gff3`
do
    x=${i/.gff3/}
    flatfile-to-json.pl -gff $i --arrowheadClass trellis-arrowhead --getSubfeatures --subfeatureClasses '{"wholeCDS": null, "CDS":"brightgreen-80pct", "UTR": "darkgreen-60pct", "exon":"container-100pct"}' --className container-16px --type mRNA --trackLabel $x
done

perl -ne 'if (/\tmult=(\d+)/ && $1 >= 3) {$mult=$1; s/(.*)\t.*/$1/; print "$1\tName=$mult;\n";}' ~/10.gene_prediction/augustus/making_hints/hints.gff > hints.intron.gff3
flatfile-to-json.pl -gff hints.intron.gff3 --getSubfeatures --subfeatureClasses '{"match_part": "darkblue-80pct"}' --className container-10px --trackLabel intron
# JBrowse Track 建立完毕，再创建索引
generate-names.pl

mkdir data/bigwig
cp *bw data/bigwig/
add-bw-track.pl --bw_url bigwig/A.bw --label A_bw --key "simulated BigWig A"
add-bw-track.pl --bw_url bigwig/D.bw --label D_bw --key "simulated BigWig D"

/home/train/smrtlink/admin/bin/services-stop
/opt/biosoft/WebApollo-2014-04-03/apache-tomcat-7.0.57/bin/startup.sh

# 访问 localhost:8080/webApollo_Malassezia_sympodialis/jbrowse/
