mkdir -p /home/train/06.reads_aligment
cd /home/train/06.reads_aligment

# Bowtie2 practise
mkdir -p /home/train/06.reads_aligment/bowtie2
cd /home/train/06.reads_aligment/bowtie2

ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/V?.?.fastq ./

bowtie2-build --threads 8 genome.fasta genome
bowtie2 -p 8 -x genome -1 V1.1.fastq -2 V1.2.fastq -S V1.sam --rg-id V1 --rg "PL:Illumina" --rg "SM:V1" 2> V1.bowtie2.log
# real	1m26.553s
# user	11m12.705s
# sys	0m13.891s

bowtie2 -p 8 -x genome -1 V2.1.fastq -2 V2.2.fastq -S V2.sam --rg-id V2 --rg "PL:Illumina" --rg "SM:V2" 2> V2.bowtie2.log

# BWA practise
mkdir -p /home/train/06.reads_aligment/bwa
cd /home/train/06.reads_aligment/bwa

ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/V?.?.fastq ./

bwa index genome.fasta -p genome

bwa mem -t 8 genome V1.1.fastq V1.2.fastq > V1.mem.sam
# real	0m23.141s
# user	2m31.3.0s
# sys	0m3.354s

bwa bwasw -t 8 genome V1.1.fastq V1.2.fastq > V1.bwasw.sam
# real	2m31.854s
# user	18m43.008s
# sys	0m30.774s

bwa aln -t 8 genome V1.1.fastq > V1.1.sai
# real	0m9.566s
# user	1m2.180s
# sys	0m0.321s
bwa aln -t 8 genome V1.2.fastq > V1.2.sai
bwa sampe genome V1.1.sai V1.2.sai V1.1.fastq V1.2.fastq > V1.backtrack.sam
# real	0m24.595s
# user	0m20.893s
# sys	0m1.737s


# Tophat Practise
mkdir -p /home/train/06.reads_aligment/tophat
cd /home/train/06.reads_aligment/tophat
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gtf > genome.gtf
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/?.?.fastq ./

bowtie2-build genome.fasta ref
for i in `ls *.1.fastq`
do
    i=${i/.1.fastq/}
    echo "tophat -N 3 --read-edit-dist 3 -p 8 -i 20 -I 4000 --min-segment-intron 20 --max-segment-intron 4000 --min-coverage-intron 20 --max-coverage-intron 4000 --coverage-search --microexon-search -G genome.gtf -o $i ref $i.1.fastq $i.2.fastq"
done > command.tophat.list
sh command.tophat.list
# real	36m24.415s
# user	73m24.766s
# sys	24m7.580s


# HISAT2 Practise
mkdir -p /home/train/06.reads_aligment/hisat2
cd /home/train/06.reads_aligment/hisat2
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gtf > genome.gtf
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/?.?.fastq ./

perl -e 'while (<>) { if (m/^#/) { print; next } $number ++; $num = "ms" . "0" x (7 - length($number)) . $number; s/\t\.\t/\t$num\t/; print; }' ~/00.incipient_data/data_for_variants_calling/variants.vcf > variants.vcf
hisat2_extract_splice_sites.py genome.gtf > splitSites.txt
hisat2_extract_exons.py genome.gtf > exonSites.txt
hisat2_extract_snps_VCF.pl variants.vcf > variants.snp
hisat2-build -p 8 --snp variants.snp --ss splitSites.txt --exon exonSites.txt genome.fasta genome
# real	0m10.630s
# user	0m35.049s
# sys	0m2.058s

for i in `ls *.1.fastq`
do
    i=${i/.1.fastq/}
    echo "hisat2 -x genome -p 8 --min-intronlen 20 --max-intronlen 4000 --dta --dta-cufflinks -1 $i.1.fastq -2 $i.2.fastq -S $i.sam --new-summary --summary-file $i.hisat2.summary"
done > command.hisat2.list
sh command.hisat2.list
# real	1m30.745s
# user	7m34.816s
# sys	4m8.138s


# Blasr Practise
mkdir -p /home/train/06.reads_aligment/blasr
cd /home/train/06.reads_aligment/blasr
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
ln -s ~/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta ./

PATH=/home/train/smrtlink/smrtcmds/bin:$PATH
sawriter genome.fasta.sa genome.fasta
blasr subreads.fasta genome.fasta --sa genome.fasta.sa --header -m 5 --out blasr.out5 --minPctAccuracy 70 --nproc 8 --stride 10
# real	1m23.424s
# user	10m55.902s
# sys	0m1.076s

perl -e '<>; while (<>) { @_ = split /\s+/; next if exists $qname{$_[0]}; $num ++ if $_[11] / $_[1] >= 0.7; $qname{$_[0]} = 1; } $qname = keys %qname;  print "$num\t$qname\n"' blasr.out5
perl -e '<>; while (<>) { @_ = split /\s+/; next if exists $qname{$_[0]}; $mm = ($_[12] + $_[13] + $_[14]) / $_[11]; push @mm, $mm if $_[1] >= 1000; } @mm = sort {$a <=> $b} @mm; print "$mm[@mm/2]\n";' blasr.out5


# Samtools Practise
cd /home/train/06.reads_aligment/bowtie2
samtools sort -@ 8 -o V1.bam -O BAM V1.sam
samtools sort -@ 8 -o V2.bam -O BAM V2.sam
samtools index V1.bam
samtools view -h V1.bam MS01Contig1:10000-20000 | less -S
samtools view -h -b V1.bam contig1 > V1.contig1.bam
samtools view -h -f 64 V1.bam | samtools view -h -F 4 | les
samtools faidx genome.fasta MS01Contig2:40000-42000 | les
samtools tview V1.bam genome.fasta

samtools view -b -f 64 V1.bam > V1.f64.bam
samtools index V1.f64.bam
samtools tview V1.f64.bam genome.fasta

cd /home/train/06.reads_aligment/hisat2
samtools sort -@ 4 -o A.bam -O BAM A.sam 
samtools index A.bam 
samtools faidx genome.fasta 
samtools tview A.bam genome.fasta
samtools view -b -f 64 A.bam > A.f64.bam
samtools index A.f64.bam
samtools tview A.f64.bam genome.fasta


# Picard Practise
mkdir -p /home/train/06.reads_aligment/picard
cd /home/train/06.reads_aligment/picard

ln -s ../bowtie2/V1.sam ./
java -jar /opt/biosoft/picard-tools/picard.jar SortSam I=V1.sam O=V1.bam SO=coordinate
java -jar /opt/biosoft/picard-tools/picard.jar CollectInsertSizeMetrics I=V1.bam O=insertSize.txt H=insertSize.pdf W=1000
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=V1.bam O=V1.MarkDuplicates.bam M=V1.MarkDuplicates.metrics
