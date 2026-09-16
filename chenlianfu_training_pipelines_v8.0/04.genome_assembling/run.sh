# 1. 基因组评估
# 1.1 使用 GCE 进行基因组评估
mkdir -p /home/train/04.genome_assembling/GCE
cd /home/train/04.genome_assembling/GCE
ls /home/train/03.sequencing_data_quality_control/FastUniq/illumina.?.fastq > reads.list

/opt/biosoft/gce-1.0.0/kmerfreq/kmer_freq_hash/kmer_freq_hash -k 21 -l reads.list -t 8 -i 80000000 -o 0 -p out &> kmer_freq.log
# real	0m15.453s
# user	1m30.543s
# sys	0m2.369s

/opt/biosoft/gce-1.0.0/gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 > out.table 2> out.log
# real	0m18.747s
# user	0m18.687s
# sys	0m0.059s
 
# 若是杂合基因组测序数据，则要添加 -H 1 参数
#/opt/biosoft/gce-1.0.0/gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 -H 1 > out.h1.table 2> out.h1.log

# kmer 图制作
perl -e 'print "dep\tnum\n";while (<>) {print}' out.freq.stat > 11
echo 'a <- read.table("11", header=TRUE);
library("ggplot2")
png(file="dep_num.png",bg="transparent")
qplot(dep, num, data=a, ylim=c(0,3e5), xlim=c(0,180), geom=c("line"))
dev.off()
png(file="dep_individual.png",bg="transparent")
qplot(dep, num*dep, data=a, ylim=c(0,1e7), xlim=c(0,180), geom=c("line"))
dev.off()' | R --vanilla --slave
cd ..

# 1.2 使用genomescope 2.0进行基因组评估
mkdir ~/04.genome_assembling/genomescope2.0
cd ~/04.genome_assembling/genomescope2.0
ln -s /home/train/03.sequencing_data_quality_control/FastUniq/illumina.?.fastq ./
# 使用jellyfish进行k-mer分析
jellyfish count -C -m 21 -s 100000000 -t 4 -o mer_counts.jf *.fastq
jellyfish histo -t 4 mer_counts.jf > mer_counts.histo
# 使用genomescope 2.0进行k-mer作图和基因组评估
/opt/biosoft/genomescope2.0-1.0.0/genomescope.R -i mer_counts.histo -o genomescope -k 21 -p 1 > genomescope.out
eog genomescope/linear_plot.png


# 2. 使用 Newbler 对454测序数据进行组装
mkdir -p /home/train/04.genome_assembling/Newbler
cd /home/train/04.genome_assembling/Newbler
runAssembly -o ./ -force -tr ~/00.incipient_data/data_for_genome_assembling/454Reads.sff 
# 由于程序输入的文件目录已经存在，需要加参数 -force 来强制将结果输出到存在的目录。若输出文件目录不存在，则可以不许要参数 -force 。
# real	13m8.886s
# user	12m7.195s
# sys	0m3.947s


# 4. 使用 IDBA 进行基因组组装
mkdir -p /home/train/04.genome_assembling/IDBA
cd /home/train/04.genome_assembling/IDBA
fq2fa --filter --merge ~/03.sequencing_data_quality_control/FindErrors/illumina.1.fastq ~/03.sequencing_data_quality_control/FindErrors/illumina.2.fastq illumina.fasta
idba_ud -r illumina.fasta --mink 20 --maxk 100 --step 20
# real	2m38.996s
# user	18m5.808s
# sys	0m5.169s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix idba out/contig.fa > IDBA.fasta
cd ..


# 4. 使用 SOAPdenovo 进行基因组组装
mkdir -p /home/train/04.genome_assembling/SOAPdenovo
cd /home/train/04.genome_assembling/SOAPdenovo
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.1.corrected.fastq jumping.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.2.corrected.fastq jumping.2.fastq
echo "max_rd_len=101
[LIB]
avg_ins=177
reverse_seq=0
asm_flags=1
rd_len_cutoff=100
rank=1
pair_num_cutoff=3
map_len=32
q1=/home/train/04.genome_assembling/SOAPdenovo/fragment.1.fastq
q2=/home/train/04.genome_assembling/SOAPdenovo/fragment.2.fastq
[LIB]
avg_ins=3000
reverse_seq=1
asm_flags=2
rd_len_cutoff=63
rank=2
pair_num_cutoff=5
map_len=35
q1=/home/train/04.genome_assembling/SOAPdenovo/jumping.1.fastq
q2=/home/train/04.genome_assembling/SOAPdenovo/jumping.2.fastq" > config.txt
mkdir out_K51
SOAPdenovo-63mer all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R &> soapdenovo.log
# real	0m35.196s
# user	1m24.200s
# sys	0m20.939s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix soapdenovo out_K51/E_coli.scafSeq > SOAPdenovo.fasta
cd ..


# 5. 使用 ALLPAHTS-LG 进行基因组组装
mkdir -p /home/train/04.genome_assembling/ALLPATHS-LG
cd /home/train/04.genome_assembling/ALLPATHS-LG

ln -s ~/03.sequencing_data_quality_control/Trimmomatic/fragment.?.fastq ./
ln -s ~/03.sequencing_data_quality_control/Trimmomatic/jumping.?.fastq ./

echo 'group_name, library_name, file_name
frags, Illumina_180bp, fragment.?.fastq
jumps, Illumina_3000bp, jumping.?.fastq' > in_groups.csv
echo 'library_name, project_name, organism_name, type, paired, frag_size, frag_stddev, insert_size, insert_stddev, read_orientation, genomic_start, genomic_end
Illumina_180bp, E_coli.genome, E.coli, fragment, 1, 177, 25, , , inward, 0, 0
Illumina_3000bp, E_coli.genome, E.coli, jumping, 1, , , 3014, 1204, outward, 0, 0' > in_libs.csv

ulimit -s 100000
mkdir -p E_coli.genome/data
PrepareAllPathsInputs.pl \
  DATA_DIR=$PWD/E_coli.genome/data \
  PLOIDY=1 \
  IN_GROUPS_CSV=in_groups.csv \
  IN_LIBS_CSV=in_libs.csv \
  OVERWRITE=True \
  | tee prepare.out
# real	0m29.448s
# user	0m9.619s
# sys	0m3.905s
RunAllPathsLG \
  PRE=$PWD \
  REFERENCE_NAME=E_coli.genome \
  DATA_SUBDIR=data \
  RUN=run \
  SUBDIR=test \
  OVERWRITE=True \
  MAXPAR=1 \
  | tee -a assemble.out
# real    14m50.312s
# user    44m8.382s
# sys     2m6.232s
# 消耗内存峰值6.9GB
ln -s E_coli.genome/data/run/ASSEMBLIES/test/final.assembly.fasta ./
EfastaToFasta HEAD=E_coli.genome/data/run/ASSEMBLIES/test/final.assembly SPLIT_DIR=scaffolds IUPAC=False
perl -p -i -e 's/n/N/g' scaffolds/*.fsa
cat scaffolds/*.fsa > allpathslg.fasta


# 6. 使用 MaSuRCA 进行基因组组装
mkdir /home/train/04.genome_assembling/MaSuRCA/
cd /home/train/04.genome_assembling/MaSuRCA/

ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq ./
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
echo "DATA
PE= p1 268 66 illumina.1.fastq illumina.2.fastq
PACBIO=/home/train/04.genome_assembling/MaSuRCA/subreads.fasta
END

PARAMETERS
GRAPH_KMER_SIZE=auto
USE_LINKING_MATES=0
USE_GRID=0
LHE_COVERAGE=40
MEGA_READS_ONE_PASS=0
CA_PARAMETERS =  cgwErrorRate=0.15
CLOSE_GAPS=1
NUM_THREADS=8
JF_SIZE=40000000
SOAP_ASSEMBLY=0
FLYE_ASSEMBLY=1
END" > config.txt

/opt/biosoft/MaSuRCA-3.4.1/bin/masurca config.txt
./assemble.sh &> masurca.log
# real	10m58.069s
# user	56m25.255s
# sys	0m49.543s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix masurca flye/assembly.fasta > MaSuRCA.fasta


# 7. 使用DBG2OLC对二、三代混合数据进行基因组组装
mkdir /home/train/04.genome_assembling/DBG2OLC
cd /home/train/04.genome_assembling/DBG2OLC
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq ./
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
# 第一步，使用SparseAssembler利用Illumina数据利用De Brujn算法进行contigs组装
for ((i=31; i<=61; i=i+4))
#for ((i=31; i<=121; i=i+6))
do
    echo "mkdir k_$i; cd k_$i; SparseAssembler LD 0 k $i g 15 NodeCovTh 1 EdgeCovTh 0 GS 1000000 f ../illumina.1.fastq f ../illumina.2.fastq"
done > command.SparseAssembler.list
ParaFly -c command.SparseAssembler.list -CPU 8
# real	2m43.545s
# user	17m57.832s
# sys	0m40.716s
for i in `ls k*/Contigs.txt`
do
    echo $i
    genome_statistic.pl $i
done

# 选择N50值最优的kmer为31
mv k_31/* ./
rm k* -rf

# 优化NodeCovTh和EdgeCovTh参数
cp Contigs.txt Contigs.txt.00
SparseAssembler LD 1 k 31 g 15 NodeCovTh 2 EdgeCovTh 1 GS 10000000 f illumina.1.fastq f illumina.2.fastq
cp Contigs.txt Contigs.txt.01
SparseAssembler LD 1 k 31 g 15 NodeCovTh 3 EdgeCovTh 2 GS 10000000 f illumina.1.fastq f illumina.2.fastq
cp Contigs.txt Contigs.txt.02
SparseAssembler LD 1 k 31 g 15 NodeCovTh 4 EdgeCovTh 3 GS 10000000 f illumina.1.fastq f illumina.2.fastq
cp Contigs.txt Contigs.txt.03
# 根据N50值选择最优的Contigs.txt结果文件
genome_statistic.pl Contigs.txt.*
cp Contigs.txt.01 Contigs.txt

# 第二步，使用DBG2OLC找Contigs序列和Pacbio reads的Overlap并进行Layout
DBG2OLC LD 0 k 17 AdaptiveTh 0.001 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
# real	3m3.895s
# user	2m52.817s
# sys	0m10.887s

# 优化AdaptiveTh，KmerCovTh和MinOverlap参数
cp backbone_raw.fasta backbone_raw.fasta.00
DBG2OLC LD 1 k 17 AdaptiveTh 0.005 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.01
DBG2OLC LD 1 k 17 AdaptiveTh 0.01 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.02
DBG2OLC LD 1 k 17 AdaptiveTh 0.015 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.03
DBG2OLC LD 1 k 17 AdaptiveTh 0.02 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.04
# 根据N50值选择最优的AdaptiveTh参数值
genome_statistic.pl backbone_raw.fasta.*
# 进一步优化KmerCovTh和MinOverlap参数
DBG2OLC LD 1 k 17 AdaptiveTh 0.015 KmerCovTh 5 MinOverlap 50 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.05
DBG2OLC LD 1 k 17 AdaptiveTh 0.013 KmerCovTh 4 MinOverlap 40 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.06
DBG2OLC LD 1 k 17 AdaptiveTh 0.016 KmerCovTh 4 MinOverlap 40 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
cp backbone_raw.fasta backbone_raw.fasta.07
# 确定最优的AdaptiveTh，KmerCovTh和MinOverlap参数后，重新使用最优参数运行一次
DBG2OLC LD 1 k 17 AdaptiveTh 0.015 KmerCovTh 5 MinOverlap 50 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta

# 第三步，Call consensus
cp /opt/biosoft/DBG2OLC/utility/*.sh /opt/biosoft/DBG2OLC/utility/*.py ./
chmod 755 *.sh *.py
perl -p -i -e 's/ -nproc 64/ --nproc 8/; s/ -bestn/ --bestn/; s/ -minMatch/ --minMatch/; s/ -out/ --out/; s#\./Sparc#Sparc#;' split_and_run_sparc.sh
cat Contigs.txt subreads.fasta > ctg_pb.fasta
PATH=/opt/sysoft/Python-2.7.18/bin/:/opt/biosoft/miniconda3_for_blasr/bin/:$PATH:`pwd`
./split_and_run_sparc.sh backbone_raw.fasta DBG2OLC_Consensus_info.txt ctg_pb.fasta ./ 2 > cns_log.txt
# real	4m55.583s
# user	28m8.583s
# sys	0m17.502s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix dbg2olc final_assembly.fasta > DBG2OLC.fasta


# 8. 使用 HGAP pacbio数据进行基因组组装
# (1) SMRT Link软件必须要在Chrome浏览器中打开。在Chrome浏览器中输入安装有SMRT Link软件机器的IP地址，并接:9090，例如：localhost:9090，就可以连接到软件的用户登陆界面，输入用户名admin，密码admin则会进入软件。
# (2) 点击Data Management，点击IMPORT并从下拉菜单中点击Sequel Data (XML)，从浏览设置中选择路径/home/train/smrtlink/install/smrtlink-release_7.0.1.66975/bundles/smrtinub/install/smrtinub-release_7.0.1.66768/private/pacbio/canneddata/lambdaTINY/m150404_101626_42267_c100807920800000001823174110291514_s1_p0.subreadset.xml，点击IMPORT，运行一段时间后，导入数据成功。
# (3) 返回到软件主界面，点击SMRT Analysis，点击CREATE NEW ANALYSIS，在Analysis Name栏随便填写字符串“Lambda_HGAP4”，在Data Sets中勾选lambda/007_tiny，点击NEXT，在Analysis Application下拉菜单中选择Assembly(HGAP 4)，在Genome Length栏将基因组大小修改为48000，再点击START。
# (4) 值得注意的是公司给的测序数据文件夹中常常不包含sts.xml、adapters.fasta和scraps bam等文件，而其xml文件中却包含了这些信息，需要将其对应的行（第7行到第15行）删除掉后再运行HGAP4，否则程序运行会失败。
# (5) 程序运行结果在/home/train/biosoft/smrtlink/userdata/jobs_root/目录下的一个数字编号（按运行顺序从000001开始编号）的文件夹中。该文件夹中的的主要结果文件（也可以在网页中下载）：
#./tasks/pbcoretools.tasks.contigset2fasta-0/file.fasta 最终的基因组组装结果。

# 利用Malassezia_sympodialis数据进行基因组组装
# (1) SMRT Link软件必须要在Chrome浏览器中打开。在Chrome浏览器中输入安装有SMRT Link软件机器的IP地址，并接:9090，例如：localhost:9090，就可以连接到软件的用户登陆界面，输入用户名admin，密码admin则会进入软件。
# (2) 点击Data Management，点击IMPORT并从下拉菜单中点击RS II MetaData (XML), 从浏览设置中选择路径/home/train/00.incipient_data/data_for_genome_assembling/m150226_221858_42237/m150226_221858_42237_c100774302550000001823163207301511_s1_p0.metadata.xml，点击IMPORT，运行一段时间后，导入数据成功。
# (3) 返回到软件主界面，点击SMRT Analysis，点击CREATE NEW ANALYSIS，在Analysis Name栏随便填写字符串“Malassezia_sympodialis_bax2bam”，在Data Type中选择RS II Data，在Data Sets中勾选m150226_221858_42237数据，点击NEXT，在Analysis Application下拉菜单中选择“Convert RS to BAM”，再点击START。
# (4) 返回到软件主界面，点击SMRT Analysis，点击CREATE NEW ANALYSIS，在Analysis Name栏随便填写字符串“Malassezia_sympodialis_HGAP4”，在Data Sets中勾选m150226_221858_42237数据，点击NEXT，在Analysis Application下拉菜单中选择“Assembly(HGAP 4)”在Genome Length栏将基因组大小修改为8000000，再点击START。

mkdir /home/train/04.genome_assembling/HGAP4
cd /home/train/04.genome_assembling/HGAP4
mkdir lamda; cd lamda
cp /home/train/smrtlink/userdata/jobs_root/000/000004/tasks/pbcoretools.tasks.contigset2fasta-0/file.fasta lamda.hgap4.fasta
cd ..

mkdir Malassezia_sympodialis
cd Malassezia_sympodialis
genome_seq_clear.pl --seq_prefix hgap /home/train/smrtlink/userdata/jobs_root/000/000011/tasks/pbcoretools.tasks.contigset2fasta-0/file.fasta > HGAP4.fasta
cd ..


# 9. 使用canu对三代数据进行基因组组装
mkdir /home/train/04.genome_assembling/Canu
cd /home/train/04.genome_assembling/Canu
mkdir lamda; cd lamda
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u /home/train/smrtlink/install/smrtlink-release_7.0.1.66975/bundles/smrtinub/install/smrtinub-release_7.0.1.66975/private/pacbio/canneddata/lambdaTINY/*.bam
/opt/biosoft/canu-2.0/Linux-amd64/bin/canu -p out genomeSize=58000 useGrid=false -pacbio-raw subreads.fasta
# real	2m16.951s
# user	8m14.511s
# sys	0m57.682s

cd ..

mkdir Malassezia_sympodialis
cd Malassezia_sympodialis
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
/opt/biosoft/canu-2.0/Linux-amd64/bin/canu -p out genomeSize=8000000 useGrid=false -pacbio-raw subreads.fasta &> canu.log
# real	65m58.093s
# user	379m18.113s
# sys	2m7.641s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix canu out.contigs.fasta > Canu.fasta
cd ..


# 10. 使用FALCON进行基因组装
mkdir /home/train/04.genome_assembling/FALCON
cd /home/train/04.genome_assembling/FALCON
mkdir lamda; cd lamda
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u /home/train/smrtlink/install/smrtlink-release_7.0.1.66975/bundles/smrtinub/install/smrtinub-release_7.0.1.66975/private/pacbio/canneddata/lambdaTINY/*.bam
ls *.fasta > input.fofn
echo '[General]
input_fofn = input.fofn
input_type = raw

pa_DBsplit_option = -x500 -s0.05
ovlp_DBsplit_option = -x500 -s0.05

pa_HPCTANmask_option = -k14 -h180 -w8 -e.70 -T4
pa_HPCREPmask_option = -k14 -h180 -w8 -e.70 -T4
pa_REPmask_code = 1,1000;8,800;16,160
ovlp_HPCTANmask_option = -k20 -h200 -w8 -e.80 -T4

length_cutoff = -1
genome_size = 48000
seed_coverage = 35
pa_daligner_option = -k14 -w6 -h35 -e.70 -l500 -T4
pa_HPCdaligner_option = -v -B4 -M16
falcon_sense_option = --output-multi --min-idt 0.70 --min-cov 4 --max-n-read 500
falcon_sense_greedy = False
falcon_sense_skip_contained = False

length_cutoff_pr = 1000
ovlp_daligner_option = -k20 -w6 -h60 -e.96 -l500 -T4
ovlp_HPCdaligner_option = -v -B4 -M16
overlap_filtering_setting = --max-diff 100 --max-cov 100 --min-cov 2 --bestn 10
fc_ovlp_to_graph_option = --min-len 500 --min-idt 0.96

[job.defaults]
job_type = local
pwatcher_type = blocking
submit = bash -C ${CMD} >| ${STDOUT_FILE} 2>| ${STDERR_FILE}
MB=32768
NPROC=4
njobs=2
[job.step.da]
[job.step.pda]
[job.step.la]
[job.step.pla]
[job.step.cns]
[job.step.asm]' > fc_run.cfg
export PATH=/opt/biosoft/miniconda3_for_pb-assembly/bin/:$PATH
source activate /opt/biosoft/miniconda3_for_pb-assembly
fc_run.py fc_run.cfg &> FALCON.log
# real	5m57.777s
# user	10m0.972s
# sys	3m37.906s
cd ..

mkdir Malassezia_sympodialis
cd Malassezia_sympodialis
ln -s /home/train/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta ./
ls *.fasta > input.fofn
echo '[General]
# input.fofn文件是输入的Pacbio数据信息，每行一个Fasta文件路径
input_fofn = input.fofn
# 输入的Pacbio数据是未进行过修正的数据
input_type = raw

# 将数据进行分块处理
pa_DBsplit_option = -x500 -s8
ovlp_DBsplit_option = -x500 -s8

# 对重复序列进行屏蔽
pa_HPCTANmask_option = -k18 -h180 -w8 -e.70 -T4
pa_HPCREPmask_option = -k18 -h180 -w8 -e.70 -T4
pa_REPmask_code = 1,1000;8,800;16,160
ovlp_HPCTANmask_option = -k24 -h200 -w8 -e.80 -T4

# 选取种子序列
length_cutoff = 500
genome_size = 8000000
seed_coverage = 40
# 对种子序列进行校正
pa_daligner_option = -k14 -w6 -h40 -e.70 -l500
# 若基因组较大较复杂，例如人类基因组，为加快运行速度
#pa_daligner_option = -k18 -w8 -h160 -e.70 -l500
pa_HPCdaligner_option = -v -B4 -M16
falcon_sense_option = --output-multi --min-idt 0.70 --min-cov 4 --min-cov-aln 6 --min-n-read 6 --max-n-read 500
falcon_sense_greedy = False
falcon_sense_skip_contained = False

# 对校正后reads进行重叠分析
length_cutoff_pr = 2000
ovlp_daligner_option = -k20 -w6 -h58 -e.96 -l500
# 若基因组较大较复杂，例如人类基因组，为加快运行速度
#ovlp_daligner_option = -k24 -w8 -h220 -e.92 -l500
ovlp_HPCdaligner_option = -v -B4 -M16
overlap_filtering_setting = --max-diff 100 --max-cov 100 --min-cov 2 --bestn 10
fc_ovlp_to_graph_option = --min-len 2000 --min-idt 0.96

# 计算环境设置
[job.defaults]
job_type = local
pwatcher_type = blocking
submit = bash -C ${CMD} >| ${STDOUT_FILE} 2>| ${STDERR_FILE}
MB=32768
NPROC=4
njobs=2
[job.step.da]
[job.step.pda]
[job.step.la]
[job.step.pla]
[job.step.cns]
[job.step.asm]' > fc_run.cfg
export PATH=/opt/biosoft/miniconda3_for_pb-assembly/bin/:$PATH
source activate /opt/biosoft/miniconda3_for_pb-assembly
fc_run.py fc_run.cfg
# real	72m13.073s
# user	478m9.231s
# sys	21m13.059s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix falcon 2-asm-falcon/p_ctg.fasta > FALCON.fasta
cd ../..


# 11. 使用wtdbg2进行基因组组装
mkdir /home/train/04.genome_assembling/wtdbg2
cd /home/train/04.genome_assembling/wtdbg2

mkdir lamda; cd lamda
/home/train/smrtlink/smrtcmds/bin/bam2fasta -o subreads -u /home/train/smrtlink/install/smrtlink-release_7.0.1.66975/bundles/smrtinub/install/smrtinub-release_7.0.1.66975/private/pacbio/canneddata/lambdaTINY/*.bam
# 进行基因组装
wtdbg2 -i subreads.fasta -fo dbg -t 8 -p 21 -S 4 -s 0.05 -g 48000 -L 200 -l 100 
# 没有生成contig序列
cd ..

mkdir Malassezia_sympodialis
cd Malassezia_sympodialis
ln -s /home/train/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta ./
# 进行基因组装
wtdbg2 -i subreads.fasta -o dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
# real	0m20.546s
# user	2m6.043s
# sys	0m6.543s

# 得到一致性序列
wtpoa-cns -t 8 -j 1000 -i dbg.ctg.lay.gz -fo dbg.raw.fa
# real	1m27.750s
# user	11m12.709s
# sys	0m13.390s

# 利用三代reads的比对结果对基因组序列进行打磨修正
/opt/biosoft/miniconda3_for_pb-assembly/bin/minimap2 -t 8 -a -x map-pb -r 500 dbg.raw.fa subreads.fasta | samtools sort -@ 4 -O BAM -o dbg.bam
# real	0m53.510s
# user	6m4.163s
# sys	0m2.596s
samtools view -F0x900 dbg.bam | wtpoa-cns -t 8 -d dbg.raw.fa -i - -fo dbg.cns.fa
# real	4m4.458s
# user	30m55.281s
# sys	0m33.600s

# 利用二代reads的比对结果对基因组序列进行打磨修正
bwa mem -t 8 dbg.cns.fa ~/03.sequencing_data_quality_control/FindErrors/illumina.1.fastq ~/03.sequencing_data_quality_control/FindErrors/illumina.2.fastq | samtools sort -O SAM | wtpoa-cns -t 8 -x sam-sr -d dbg.cns.fa -i - -fo dbg.srp.fa
# real	0m7.832s
# user	0m50.056s
# sys	0m1.915s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix wtdbg dbg.srp.fa > wtdbg2.fasta
cd ..


# 12. 使用Platanus-allee组装基因组
mkdir /home/train/04.genome_assembling/Platanus_allee
cd /home/train/04.genome_assembling/Platanus_allee
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq .
ln -s /home/train/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta ./

# 使用Illunmina数据进行contigs组装
platanus_allee assemble -t 8 -f illumina.1.fastq illumina.2.fastq 2>assemble.log
# real	1m8.315s
# user	2m4.254s
# sys	0m17.029s

# 结合三代测序数据（支持nanopore和10x数据），或得单倍基因组序列
platanus_allee phase -t 8 \
-c out_contig.fa out_junctionKmer.fa \
-IP1 illumina.1.fastq illumina.2.fastq \
-p subreads.fasta 2> phase.log
# real	4m31.391s
# user	27m12.123s
# sys	0m22.619s

# 对基因组序列进行校正
platanus_allee consensus -t 8 \
-c out_primaryBubble.fa out_nonBubbleHomoCandidate.fa \
-IP1 illumina.1.fastq illumina.2.fastq \
-p subreads.fasta 2> consensus.log
# real	0m57.691s
# user	6m23.557s
# sys	0m3.995s


# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix platanus out_consensusScaffold.fa > Platanus.fasta
cd ..


# 13. 使用quickmerge整合多个基因组组装序列
mkdir -p /home/train/04.genome_assembling/quickmerge
cd /home/train/04.genome_assembling/quickmerge
ln -s ~/04.genome_assembling/DBG2OLC/DBG2OLC.fasta ./
ln -s ~/04.genome_assembling/Canu/Malassezia_sympodialis/Canu.fasta ./

mkdir DBG2OLC_Canu
cd DBG2OLC_Canu
para_nucmer --CPU 8 --nucmer " -p out -l 100" ../DBG2OLC.fasta ../Canu.fasta > out.delta
delta-filter -i 95 -r -q out.delta > out.rq.delta
quickmerge -d out.rq.delta -q ../Canu.fasta -r ../DBG2OLC.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out
cd ..

mkdir Canu_DBG2OLC
cd Canu_DBG2OLC
para_nucmer --CPU 8 --nucmer " -p out -l 100" ../Canu.fasta ../DBG2OLC.fasta > out.delta
delta-filter -i 95 -r -q out.delta > out.rq.delta
quickmerge -d out.rq.delta -q ../DBG2OLC.fasta -r ../Canu.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out
cd ..

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix quickmerge Canu_DBG2OLC/merged_out.fasta > quickmerge.fata
cd ..


# 14. 使用FinisherSC更新基因组序列
mkdir /home/train/04.genome_assembling/FinisherSC
cd /home/train/04.genome_assembling/FinisherSC
ln -s ~/04.genome_assembling/quickmerge/quickmerge.fata contigs.fasta
ln -s /home/train/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta raw_reads.fasta

python /opt/biosoft/kakitone-finishingTool-a1f2608/finisherSC.py -par 8 -l True -o contigs.fasta_improved3.fasta ./ /opt/biosoft/mummer-4.0.0beta2/bin/
# real	7m57.455s
# user	55m17.056s
# sys	1m0.953s

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix finisherSC improved3.fasta > FinisherSC.fasta
cd ..


# 15. 使用ARROW算法利用PacBio数据对基因组进行修正
mkdir /home/train/04.genome_assembling/ARROW
cd /home/train/04.genome_assembling/ARROW
ln -s ../FinisherSC/FinisherSC.fasta ./
ls /home/train/00.incipient_data/data_for_genome_assembling/*.subreads.bam > pacbio_reads.fofn

# 使用blasr将pacbio reads比对到基因组序列上
PATH=/home/train/smrtlink/smrtcmds/bin:$PATH
sawriter FinisherSC.fasta.sa FinisherSC.fasta
samtools faidx FinisherSC.fasta
blasr pacbio_reads.fofn FinisherSC.fasta --sa FinisherSC.fasta.sa --bam --out for_arrow00.bam --minPctAccuracy 70 --nproc 8
# real	15m5.958s
# user	119m1.618s
# sys	0m7.939s

# 输入基因组序列和排序后的SAM/BAM文件结果，使用ARROW进行修正
samtools sort -@ 4 -o for_arrow00.sorted.bam -O BAM for_arrow00.bam
pbindex for_arrow00.sorted.bam
arrow --referenceFilename FinisherSC.fasta -o consensus00.fasta -o consensus00.gff -o consensus00.vcf -j 8 for_arrow00.sorted.bam
# real	53m31.897s
# user	424m25.220s
# sys	0m24.475s
# 统计修正数据量
arrow_stats.pl consensus00.vcf > consensus00.vcf.stats

# 进行第二轮修正
sawriter consensus00.fasta.sa consensus00.fasta
samtools faidx consensus00.fasta
blasr pacbio_reads.fofn consensus00.fasta --sa consensus00.fasta.sa --bam --out for_arrow01.bam --minPctAccuracy 70 --nproc 8
samtools sort -@ 4 -o for_arrow01.sorted.bam -O BAM for_arrow01.bam
pbindex for_arrow01.sorted.bam
arrow --referenceFilename consensus00.fasta -o consensus01.fasta -o consensus01.gff -o consensus01.vcf -j 8 for_arrow01.sorted.bam
arrow_stats.pl consensus01.vcf > consensus01.vcf.stats

# 进行第三轮修正
sawriter consensus01.fasta.sa consensus01.fasta
samtools faidx consensus01.fasta
blasr pacbio_reads.fofn consensus01.fasta --sa consensus01.fasta.sa --bam --out for_arrow02.bam --minPctAccuracy 70 --nproc 8
samtools sort -@ 4 -o for_arrow02.sorted.bam -O BAM for_arrow02.bam
pbindex for_arrow02.sorted.bam
arrow --referenceFilename consensus01.fasta -o consensus02.fasta -o consensus02.gff -o consensus02.vcf -j 8 for_arrow02.sorted.bam
arrow_stats.pl consensus02.vcf > consensus02.vcf.stats

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix arrow consensus02.fasta > ARROW.fasta
cd ..


# 16. 使用Pilon算法利用Illumina数据对基因组进行修正
mkdir /home/train/04.genome_assembling/Pilon
cd /home/train/04.genome_assembling/Pilon
perl -e 'while (<>) { if (m/^>/) { print; } else { tr/atcg/ATCG/; print; } }' ../ARROW/ARROW.fasta > genome00.fasta
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq .

# 将Illumina数据比对到基因组序列
bowtie2-build --threads 8 genome00.fasta genome00
bowtie2 -x genome00 -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 -I 0 -X 1000 --fr -S bowtie2.00.sam 2> bowtie2.00.log
# real	3m18.445s
# user	25m37.612s
# sys	0m13.719s
samtools sort -@ 8 -o bowtie2.00.bam -O BAM bowtie2.00.sam
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=bowtie2.00.bam O=bowtie2_RD.00.bam M=bowtie2_RD.00.metrics
samtools index bowtie2_RD.00.bam
samtools faidx genome00.fasta
java -Xmx100G -jar /opt/biosoft/pilon/pilon-1.23.jar --genome genome00.fasta --frags bowtie2_RD.00.bam --fix all --changes --output pilon01
# real	2m19.524s
# user	2m44.993s
# sys	0m4.779s
pilon_stats.pl --arrow-genome ../ARROW/ARROW.fasta pilon01.changes > pilon01.changes.stats

# 进行第二轮修正
ln -s pilon01.fasta genome01.fasta
bowtie2-build --threads 8 genome01.fasta genome01
bowtie2 -x genome01 -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 -I 0 -X 1000 --fr -S bowtie2.01.sam 2> bowtie2.01.log
samtools sort -@ 8 -o bowtie2.01.bam -O BAM bowtie2.01.sam
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=bowtie2.01.bam O=bowtie2_RD.01.bam M=bowtie2_RD.01.metrics
samtools index bowtie2_RD.01.bam
samtools faidx genome01.fasta
java -Xmx101G -jar /opt/biosoft/pilon/pilon-1.23.jar --genome genome01.fasta --frags bowtie2_RD.01.bam --fix all --changes --output pilon02
pilon_stats.pl pilon02.changes > pilon02.changes.stats

# 进行第三轮修正
ln -s pilon02.fasta genome02.fasta
bowtie2-build --threads 8 genome02.fasta genome02
bowtie2 -x genome02 -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 -I 0 -X 1000 --fr -S bowtie2.02.sam 2> bowtie2.02.log
samtools sort -@ 8 -o bowtie2.02.bam -O BAM bowtie2.02.sam
java -jar /opt/biosoft/picard-tools/picard.jar MarkDuplicates I=bowtie2.02.bam O=bowtie2_RD.02.bam M=bowtie2_RD.02.metrics
samtools index bowtie2_RD.02.bam
samtools faidx genome02.fasta
java -Xmx102G -jar /opt/biosoft/pilon/pilon-1.23.jar --genome genome02.fasta --frags bowtie2_RD.02.bam --fix all --changes --output pilon03
pilon_stats.pl pilon03.changes > pilon03.changes.stats

# 对genome assembly进行格式化
genome_seq_clear.pl --seq_prefix pilon pilon03.fasta > Pilon.fasta
cd ..


# 17. 对基因组序列进行过滤
# 去除重复序列
mkdir /home/train/04.genome_assembling/rmFPsequences
cd /home/train/04.genome_assembling/rmFPsequences
ln -s ~/04.genome_assembling/Pilon/Pilon.fasta ./
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq .
bowtie2-build --threads 8 Pilon.fasta genome
bowtie2 -x genome -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 -I 0 -X 1000 --fr -S bowtie2.sam 2> bowtie2.00.log
samtools sort -@ 8 -o bowtie2.bam -O BAM bowtie2.sam
samtools index bowtie2.bam
samtools depth bowtie2.bam > depth.txt
perl -e 'while (<>) { @_ = split /\t/; push @dep, $_[2] if $_[2] >= 3; } @dep = sort {$a <=> $b} @dep; print "$dep[@dep/2]\n";' depth.txt
# 平均测序深度为32x
perl -e 'while (<>) {chomp; @_ = split /\t/; push @{$dep{$_[0]}}, $_[2]; } foreach (sort keys %dep) { my @dep = sort {$a <=> $b} @{$dep{$_}};  print "$_\t$dep[@dep/2]\t$dep[-1]\n"; }' depth.txt > depth.stats
# pilon10 序列深度异常大。

genome_rmDuplicates.pl --length 1000000 --CPU 8 Pilon.fasta > genome.RD.fasta
# pilon11 整条序列和其他序列重复；且其平均测序深度为17，约为全基因组平均测序深度的一半，说明该序列在基因组上不是重复序列。

# 检测线粒体序列
mkdir homolog_genewise
cd homolog_genewise
homolog_genewise --cpu 8 --max_gene_length 2000 ~/00.incipient_data/data_for_genome_assembling/Mit_proteins_Lentinula_edodes.fasta ../genome.RD.fasta 
# real	0m2.731s
# user	0m5.059s
# sys	0m0.631s
homolog_genewiseGFF2GFF3 --genome ../genome.RD.fasta genewise.gff > genewise.gff3 2> gene_id.with_stop_codon.list
# pilon10 序列属于线粒体序列，首尾同时存在atp9基因，表明有重叠。
cd ..

# 线粒体序列连环
mkdir mit_genome
cd mit_genome
samtools faidx ../Pilon.fasta pilon10 > out.fasta
makeblastdb -in out.fasta -dbtype nucl -title out -parse_seqids -out out
blastn -query out.fasta -db out -outfmt 7 > blast.out
# 1-4292 => 38516-42868
# 3863-9792 => 41784-35855
# 1-3207 => 7131-3863
# atp9: 8411-8632 37015-37236
# 初步得到环状线粒体DNA
perl -e '<>; while (<>) { chomp; $seq .= $_; } $mit = substr($seq, 0, 38515); print ">mit\n$mit\n";' out.fasta > ../Malassezia_sympodialis.genome_MIT.fasta
cd ..

# 提取核基因组序列
perl -e 'while (<>) { last if m/^>pilon10/; print; }' Pilon.fasta > rmFPsequences.fasta

# 对genome assembly进行格式化，得到最终的基因组序列
genome_seq_clear.pl --seq_prefix MS01Contig rmFPsequences.fasta > Malassezia_sympodialis.genome_V01.fasta
cd ..


# 18. 使用 GapFiller 进行基因组补洞
mkdir -p /home/train/04.genome_assembling/GapFiller
cd /home/train/04.genome_assembling/GapFiller
ln -s ../ALLPATHS-LG/allpathslg.fasta genome.fa
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.1.corrected.fastq jumping.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.2.corrected.fastq jumping.2.fastq
echo "Lib1 bwa fragment.1.fastq fragment.2.fastq 177 0.43 FR
Lib2 bwa jumping.1.fastq jumping.2.fastq 3014 0.67 RF" > library.txt
GapFiller.pl -l library.txt -s genome.fa -T 4
# real	4m35.022s
# user	8m4.712s
# sys	0m7.762s


# 19. 使用 GapCloser 进行基因组补洞
mkdir -p /home/train/04.genome_assembling/GapCloser
cd /home/train/04.genome_assembling/GapCloser
cp ../SOAPdenovo/config.txt ./
ln -s ../ALLPATHS-LG/allpathslg.fasta genome.fa
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.1.corrected.fastq jumping.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.2.corrected.fastq jumping.2.fastq
GapCloser -a genome.fa -b config.txt -o gapcloser.fa -l 120 -t 4
# real	1m14.855s
# user	1m13.053s
# sys	0m0.957s


# 20. 使用 SSPACE 进行基因组scaffold连接
mkdir -p /home/train/04.genome_assembling/SSPACE
cd /home/train/04.genome_assembling/SSPACE
genome_seq_clear.pl --seq_prefix contig ../SOAPdenovo/out_K51/E_coli.contig > genome.fasta
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.?.fastq .
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.?.fastq .

# (1) 先将fastq文件进行到Contig序列
bowtie2-build genome.fasta genome
bowtie2 -x genome -p 4 -1 fragment.1.fastq -2 fragment.2.fastq --score-min L,-0.3,-0.3 -S fragment.sam 2> fragment.bowtie2.log
# real	0m53.127s
# user	3m21.309s
# sys	0m8.373s
bowtie2 -x genome -p 4 -1 jumping.1.fastq -2 jumping.2.fastq --score-min L,-0.3,-0.3 -S  jumping.sam 2> jumping.bowtie2.log
# real	0m9.078s
# user	0m35.985s
# sys	0m0.169s

# (2) 提取连接到2条不同的contigs序列上的reads对信息
~/bin/sspace_sam2tab.pl fragment.sam fragment.tab > fragment.unpaired_match.readsID.list 2> fragment.sspace_sam2tab.log
~/bin/sspace_sam2tab.pl jumping.sam jumping.tab > jumping.unpaired_match.readsID.list 2> jumping.sspace_sam2tab.log

# (3) 对TAB文件进行去除PCR重复处理
perl -e 'while (<>) { chomp; @_ = split /\t/; @aa = ("$_[0]\t$_[1]\t$_[2]", $two = "$_[3]\t$_[4]\t$_[5]"); @aa = sort {$a cmp $b} @aa; $aa = join "\t", @aa; $hash{$aa} = 1; } foreach (keys %hash) { print "$_\n"; }' fragment.tab > fragment.rmDup.tab
perl -e 'while (<>) { chomp; @_ = split /\t/; @aa = ("$_[0]\t$_[1]\t$_[2]", $two = "$_[3]\t$_[4]\t$_[5]"); @aa = sort {$a cmp $b} @aa; $aa = join "\t", @aa; $hash{$aa} = 1; } foreach (keys %hash) { print "$_\n"; }' jumping.tab > jumping.rmDup.tab

# (4) 最后进行SSPACE分析
echo -e "LIB1\tTAB\tfragment.rmDup.tab\t177\t0.43\tFR
LIB2\tTAB\tjumping.rmDup.tab\t3014\t0.67\tRF" > library3.txt
SSPACE_Standard_v3.0.pl -l library3.txt -s genome.fasta -x 0 -T 4 -b SSPACE_OUT
# eal	0m5.970s
# user	0m5.900s
# sys	0m0.070s
