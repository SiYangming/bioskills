## 此部分内容用于下载本教材中的示例数据。由于示例数据已保存到了00.incipient_data目录下，因此无需运行本run.sh文件中代码。

# 1. (已经淘汰，不建议操作) 下载一代数据进行基因组组装的454测序数据
# SRR797242
# lftp -e "get -c /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra; exit" ftp-trace.ncbi.nlm.nih.gov
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./
sff-dump SRR797242/SRR797242.sra
sfffile -pickr 300000 SRR797242.sff
mv 454Reads.sff ~/00.incipient_data/data_for_genome_assembling/


# 2. (已经淘汰，不建议操作) 下载纯二代数据进行基因组装的Illumina测序数据。物种为E.coli K-12 MG1655
# fragment library : SRR447685
# jumping library : SRR401827, SRR492488, SRR522159
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv /sra/sra-instant/reads/ByRun/sra/SRR/SRR447/SRR447685 ./
# 取~80x数据用于培训数据
fatq-dump --split-files SRR447685/SRR447685.sra
mkdir -p ~/00.incipient_data/data_for_genome_assembling/
head -n 8000000 SRR447685_1.fastq > ~/00.incipient_data/data_for_genome_assembling/fragment.1.fastq
head -n 8000000 SRR447685_3.fastq > ~/00.incipient_data/data_for_genome_assembling/fragment.2.fastq
# insert size : 177 25

ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv /sra/sra-instant/reads/ByRun/sra/SRR/SRR401/SRR401827 ./
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv /sra/sra-instant/reads/ByRun/sra/SRR/SRR492/SRR492488 ./
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv /sra/sra-instant/reads/ByRun/sra/SRR/SRR522/SRR522159 ./
# 这3组数据，在数据质量上 SRR492488 > SRR522159 > SRR401827
cat SRR492488_1.fastq SRR522159_1.fastq > ~/00.incipient_data/data_for_genome_assembling/jumping.1.fastq
cat SRR492488_2.fastq SRR522159_2.fastq > ~/00.incipient_data/data_for_genome_assembling/jumping.2.fastq
tail -n 5000000 SRR401827_1.fastq >> ~/00.incipient_data/data_for_genome_assembling/jumping.1.fastq
tail -n 5000000 SRR401827_3.fastq >> ~/00.incipient_data/data_for_genome_assembling/jumping.2.fastq 
# insert size : 3100 1200


# 3. 下载三代数据进行基因组装的PacBio测序数据。物种为Malassezia sympodialis
# 基因在包含多条染色体且基因组大小较小的物种。定位真菌中的担子菌物种。在https://www.ncbi.nlm.nih.gov/genome/browse数据中搜索basidiomycetes，并按基因组大小排序，锁定基因组大小只有7.5MB的Malassezia属的物种。
# 然后，在NCBI SRA数据库中搜索“Malassezia PacBio”，寻找有Pacbio测序数据和Illumina测序数据的物种。最后选定物种为Malassezia sympodialis (ATCC 42132)。
# PacBio测序数据：ERR1358792
# Illumina测序数据：SRR2131197 (三代测序数据一般要测一个Illumina文科数据，用于基因评估、二代三代数据混合组装和最后的基因组序列校正)
wget https://sra-download.ncbi.nlm.nih.gov/traces/era10/ERZ/001358/ERR1358792/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.1.bax.h5
wget https://sra-download.ncbi.nlm.nih.gov/traces/era10/ERZ/001358/ERR1358792/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.2.bax.h5
wget https://sra-download.ncbi.nlm.nih.gov/traces/era10/ERZ/001358/ERR1358792/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.3.bax.h5
wget https://sra-download.ncbi.nlm.nih.gov/traces/era10/ERZ/001358/ERR1358792/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.bas.h5
wget https://sra-download.ncbi.nlm.nih.gov/traces/era10/ERZ/001358/ERR1358792/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.metadata.xml
mkdir -p m150226_221858_42237/Analysis_Results
mv *.h5 m150226_221858_42237/Analysis_Results
mv m150226_221858_42237_*.xml m150226_221858_42237/
mv m150226_221858_42237/ ~/00.incipient_data/data_for_genome_assembling

prefetch SRR2131197
mv ~/ncbi/public/sra/SRR2131197 ~/00.incipient_data/data_for_genome_assembling

# 下载的数据量较大，为了能在内存较小的笔记本电脑上运行，此处选择~50x的数据量。若是计算性能好，推荐使用全部数据。
/home/train/smrtlink/smrtcmds/bin/bax2bam -o m150226_221858_42237 --subread ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237/Analysis_Results/*.h5
samtools view -h m150226_221858_42237.subreads.bam | head -n 60000 | samtools view -b > ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
/home/train/smrtlink/smrtcmds/bin/pbindex ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam

fastq-dump --split-files ~/00.incipient_data/data_for_genome_assembling/SRR2131197.sra
head -n 9000000 SRR2131197_1.fastq > ~/00.incipient_data/data_for_genome_assembling/illumina.1.fastq
head -n 9000000 SRR2131197_2.fastq > ~/00.incipient_data/data_for_genome_assembling/illumina.2.fastq


# 4. 下载三代数据进行全长转录组组装的PacBio测序数据。官网示例中的数据，物种未知。
lftp -e 'pget -n 100 https://downloads.pacbcloud.com/public/dataset/RC0_1cell_2017/m54086_170204_081430.subreads.bam; exit'
wget https://downloads.pacbcloud.com/public/dataset/RC0_1cell_2017/m54086_170204_081430.subreads.bam.pbi
wget https://downloads.pacbcloud.com/public/dataset/RC0_1cell_2017/m54086_170204_081430.subreadset.xml


# 5. 下载重测序数据。物种为Malassezia sympodialis
# Malassezia sympodialis ATCC 96806
prefetch SRR2132331
# Malassezia sympodialis ATCC 44340
prefetch SRR2132329
mv ~/ncbi/public/sra/SRR21323* ~/00.incipient_data/data_for_variants_calling/

# 下载的数据量较大，为了能在内存较小的笔记本电脑上运行，此处选择~50x的数据量。若是计算性能好，推荐使用全部数据。
fastq-dump --split-files ~/00.incipient_data/data_for_variants_calling/SRR2132331.sra
head -n 9000000 SRR2132331_1.fastq > ~/00.incipient_data/data_for_variants_calling/V1.1.fastq
head -n 9000000 SRR2132331_2.fastq > ~/00.incipient_data/data_for_variants_calling/V1.2.fastq
fastq-dump --split-files ~/00.incipient_data/data_for_variants_calling/SRR2132329.sra
head -n 9000000 SRR2132329_1.fastq > ~/00.incipient_data/data_for_variants_calling/V2.1.fastq
head -n 9000000 SRR2132329_2.fastq > ~/00.incipient_data/data_for_variants_calling/V2.2.fastq


# 6. 下载Illumina转录组测序数据
# 将Malassezia sympodialis(ATCC 42132) 培养4天
prefetch ERR1337978
prefetch ERR1337977
prefetch ERR1337976
# 将Malassezia sympodialis(ATCC 42132) 培养2天
prefetch ERR1337975
prefetch ERR1337974
prefetch ERR1337973
prefetch ERR1337972
mv ~/ncbi/public/sra/ERR133797* ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/

# 下载的数据量较大，为了能在内存较小的笔记本电脑上运行，此处选择~50x的数据量。若是计算性能好，推荐使用全部数据。
for i in `ls ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/ERR133*`
do
    fastq-dump --split-files --defline-seq '@$sn[_$rn]/$ri' $i
done

head -n 6000000 ERR1337978_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/A.1.fastq
head -n 6000000 ERR1337978_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/A.2.fastq
head -n 6000000 ERR1337977_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/B.1.fastq
head -n 6000000 ERR1337977_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/B.2.fastq
head -n 6000000 ERR1337976_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/C.1.fastq
head -n 6000000 ERR1337976_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/C.2.fastq
head -n 6000000 ERR1337975_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/D.1.fastq
head -n 6000000 ERR1337975_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/D.2.fastq
head -n 6000000 ERR1337974_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/E.1.fastq
head -n 6000000 ERR1337974_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/E.2.fastq
head -n 6000000 ERR1337973_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/F.1.fastq
head -n 6000000 ERR1337973_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/F.2.fastq
head -n 6000000 ERR1337972_1.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/G.1.fastq
head -n 6000000 ERR1337972_2.fastq > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/G.2.fastq
perl -i -e 'while (<>) { s/#.*\//\//; print; $_ = <>; print; $_ = <>; print; $_ = <>; print; }' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/?.?.fastq
