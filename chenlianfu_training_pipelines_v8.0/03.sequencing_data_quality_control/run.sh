# 1. 使用 FastQC 检测测序数据的质量
mkdir -p /home/train/03.sequencing_data_quality_control/FastQC
cd /home/train/03.sequencing_data_quality_control/FastQC
mkdir raw_data
/opt/biosoft/FastQC/fastqc -t 8 -o ./raw_data ~/00.incipient_data/data_for_gen*/*.fastq
# real	0m43.798s
# user	3m55.076s
# sys	0m7.017s

firefox http://localhost/train/03.sequencing_data_quality_control/FastQC/raw_data/
cd ..


# 2. 使用Trimmomatic软件对Illumina测序数据进行质量控制
mkdir -p /home/train/03.sequencing_data_quality_control/Trimmomatic
cd /home/train/03.sequencing_data_quality_control/Trimmomatic

<<### 纯二代数据进行基因组组装的示例(淘汰的流程，不建议操作) 对大肠杆菌的基因组De novo测序数据进行质量控制
#java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_genome_assembling/fragment.1.fastq ~/00.incipient_data/data_for_genome_assembling/fragment.2.fastq fragment.1.fastq fragment.1.unpaired.fastq fragment.2.fastq fragment.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE-2.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:10 MINLEN:36 TOPHRED33
#java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_genome_assembling/jumping.1.fastq ~/00.incipient_data/data_for_genome_assembling/jumping.2.fastq jumping.1.fastq jumping.1.unpaired.fastq jumping.2.fastq jumping.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE-2.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:10 MINLEN:27 TOPHRED33
###

# 对Malassezia sympodialis的基因组Illumina测序数据进行行质量控制
java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_genome_assembling/illumina.1.fastq ~/00.incipient_data/data_for_genome_assembling/illumina.2.fastq illumina.1.fastq illumina.1.unpaired.fastq illumina.2.fastq illumina.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE-2.fa:2:30:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33

# 对某一真核生物的基因组重测序数据进行质量控制
java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_variants_calling/V1.1.fastq ~/00.incipient_data/data_for_variants_calling/V1.2.fastq V1.1.fastq V1.1.unpaired.fastq V1.2.fastq V1.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33
java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_variants_calling/V2.1.fastq ~/00.incipient_data/data_for_variants_calling/V2.2.fastq V2.1.fastq V2.1.unpaired.fastq V2.2.fastq V2.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33

# 对某一真核生物的转录组测序数据进行质量控制
# 由于转录组测序的样本数量较多，使用Shell循环进行批处理
for i in `ls ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/*.1.fastq`
do
    i=${i/*\//}
    i=${i/.1.fastq/}
    java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/$i.1.fastq ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/$i.2.fastq $i.1.fastq $i.1.unpaired.fastq $i.2.fastq $i.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36 TOPHRED33
done
cd ..


# 3. 使用fastuniq软件去除基因组测序中的重复数据（PCR重复和optical重复）
mkdir -p /home/train/03.sequencing_data_quality_control/FastUniq
cd /home/train/03.sequencing_data_quality_control/FastUniq
ls ../Trimmomatic/illumina.?.fastq > illumina.list
fastuniq -i illumina.list -o illumina.1.fastq -p illumina.2.fastq

<<### 纯二代数据进行基因组组装的示例(淘汰的流程，不建议操作)
ls ../Trimmomatic/fragment.?.fastq > fragment.list
fastuniq -i fragment.list -o fragment.1.fastq -p fragment.2.fastq
ls ../Trimmomatic/jumping.?.fastq > jumping.list
fastuniq -i jumping.list -o jumping.1.fastq -p jumping.2.fastq
###

cd ..


# 4. 使用BLESS软件对reads进行修正
# 推荐使用较准确的paired-end测序数据生成数据库，对准确性相对较差的mate-pair数据进行校正。
mkdir -p /home/train/03.sequencing_data_quality_control/BLESS
cd /home/train/03.sequencing_data_quality_control/BLESS
source ~/.bashrc.gcc
bless -read1 ../FastUniq/illumina.1.fastq -read2 ../FastUniq/illumina.2.fastq -kmerlength 21 -prefix illumina
# real	0m25.883s
# user	3m0.716s
# sys	0m3.683s
ln -s illumina.1.corrected.fastq illumina.1.fastq
ln -s illumina.2.corrected.fastq illumina.2.fastq

<<### 纯二代数据进行基因组组装的示例(淘汰的流程，不建议操作)
source ~/.bashrc.gcc
bless -read1 ../FastUniq/fragment.1.fastq -read2 ../FastUniq/fragment.2.fastq -kmerlength 21 -prefix fragment
bless -read1 ../FastUniq/jumping.1.fastq -read2 ../FastUniq/jumping.2.fastq -load fragment -kmerlength 21 -prefix jumping
ln -s fragment.1.corrected.fastq fragment.1.fastq
ln -s fragment.2.corrected.fastq fragment.2.fastq
ln -s jumping.1.corrected.fastq jumping.1.fastq
ln -s jumping.2.corrected.fastq jumping.2.fastq
###

# 5. 使用Finderrors对Paired-End数据进行修正
# 可以输入准确的插入片段长度的均值和标准差，将有overlap的paired-end数据的两端连成一条更长的序列。这种方法有利于得到更长且准确的Illumina reads，适用于对错误率较高的三代基因组组装序列进行校正。
# 同时，也能对基因组信息（序列大小、重复序列含量、杂合率）进行评估。
mkdir -p /home/train/03.sequencing_data_quality_control/FindErrors
cd /home/train/03.sequencing_data_quality_control/FindErrors
ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=illumina KEEP_KMER_SPECTRA=1 PAIRED_READS_A_IN=../Trimmomatic/illumina.1.fastq PAIRED_READS_B_IN=../Trimmomatic/illumina.2.fastq PLOIDY=1 PAIRED_SEP=68 PAIRED_STDEV=66 &> ErrorCorrectReads.log
# real	6m31.220s
# user	34m28.982s
# sys	1m16.523s

ln -s illumina.paired.A.fastq illumina.1.fastq
ln -s illumina.paired.B.fastq illumina.2.fastq

# 进行 Kmer 作图
cd illumina.fastq.kspec
perl -p -i -e 's/(my \@fns.*)/$1\n\@fns = \(\"frag_reads_filt.25mer.kspec\", \"frag_reads_edit.24mer.kspec\", \"frag_reads_corr.25mer.kspec\"\);/' /opt/biosoft/ALLPATHS-LG/bin/KmerSpectrumPlot.pl
KmerSpectrumPlot.pl SPECTRA=1
perl -p -i -e 's/\@fns = \(\"frag_reads_filt.25mer.kspec\", \"frag_reads_edit.24mer.kspec\", \"frag_reads_corr.25mer.kspec\"\);\n//' /opt/biosoft/ALLPATHS-LG/bin/KmerSpectrumPlot.pl
convert kmer_spectrum.cumulative_frac.log.lin.eps kmer_spectrum.cumulative_frac.log.lin.png
convert kmer_spectrum.distinct.lin.lin.eps kmer_spectrum.distinct.lin.lin.png
convert kmer_spectrum.distinct.log.log.eps kmer_spectrum.distinct.log.log.png

<<### 纯二代数据进行基因组组装的示例(淘汰的流程，不建议操作)
ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=fragment FILL_FRAGMENTS=1 KEEP_KMER_SPECTRA=1 PAIRED_READS_A_IN=../Trimmomatic/fragment.1.fastq PAIRED_READS_B_IN=../Trimmomatic/fragment.2.fastq PLOIDY=1 PAIRED_SEP=-25 PAIRED_STDEV=25
ln -s fragment.paired.A.fastq fragment.1.fastq
ln -s fragment.paired.B.fastq fragment.2.fastq
# 进行 Kmer 作图
cd fragment.fastq.kspec
perl -p -i -e 's/(my \@fns.*)/$1\n\@fns = \(\"frag_reads_filt.25mer.kspec\", \"frag_reads_edit.24mer.kspec\", \"frag_reads_corr.25mer.kspec\"\);/' /opt/biosoft/ALLPATHS-LG/bin/KmerSpectrumPlot.pl
KmerSpectrumPlot.pl SPECTRA=1
perl -p -i -e 's/\@fns = \(\"frag_reads_filt.25mer.kspec\", \"frag_reads_edit.24mer.kspec\", \"frag_reads_corr.25mer.kspec\"\);\n//' /opt/biosoft/ALLPATHS-LG/bin/KmerSpectrumPlot.pl
convert kmer_spectrum.cumulative_frac.log.lin.eps kmer_spectrum.cumulative_frac.log.lin.png
convert kmer_spectrum.distinct.lin.lin.eps kmer_spectrum.distinct.lin.lin.png
convert kmer_spectrum.distinct.log.log.eps kmer_spectrum.distinct.log.log.png
# 不推荐直接使用Finderrors对Mate-Pair数据进行修正，是因为Finderrors不能使用准确的Paired-End数据对Mate-Pair数据进行修正。
###

cd ..


# 6. 使用 PacBioToCA 进行 reads 的修正
mkdir -p /home/train/03.sequencing_data_quality_control/PacBioToCA
cd /home/train/03.sequencing_data_quality_control/PacBioToCA

# 使用 PacBiToCA 对 E.coli 的 Pacbio 数据进行修正
#export PATH=$PATH:/home/smrtanalysis/install/smrtanalysis_2.3.0.140936/analysis/bin/
#export PATH=/opt/sysoft/jre1.8.0_45/bin/:$PATH
#pls2fasta -fastq -trimByRegion ~/01.high_throughput_data_download/ecoliK12/Analysis_Results/m130404_014004_sidney_c100506902550000001823076808221337_s1_p0.bas.h5 pacbio_subreads.fastq
#head -n 120000 pacbio_subreads.fastq > ~/00.incipient_data/data_for_genome_assembling/pacbio_subreads.fastq
echo "assemble=0" > pacbio.spec
ln -s ../FindErrors/fragment.?.fastq ./
fastqToCA -insertsize 177 25 -libraryname pe150 -mates fragment.1.fastq,fragment.2.fastq > illumina.frg
PBcR -libraryname E_coli_pacbio -s pacbio.spec -fastq ~/00.incipient_data/data_for_genome_assembling/pacbio_subreads.fastq -genomeSize 4600000 -maxCoverage 40 illumina.frg &> pacbiotoca.log
# real    141m26.718s
# user    489m7.042s
# sys     24m10.249s

# 使用官网提供的示例数据
#wget http://www.cbcb.umd.edu/software/PBcR/data/sampleData.tar.gz -O ~/00.incipient_data/data_for_genome_assembling/PacBioToCA_sampleData.tar.gz
tar zxf ~/00.incipient_data/data_for_genome_assembling/PacBioToCA_sampleData.tar.gz
cd sampleData
# 自我校正
java -jar convertFastaAndQualToFastq.jar pacbio.filtered_subreads.fasta > pacbio.filtered_subreads.fastq
PBcR -length 500 -partitions 200 -l lambda -s pacbio.spec -fastq pacbio.filtered_subreads.fastq genomeSize=50000 &> lambda_pacbiotoca.log
# real	1m46.910s
# user	4m9.361s
# sys	0m38.952sG
# 使用 Illumina 数据进行校正
fastqToCA -libraryname illumina -technology illumina -type sanger -innie -reads illumina.fastq > illumina.frg
java -jar convertFastaAndQualToFastq.jar pacbio.filtered_subreads.fasta > pacbio.filtered_subreads.fastq 
PBcR -length 500 -partitions 200 -l lambdaIll -s pacbio.spec -fastq pacbio.filtered_subreads.fastq genomeSize=50000 illumina.frg > lambdaIll_pacbiotoca.log 2>&1
# real	2m13.707s
# user	5m11.338s
# sys	0m20.958s


# 9. 使用 LoRDEC 对 PacBio Reads 进行修正
mkdir -p /home/train/03.sequencing_data_quality_control/LoRDEC
cd /home/train/03.sequencing_data_quality_control/LoRDEC
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
lordec-correct -2 ../BLESS/illumina.1.corrected.fastq,../BLESS/illumina.2.corrected.fastq -i subreads.fasta -k 17 -o subreads.corrected.fasta -s 3 -T 8 &> lordec-correct.log
# real	28m13.080s
# user	104m32.074s
# sys	0m39.412s
lordec-trim -i subreads.corrected.fasta -o subreads.corrected.trimmed.fasta
lordec-trim-split -i subreads.corrected.fasta -o subreads.corrected.trim-split.fasta
