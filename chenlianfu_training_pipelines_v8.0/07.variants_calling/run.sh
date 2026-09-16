mkdir -p /home/train/07.variants_calling
cd /home/train/07.variants_calling

# 准备输入的BAM文件和参考基因组文件
ln -s ~/06.reads_aligment/bowtie2/*.sam ./
samtools sort -@ 4 -O BAM -o V1.bam V1.sam
samtools sort -@ 4 -O BAM -o V2.bam V2.sam
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=~/06.reads_aligment/bowtie2/V1.bam O=V1.bam M=V1.metrics
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=~/06.reads_aligment/bowtie2/V2.bam O=V2.bam M=V2.metrics
samtools index V1.bam
samtools index V2.bam

ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
samtools faidx genome.fasta
java -jar /opt/biosoft/picard-tools/picard.jar CreateSequenceDictionary R=genome.fasta O=genome.dict

# 使用 GATK HaplotypeCaller 进行 SNP/InDel calling
mkdir -p /home/train/07.variants_calling/GATK
cd /home/train/07.variants_calling/GATK
# 准备 bam 文件和基因组文件
ln -s ../*bam* .
ln -s ../genome.* .
# 运行HaplotypeCaller分别对单个样品进行variants分析
gatk HaplotypeCaller -R genome.fasta -I V1.bam -ERC GVCF -O V1.g.vcf --pcr-indel-model CONSERVATIVE --sample-ploidy 2 --min-base-quality-score 10 --kmer-size 10 --kmer-size 25
# real	2m13.747s
# user	4m26.141s
# sys	0m1.111s

gatk HaplotypeCaller -R genome.fasta -I V2.bam -ERC GVCF -O V2.g.vcf --pcr-indel-model CONSERVATIVE --sample-ploidy 2 --min-base-quality-score 10 --kmer-size 10 --kmer-size 25
# real	2m26.303s
# user	5m44.855s
# sys	0m1.106s

# 运行CombineGVCFs将多个GVCF文件进行整合
gatk CombineGVCFs -R genome.fasta -O combined.g.vcf -V V1.g.vcf -V V2.g.vcf
# real	0m16.789s
# user	0m33.000s
# sys	0m0.811s

# 运行GenotypeGVCFs鉴定joint-called variants
gatk GenotypeGVCFs -R genome.fasta -O variants.raw.vcf -V combined.g.vcf --sample-ploidy 2
# real	0m14.088s
# user	0m25.331s
# sys	0m0.668s

# 运行VariantFiltration对variants结果进行hard filtering。理论上，更好的filtering方法是根据已有的准确的variants位点，通过机器学习的方法来进行variant quality score recalibration (VQSR)。该方法使用的命令是VariantRecalibrator。适用与大样本数，大数据，不适合小样本，简化基因组测序和转录组测序等。
gatk VariantFiltration -R genome.fasta -O variants.filter.vcf -V variants.raw.vcf --filter-name FilterQual --filter-expression "QUAL < 30.0" --filter-name FilterQD --filter-expression "QD < 13.0" --filter-name FilterMQ --filter-expression "MQ < 20.0" --filter-name FilterFS --filter-expression "FS > 20.0" --filter-name FilterMQRankSum --filter-expression "MQRankSum < -3.0" --filter-name FilterReadPosRankSum --filter-expression "ReadPosRankSum < -3.0" --filter-name FilterBaseQRankSum --filter-expression "BaseQRankSum < -3.0"
# real	0m3.596s
# user	0m5.314s
# sys	0m0.233s

grep -v -P "\tFilter" variants.filter.vcf > variants.vcf


# 使用 samtools 进行 SNP/InDel calling
mkdir -p /home/train/07.variants_calling/samtools
cd /home/train/07.variants_calling/samtools
# 准备 bam 文件和基因组文件
ln -s ../*bam* .
ln -s ../genome.* .

samtools mpileup -f genome.fasta V1.bam > mpileup.txt
# real	1m35.457s
# user	1m34.788s
# sys	0m0.668s

samtools mpileup -t AD,ADF,ADR,DP,SP -gf genome.fasta V1.bam V2.bam > variants.bcf
# real	4m51.489s
# user	4m51.116s
# sys	0m0.325s

bcftools call -vm variants.bcf > variants.vcf
# real	0m5.202s
# user	0m5.088s
# sys	0m0.098s

samtools mpileup -ugf genome.fasta V1.bam V2.bam | bcftools call -vm > variants.vcf
# real	4m19.176s
# user	4m23.800s
# sys	0m2.519s

vcfutils.pl varFilter variants.vcf > variants.filter.vcf


# Variants calling的bam文件准备
mkdir -p /home/train/07.variants_calling/bam_preparing_for_variants_calling
cd /home/train/07.variants_calling/bam_preparing_for_variants_calling
ln -s ~/00.incipient_data/data_for_variants_calling/V?.?.fastq .
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta


#对raw data进行数据预处理和比对，得到BAM文件
mkdir data_preprocessing
cd data_preprocessing
java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ../V1.1.fastq ../V1.2.fastq V1.1.fastq V1.1.unpaired.fastq V1.2.fastq V1.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33
java -jar /opt/biosoft/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 4 ../V2.1.fastq ../V2.2.fastq V2.1.fastq V2.1.unpaired.fastq V2.2.fastq V2.2.unpaired.fastq ILLUMINACLIP:/opt/biosoft/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33

bowtie2-build ../genome.fasta genome
bowtie2 -p 8 -x genome -1 V1.1.fastq -2 V1.2.fastq -S V1.sam 2> V1.bowtie2.log
bowtie2 -p 8 -x genome -1 V2.1.fastq -2 V2.2.fastq -S V2.sam 2> V2.bowtie2.log
samtools sort -@ 8 -O BAM -o V1.bam V1.sam
samtools sort -@ 8 -O BAM -o V2.bam V2.sam

java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=V1.bam REMOVE_DUPLICATES=true O=V1.rd.bam M=V1.metrics 
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=V2.bam REMOVE_DUPLICATES=true O=V2.rd.bam M=V2.metrics

java -jar /opt/biosoft/picard-tools/picard.jar SamToFastq I=V1.rd.bam F=V1.rd.1.fastq F2=V1.rd.2.fastq
java -jar /opt/biosoft/picard-tools/picard.jar SamToFastq I=V2.rd.bam F=V2.rd.1.fastq F2=V2.rd.2.fastq

source ~/.bashrc.gcc 
bless -read1 V1.rd.1.fastq -read2 V1.rd.2.fastq -kmerlength 21 -prefix V1
bless -read1 V2.rd.1.fastq -read2 V2.rd.2.fastq -kmerlength 21 -prefix V2

bowtie2 -p 4 -x genome --score-min L,-0.3,-0.3 --rg-id V1 --rg SM:V1 --rg PL:ILLUMINA -1 V1.1.corrected.fastq -2 V1.2.corrected.fastq -S V1.corr.sam 2> V1.corr.bowtie2.log
bowtie2 -p 4 -x genome --score-min L,-0.3,-0.3 --rg-id V2 --rg SM:V2 --rg PL:ILLUMINA -1 V2.1.corrected.fastq -2 V2.2.corrected.fastq -S V2.corr.sam 2> V2.corr.bowtie2.log
samtools sort -@ 4 -O BAM -o V1.corr.bam V1.corr.sam
samtools sort -@ 4 -O BAM -o V2.corr.bam V2.corr.sam

java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=V1.corr.bam REMOVE_DUPLICATES=true O=../V1.bam M=V1.metrics
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=V2.corr.bam REMOVE_DUPLICATES=true O=../V2.bam M=V2.metrics
cd ..


# 根据INDEL信息批量设计引物
mkdir -p /home/train/07.variants_calling/INDEL_primer_design
cd /home/train/07.variants_calling/INDEL_primer_design
ln -s ../genome.* .
gatk SelectVariants -R genome.fasta -V ../GATK/variants.vcf -O INDELs.vcf --select-type-to-include INDEL 
ln -s ~/05.genome_feature_analysis/SSR_detecting_and_primer_design/p3_settings_file .
VCF_InDel_primer3.pl INDELs.vcf genome.fasta --CPU 4 --p3_setting_file p3_settings_file --gff3_out VCF_InDel_primer3.gff3 > VCF_InDel_primer3.out
# real	3m0.606s
# user	21m44.174s
# sys	0m0.546s


mkdir -p /home/train/07.variants_calling/SnpEff
cd /home/train/07.variants_calling/SnpEff
#构建SnpEff数据库
mkdir -p /opt/biosoft/snpEff/data/malassezia_sympodialis/
cp ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta /opt/biosoft/snpEff/data/malassezia_sympodialis/sequences.fa
gff3_remove_UTR.pl ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gff3 > Malassezia_sympodialis.gff3
gff3ToGtf.pl ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta Malassezia_sympodialis.gff3 > /opt/biosoft/snpEff/data/malassezia_sympodialis/genes.gtf
perl -p -i -e 's/^\s*$//' /opt/biosoft/snpEff/data/malassezia_sympodialis/genes.gtf

echo "malassezia_sympodialis.genome : malassezia sympodialis" >> /opt/biosoft/snpEff/snpEff.config
java -jar /opt/biosoft/snpEff/snpEff.jar build -c /opt/biosoft/snpEff/snpEff.config -gtf22 -v malassezia_sympodialis

#运行SnpEff注释程序
java -Xmx2G -jar /opt/biosoft/snpEff/snpEff.jar eff -csvStats variants.SnpEff.csv -s variants.SnpEff.html -c /opt/biosoft/snpEff/snpEff.config -v -ud 500 malassezia_sympodialis ~/00.incipient_data/data_for_variants_calling/variants.vcf > variant.SnpEff.vcf
# real	0m6.132s
# user	0m11.224s
# sys	0m0.369s
