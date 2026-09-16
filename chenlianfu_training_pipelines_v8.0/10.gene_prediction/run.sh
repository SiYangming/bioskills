## 1. 使用 PASA 利用转录本序列进行基因预测
mkdir -p /home/train/10.gene_prediction/pasa
cd /home/train/10.gene_prediction/pasa

ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 将 RNA-Seq de novo 组装序列和 genome-guided 组装序列合并到一个文件中
cat ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Trinity*fasta > transcripts.fasta
perl -e 'while (<>) { print "$1\n" if />(\S+)/ }' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Trinity.fasta > tdn.accs

# 对 transcripts 序列进行 end-trimming (vector, adaptor, primer, polyA/T tails)
seqclean transcripts.fasta -v /opt/biosoft/PASApipeline.v2.4.1/UniVec/UniVec
# real	2m32.771s
# user	2m32.096s
# sys	0m1.013s

# 生成比对配置文件
cp /opt/biosoft/PASApipeline.v2.4.1/pasa_conf/pasa.alignAssembly.Template.txt alignAssembly.config
DATE=`date +%Y%m%H%M%S`
User=`whoami`
echo "perl -p -i -e 's/DATABASE=.*/DATABASE=pasa_${DATE}_$User/' alignAssembly.config" | sh

# 生成 mysql 数据库及表
/opt/biosoft/PASApipeline.v2.4.1/scripts/create_mysql_cdnaassembly_db.dbi -r -c alignAssembly.config -S /opt/biosoft/PASApipeline.v2.4.1/schema/cdna_alignment_mysqlschema

# 运行 PASA 主程序，将 transcripts 序列比对到基因组上，得到去冗余的转录子序列、转录子和基因组的比对结果和可变剪接信息
/opt/biosoft/PASApipeline.v2.4.1/Launch_PASA_pipeline.pl -c alignAssembly.config -R -g genome.fasta -t transcripts.fasta.clean -T -u transcripts.fasta --ALIGNERS gmap,blat --CPU 8 --stringent_alignment_overlap 30.0 --TDN tdn.accs --MAX_INTRON_LENGTH 20000 --TRANSDECODER &> pasa.log
# real	10m21.260s
# user	14m48.870s
# sys	2m14.255s
# 链特异性测序需要加入参数 --transcribed_is_aligned_orient
# 真菌等小基因组，由于基因比较稠密，需要加入参数 --stringent_alignment_overlap

# 网页中访问PASA结果
/opt/biosoft/PASApipeline.v2.4.1/run_PasaWeb.pl 9988 &
firefox localhost:9988/index.html
# 然后，输入pasa的数据库名，例如pasa_201907_train，点击Launch PasaWeb访问结果。

# 构建综合转录组数据库
#perl -p -i -e 's#TR\\d\+\\\|#TRINITY_DN\\d\+_#' /opt/biosoft/PASApipeline.v2.4.1/scripts/build_comprehensive_transcriptome.dbi
/opt/biosoft/PASApipeline.v2.4.1/scripts/build_comprehensive_transcriptome.dbi -c alignAssembly.config -t transcripts.fasta.clean 
#real	0m19.906s
# user	0m8.746s
# sys	0m0.559s

# ORF预测和基因预测
DBName=`ls *.assemblies.fasta | perl -pe 's/.assemblies.fasta\s*//'`
/opt/biosoft/PASApipeline.v2.4.1/scripts/pasa_asmbls_to_training_set.dbi --pasa_transcripts_fasta $DBName.assemblies.fasta --pasa_transcripts_gff3 $DBName.pasa_assemblies.gff3
# real	2m50.461s
# user	2m49.159s
# sys	0m1.174s
ln -s $DBName.assemblies.fasta.transdecoder.genome.gff3 pasa.gff3

# 提取完好的基因模型
geneModels2AugusutsTrainingInput --cpu 8 --min_evalue 1e-9 --min_identity 0.7 --min_coverage_ratio 0.7 --min_cds_num 1 --min_cds_length 450 --min_cds_exon_ratio 0.4 --keep_ratio_for_excluding_too_long_gene 0.99 pasa.gff3 genome.fasta
# out.filter1.gff3是去冗余后的基因模型；out.filter2.gff3是完整的基因模型。这些基因模型可以用于其它 ab initio 基因预测软件的 HMM trainning 。
cd ..


## 2. 使用 genewise 利用同源蛋白进行基因预测
mkdir /home/train/10.gene_prediction/homolog
cd /home/train/10.gene_prediction/homolog
ln -s ~/05.genome_feature_analysis/repeat_analysis/genome.hardmaskN.fasta genome.fasta
gzip -dc /home/train/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta

homolog_genewise --cpu 8 --coverage_ratio 0.4 --evalue 1e-9 --max_gene_length 2000 homolog.fasta genome.fasta
# real	11m33.577s
# user	85m50.057s
# sys	2m21.242s
homolog_genewiseGFF2GFF3 --genome genome.fasta --min_score 15 --gene_prefix genewise genewise.gff > genewise.gff3 2> gene_id.with_stop_codon.list
cd ..


## 3. 使用 AUGUSTUS 进行基因预测

# 3.1 AUGUSTUS Training
mkdir -p /home/train/10.gene_prediction/augustus/training
cd /home/train/10.gene_prediction/augustus/training
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 对pasa.gff3中添加基因的完整性信息
GFF3Clear --gene_prefix pasa --genome genome.fasta ../../pasa/pasa.gff3 > pasa.gff3
# 整合PASA和genewise的基因预测结果 (需要转录本预测结果GFF3文件第9列含有Integrity信息)
paraCombineGeneModels /dev/null pasa.gff3 ../../homolog/genewise.gff3 /dev/null

# 提取完好的基因模型
geneModels2AugusutsTrainingInput --cpu 8 --min_evalue 1e-9 --min_identity 0.7 --min_coverage_ratio 0.7 --min_cds_num 1 --min_cds_length 450 --min_cds_exon_ratio 0.4 --keep_ratio_for_excluding_too_long_gene 0.99 --out_prefix ati combine.1.gff3 genome.fasta
# real	0m44.092s
# user	3m35.421s
# sys	0m30.430s
# ati.filter1.gff3是去冗余后的基因模型；ati.filter2.gff3是完整的基因模型。这些基因模型可以用于其它 ab initio 基因预测软件的 HMM trainning 。

# 利用已有的准确的基因模型进行HMM Training，使用BGM2AT程序自动化运行
#BGM2AT --flanking_length 100 --CPU 8 --optimize_augustus_rounds 5 --onlytrain_GFF3 ati.filter1.gff3 ati.filter2.gff3 genome.fasta malassezia_sympodialis
# real	60m24.233s
# user	408m17.384s
# sys	5m23.935s

# 手动分步运行
# 将 GFF3 文件转换为 GeneBank 格式
gff2gbSmallDNA.pl ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/ati.filter2.gff3 genome.fasta 100 genes.raw.gb
# 去除错误的基因
new_species.pl --species=for_bad_genes_removing
etraining --species=for_bad_genes_removing --stopCodonExcludedFromCDS=false genes.raw.gb 2> train.err
cat train.err | perl -pe 's/.*in sequence (\S+): .*/$1/' > badgenes.lst
filterGenes.pl badgenes.lst genes.raw.gb > genes.gb
#cp ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/genes.gb ./
randomSplit.pl genes.gb 200
new_species.pl --species=malassezia_sympodialis
# 第一次training
etraining --species=malassezia_sympodialis genes.gb.train > train.out
perl -e 'open IN, "train.out"; while (<IN>) { $tag = $1 if m/tag:.*\((.*)\)/; $taa = $1 if m/taa:.*\((.*)\)/; $tga = $1 if m/tga:.*\((.*)\)/; } while (<>) { s#/Constant/amberprob.*#/Constant/amberprob                   $tag#; s#/Constant/ochreprob.*#/Constant/ochreprob                   $taa#; s#/Constant/opalprob.*#/Constant/opalprob                    $tga#; print }' /opt/biosoft/augustus-3.3.3/config/species/malassezia_sympodialis/malassezia_sympodialis_parameters.cfg > 11
mv 11 /opt/biosoft/augustus-3.3.3/config/species/malassezia_sympodialis/malassezia_sympodialis_parameters.cfg
augustus --species=malassezia_sympodialis genes.gb.test | tee firsttest.out

# 使用optimize_augustus.pl进行循环training找最优参数
# genes.gb.train中包含514个基因模型。对其再次进行分割，取其中 400 个基因模型用于对HMM模型参数进行优化时的准确性检测，剩下114个仅加入到training的过程中。本次优化过程如下：对某一个参数进行优化的时候，将400个基因模型随机分成8份，每份的基因模型数目为50个；取其中7份的基因模型和135个基因模型用于etraining，再使用剩下的1份基因模型进行准确性检测；总共有8份数据，这8份数据并行化运行，得到8个准确性检测值，取其均值用于参数的优化。
# 因此，为了能更准确快速的进行HMM参数文件优化，则需要注意两点：（1）根据计算资源确定并行数。当然，并行数越大，则准确性检测的值更准确。（2）用于准确性检测的基因模型数目。该数目除以并行数的值不要大于100，否则，每次准确性检测耗时会很长。当然，用于准确性检测的基因模型数目除以并行数的值越大，则准确性检测的值更准确。这个需要在准确性和耗时中权衡该值，推荐50-100。
# 若用于training的基因模型数目很多，比如有4500个；同时计算资源达80线程。则可以设置：先将4500个基因模型分成200和4300个，其中200个用于参数文件的准确性检测；然后再将4300个分成300和4000个，在优化参数过程中，设置并行化数80，这4000个基因模型用于training和准确性检测（并行化的每个线程中随机从4000个基因中取50个用于准确性检测），而这300个仅用于training。
randomSplit.pl genes.gb.train 134
ln -s genes.gb.train.test training.gb.onlytrain
optimize_augustus.pl --species=malassezia_sympodialis --rounds=5 --cpus=8 --kfold=8 --onlytrain=training.gb.onlytrain genes.gb.train.train > optimize.out 2> /dev/null
# real	38m26.834s
# user	2.4.14.136s
# sys	2m43.755s
# accuracy value = (3*nucleotide_sensitivity + 2*nucleotide_specificity + 4*exon_sensitivity + 3*exon_specificity + 2*gene_sensitivity + 1*gene_specificity)/15
# Commonly observed values at this position range from 40 to 60 percent. If you obtain a very low value, this gives a strong indication that the obtained parameter set is not very useful for predicting genes accurately.
# 第二次training
etraining --species=malassezia_sympodialis genes.gb.train
augustus --species=malassezia_sympodialis genes.gb.test | tee secondtest.out
cd ..

# 使用 RNA-seq 数据制作 hints 文件
mkdir -p /home/train/10.gene_prediction/augustus/making_hints
cd /home/train/10.gene_prediction/augustus/making_hints
samtools merge -@ 8 rnaseq.bam ~/06.reads_aligment/hisat2/*.sam
samtools sort -@ 8 -O bam -o rnaseq.sort.bam rnaseq.bam
bam2hints --intronsonly --in=rnaseq.sort.bam --out=hints.gff
# 推荐使用masked重复序列后的基因组序列进行转录组测序数据的比对，得到hints信息。

# 运行 Augustus 进行基因预测
cd /home/train/10.gene_prediction/augustus
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
tar zxf ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/augustus_trainingOut_malassezia_sympodialis.tar.gz -C /opt/biosoft/augustus-3.3.3/config/species

#augustus --species=malassezia_sympodialis --extrinsicCfgFile=/opt/biosoft/augustus/config/extrinsic/extrinsic.M.RM.E.W.cfg --alternatives-from-evidence=true --allow_hinted_splicesites=atac --hintsfile=making_hints/hints.gff --gff3=on genome.fasta > aug.gff3
augustus_para_with_hints.pl genome.fasta making_hints/hints.gff malassezia_sympodialis 8 > augustus.out
# real	1m40.549s
# user	8m53.710s
# sys	0m1.890s

join_aug_pred.pl <augustus.out > augustus.gff3
perl -p -i -e 's/\ttranscript\t/\tmRNA\t/' augustus.gff3
gff3_clear.pl --prefix aug augustus.gff3 > aa;
perl -e 'while (<>) { if (m/\tCDS\t/) { print; s/CDS/exon/g; print; } else { print } }' aa > augustus.gff3
rm aa


## 使用 GeneMark-ES/ET 进行基因预测
mkdir -p /home/train/10.gene_prediction/genemark_es_et/es
cd /home/train/10.gene_prediction/genemark_es_et/es
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
gmes_petap.pl --sequence genome.fasta --ES --fungus --cores 8
# real	2m40.876s
# user	11m22.678s
# sys	0m4.806s
/opt/biosoft/PASApipeline.v2.4.1/misc_utilities/gtf_to_gff3_format.pl genemark.gtf genome.fasta > genemark.gff3
gff3_clear.pl --prefix gmes genemark.gff3 > aa; mv aa ../genemarkES.gff3

mkdir -p /home/train/10.gene_prediction/genemark_es_et/et
cd /home/train/10.gene_prediction/genemark_es_et/et
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
#bet_to_gff.pl --bed ~/06.reads_aligment/tophat/A1/junctions.bed --gff introns.gff --label tophat2 --seq genome.fasta
hints2genemarkETintron.pl genome.fasta ../../augustus/making_hints/hints.gff > genemartET.intron.gff
gmes_petap.pl --sequence genome.fasta --ET genemartET.intron.gff --fungus --et_score 10 --cores 8
# real	2m13.495s
# user	10m30.754s
# sys	0m4.878s
/opt/biosoft/PASApipeline.v2.4.1/misc_utilities/gtf_to_gff3_format.pl genemark.gtf genome.fasta > genemark.gff3
gff3_clear.pl --prefix gmet genemark.gff3 > aa; mv aa ../genemarkET.gff3
cd ..


## 使用SNAP进行基因预测
mkdir -p /home/train/10.gene_prediction/snap
cd /home/train/10.gene_prediction/snap
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
export PERL5LIB=$PERL5LIB:/opt/biosoft/EVM_r2012-06-25/PerlLib/
/opt/biosoft/EVM_r2012-06-25/OtherGeneFinderTrainingGuide/SNAP/gff3_to_SNAP_train.pl ../augustus/training/ati.filter2.gff3 genome.fasta 

fathom genome.ann genome.dna -gene-stats &> gene-stats.log
fathom genome.ann genome.dna -validate &> validate.log
perl -ne 'print "$1\n" if /.*:\s+(\S+)\s+OK/' validate.log > zff2keep.txt
perl -e 'open IN, "zff2keep.txt"; while (<IN>) { chomp; $keep{$_} = 1; } while (<>) { if (m/>/) { print; } else { chomp; @_ = split /\t/; print "$_\n" if exists $keep{$_[-1]}; } }' genome.ann > out;
mv out genome.ann
fathom genome.ann genome.dna -categorize 200
rm alt.* err.* olp.* wrn.*
fathom genome.ann genome.dna -export 200 -plus
mkdir params; cd params
forge ../export.ann ../export.dna
cd ..
hmm-assembler.pl species params > species.hmm
snap species.hmm genome.fasta > snap_out.zff
# real	0m32.237s
# user	0m31.768s
# sys	0m0.461s

/opt/biosoft/EVM_r2012-06-25/OtherGeneFinderTrainingGuide/SNAP/SNAP_output_to_gff3.pl snap_out.zff genome.fasta > snap_out.gff3
gff3_clear.pl --prefix snap snap_out.gff3 > aa; mv aa snap.gff3
cd ..


## 使用 MAKER 进行基因预测
mkdir -p /home/train/10.gene_prediction/maker
cd /home/train/10.gene_prediction/maker
# 准备输入文件
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Trinity.fasta ./
gzip -dc /home/train/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta
ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/RepeatModeler_database.consensi.fa consensi.fa
ln -s /home/train/10.gene_prediction/genemark_es_et/es/output/gmhmm.mod ./
ln -s /home/train/10.gene_prediction/snap/species.hmm ./

# 准备配置文件
PATH=/opt/biosoft/tRNAscan-SE-1.3.1/bin/:$PATH
export PERL5LIB=$PERL5LIB:/opt/biosoft/tRNAscan-SE-1.3.1/bin/
maker -CTL
perl -p -i -e 's/^genome=.*/genome=genome.fasta/; s/^est=.*/est=Trinity.fasta/; s/^protein=.*/protein=homolog.fasta/; s/^model_org=.*/model_org=fungi/; s/^rmlib=.*/rmlib=consensi.fa/; s/^augustus_species=.*/augustus_species=malassezia_sympodialis/; s/^snaphmm=.*/snaphmm=species.hmm/; s/^gmhmm=.*/gmhmm=gmhmm.mod/; s/^est2genome=.*/est2genome=1/; s/^protein2genome=.*/protein2genome=1/; s/^trna=.*/trna=1/; s/^correct_est_fusion=.*/correct_est_fusion=1/; s/^keep_preds=.*/keep_preds=1/;' maker_opts.ctl

# 并行运行maker 使用mpich2进行并性化，maker依赖旧版本的tRNAscan-SE
/usr/lib64/mpich/bin/mpiexec -n 8 maker -fix_nucleotides &> maker.log
# real	41m28.003s
# user	105m16.438s
# sys	7m43.114s
cd genome.maker.output
gff3_merge -d genome_master_datastore_index.log 
grep -P "\tmaker\t" genome.all.gff > genome.maker.gff3
gff3_clear.pl --prefix maker genome.maker.gff3 > ../maker.gff3
cd ..


# 使用 BRAKER 进行基因预测
mkdir /home/train/10.gene_prediction/braker
cd /home/train/10.gene_prediction/braker
ln -s ~/05.genome_feature_analysis/repeat_analysis/genome.softmask.fasta genome.fasta
gzip -dc /home/train/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta
ln -s ../augustus/making_hints/rnaseq.sort.bam

export AUGUSTUS_CONFIG_PATH=/opt/biosoft/augustus-3.3.3/config/
export AUGUSTUS_BIN_PATH=/opt/biosoft/augustus-3.3.3/bin/
export AUGUSTUS_SCRIPTS_PATH=/opt/biosoft/augustus-3.3.3/scripts/
export BAMTOOLS_PATH=/usr/local/bin/
export SAMTOOLS_PATH=/opt/biosoft/samtools-1.10/bin/
export ALIGNMENT_TOOL_PATH=/opt/biosoft/gth-1.7.3-Linux_x86_64-64bit/bin/
export BLAST_PATH=/opt/biosoft/ncbi-rmblast-2.10.0+/bin/
export GENEMARK_PATH=/opt/biosoft/gmes_linux_64
export DIAMOND_PATH=/opt/biosoft/diamond
export PYTHON3_PATH=/opt/sysoft/Python-3.8.4/bin
export CDBTOOLS_PATH=/opt/biosoft/PASApipeline.v2.4.1/bin
braker.pl --species=malassezia_sympodialis_braker --genome=genome.fasta --bam=rnaseq.sort.bam --prot_seq=homolog.fasta --cores 8 --etpmode --softmasking
# real	10m21.224s
# user	41m42.403s
# sys	0m54.929s

perl -e 'while (<>) { if (m/\tCDS\t/) { print; s/\tCDS\t/\texon\t/; print; } elsif (m/\ttranscript\t/) { next; } elsif (m/^#/) { next; } elsif (m/\tgene\t/) { next; } elsif (m/\tintron\t/) { next; } else { print; } }' braker/braker.gtf > braker.gtf
#/opt/biosoft/PASApipeline.v2.4.1/misc_utilities/gtf_to_gff3_format.pl braker.gff3 genome.fasta > braker.gff3 
gtf2gff3.pl braker.gtf > braker.gff3
gff3_clear.pl --prefix braker braker.gff3 > aa; mv aa braker.gff3


## 使用 EVM 对基因预测结果进行整合
mkdir -p /home/train/10.gene_prediction/evm
cd /home/train/10.gene_prediction/evm
# 准备输入文件
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
bestGeneModels.pl ../augustus/augustus.gff3 | perl -pe 's/^\s*$//' > gene_predictions.gff3 
#ln -s ../genemark_es_et/et/genemark.gff3 genemark-et.gff3
#ln -s ../snap/snap.gff3 ./
#ln -s ../maker/genome.maker.gff3 maker.gff3
#cat augustus.gff3 genemark-et.gff3 snap.gff3 maker.gff3 | perl -pe 's/^#.*//; s/^\s*$//' > gene_predictions.gff3
cp ../pasa/pasa*.pasa_assemblies.gff3 transcript_alignments.gff3
perl -p -i -e 's/\t\S+/\tpasa_transcript_alignments/' transcript_alignments.gff3
perl -ne 'if (s/\tcds\t/\tprotein_match\t/) { @_ = split /\t/; my ($start, $end) = ($_[3], $_[4]); ($start, $end) = ($_[4], $_[3]) if $_[4] < $_[3]; ($_[3], $_[4]) = ($start, $end); print join "\t", @_; }' ../homolog/genewise.gff | sort -k 1.1,1 -k 4.1n,4n > protein_alignments.gff3
perl -pe 's/.*Low_complexity.*//; s/.*Simple_repeat.*//; s/^#.*//; s/^\s*$//;' ~/05.genome_feature_analysis/repeat_analysis/genome.repeat.gff3 > genome.repeat.gff3
echo -e "ABINITIO_PREDICTION\tAUGUSTUS\t1
PROTEIN\tGeneWise\t5
TRANSCRIPT\tpasa_transcript_alignments\t10" > weights.txt
# 将输入数据分隔成小份数据
/opt/biosoft/EVidenceModeler-1.1.1/EvmUtils/partition_EVM_inputs.pl --genome genome.fasta --gene_predictions gene_predictions.gff3 --protein_alignments protein_alignments.gff3 --transcript_alignments transcript_alignments.gff3 --repeats genome.repeat.gff3 --segmentSize 500000 --overlapSize 10000 --partition_listing partitions_list.out
# 对小份数据进行EVM并行运算
/opt/biosoft/EVidenceModeler-1.1.1/EvmUtils/write_EVM_commands.pl --genome genome.fasta --gene_predictions gene_predictions.gff3 --protein_alignments protein_alignments.gff3 --transcript_alignments transcript_alignments.gff3 --repeats genome.repeat.gff3  --weights `pwd`/weights.txt --partitions partitions_list.out --output_file_name evm.out > commands.write_EVM_commands.list
ParaFly -c commands.write_EVM_commands.list -CPU 8
# real	30m36.502s
# user	206m40.298s
# sys	0m1.567s
# 合并并行运算的结果并转换成GFF3格式
/opt/biosoft/EVidenceModeler-1.1.1/EvmUtils/recombine_EVM_partial_outputs.pl --partitions partitions_list.out --output_file_name evm.out
/opt/biosoft/EVidenceModeler-1.1.1/EvmUtils/convert_EVM_outputs_to_GFF3.pl --partitions partitions_list.out --output_file_name evm.out --genome genome.fasta
cat */evm.out.gff3 > evm_out.gff3
gff3_clear.pl --prefix evm evm_out.gff3 > evm.gff3
cat transcript_alignments.gff3 protein_alignments.gff3 > evidence.gff3
evm_genes_filtering.pl evm.gff3 evidence.gff3 0.3 genome.fasta 1e-6 0.3 8 > evm.filter.gff3
# real	6m10.408s
# user	36m26.115s
# sys	10m45.392s


## PASA 对 EVM 结果进行更新
mkdir /home/train/10.gene_prediction/evm_pasa
cd /home/train/10.gene_prediction/evm_pasa
# 对 EVM 生成的 GFF3 格式的结果文件按染色体位置进行排序，并为基因id进行重命名
gff3_clear.pl --prefix evm ../evm/evm.filter.gff3 > evm.gff3
# 使用 PASA 对上一步生成的 gff3 文件进行更新。
cd ../pasa/
cp /opt/biosoft/PASApipeline.v2.4.1/pasa_conf/pasa.annotationCompare.Template.txt annotationCompare.config
PasaMysqlDB=`perl -ne 'print $1 if m/DATABASE=(\S+)/' alignAssembly.config`
echo "perl -p -i -e 's/DATABASE=.*/DATABASE=$PasaMysqlDB/' annotationCompare.config" | sh
/opt/biosoft/PASApipeline.v2.4.1/Launch_PASA_pipeline.pl -c annotationCompare.config -A -g genome.fasta -t transcripts.fasta.clean -T -u transcripts.fasta -L --annots ../evm_pasa/evm.gff3
# real	2m59.288s
# user	2m18.979s
# sys	2m2.800s
first_update_gff3=`ls *gene_structures_post_PASA_updates*.gff3 -t | head -n 1`
/opt/biosoft/PASApipeline.v2.4.1/Launch_PASA_pipeline.pl -c annotationCompare.config -A -g genome.fasta -t transcripts.fasta.clean -T -u transcripts.fasta -L --annots $first_update_gff3
second_update_gff3=`ls *gene_structures_post_PASA_updates*.gff3 -t | head -n 1`
/opt/biosoft/PASApipeline.v2.4.1/Launch_PASA_pipeline.pl -c annotationCompare.config -A -g genome.fasta -t transcripts.fasta.clean -T -u transcripts.fasta -L --annots $second_update_gff3
third_update_gff3=`ls *gene_structures_post_PASA_updates*.gff3 -t | head -n 1`
gff3_clear.pl --prefix evmPasa $third_update_gff3 > ../evm_pasa/evmPasa.gff3


## 使用GETA进行基因预测
mkdir -p /home/train/10.gene_prediction/GETA
cd /home/train/10.gene_prediction/GETA
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta

# wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/328/475/GCF_000328475.2_Umaydis521_2.0/GCF_000328475.2_Umaydis521_2.0_protein.faa.gz -P ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/
gzip -dc /home/train/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta

ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/RepeatModeler_database.consensi.fa consensi.fa
cat ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/*.1.fastq > reads.1.fastq
cat ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/*.2.fastq > reads.2.fastq

#geta.pl --RM_species fungi --genome genome.fasta -1 reads.1.fastq -2 reads.2.fastq --protein homolog.fasta --augustus_species Malassezia_sympodialis_geta --RM_lib consensi.fa --cpu 8 --pfam_db /opt/biosoft/hmmer-3.2.1/Pfam-AB.hmm --gene_prefix MS01Gene &> geta.log
# real	73m40.677s
# user	258m39.189s
# sys	15m7.167s
geta.pl --RM_species fungi --genome genome.fasta -1 reads.1.fastq -2 reads.2.fastq --protein homolog.fasta --use_existed_augustus_species malassezia_sympodialis --RM_lib consensi.fa --cpu 8 --pfam_db /opt/biosoft/hmmer-3.2.1/Pfam-AB.hmm --gene_prefix MS01Gene &> geta.log

# 去除可变剪接
bestGeneModels.pl out.gff3 > bestGeneModels.gff3 2> geneModelsStatistic
gff3ToGtf.pl genome.fasta bestGeneModels.gff3 > bestGeneModels.gtf

# 整理基因组注释信息
perl -p -e 's/\t\S+\t/\tGETA\t/' out.gff3 > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gff3
perl -p -e 's/\t\S+\t/\tGETA\t/' out.gtf > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gtf
perl -p -e 's/\t\S+\t/\tBestGeneModels\t/' bestGeneModels.gff3 > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gff3
perl -p -e 's/\t\S+\t/\tBestGeneModels\t/' bestGeneModels.gtf > ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gtf
cp out.cDNA.fasta ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.cDNA.fasta
cp out.CDS.fasta ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.CDS.fasta
cp out.gene.fasta ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.gene.fasta
cp out.pep.fasta ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.protein.fasta
cd ..


## 使用BUSCO进行基因组完整性分析
mkdir -p /home/train/10.gene_prediction/BUSCO
cd /home/train/10.gene_prediction/BUSCO
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 去除可变剪接
mkdir GFF3_files
bestGeneModels.pl ../augustus/augustus.gff3 > GFF3_files/augustus.gff3
bestGeneModels.pl ../genemark_es_et/genemarkES.gff3 > GFF3_files/genemarkES.gff3 
bestGeneModels.pl ../genemark_es_et/genemarkET.gff3 > GFF3_files/genemarkET.gff3
bestGeneModels.pl ../snap/snap.gff3 > GFF3_files/snap.gff3
bestGeneModels.pl ../maker/maker.gff3 > GFF3_files/maker.gff3
bestGeneModels.pl ../braker/braker.gff3 > GFF3_files/braker.gff3
bestGeneModels.pl ../evm_pasa/evm.gff3 > GFF3_files/evm.gff3
bestGeneModels.pl ../evm_pasa/evmPasa.gff3 > GFF3_files/evmPasa.gff3
bestGeneModels.pl ../GETA/out.gff3 > GFF3_files/geta.gff3

# 提取蛋白序列
mkdir protein_files
for i in `ls GFF3_files/*.gff3`
do
    x=${i/*\//}
    x=${x/.gff3/}
    echo "gff3_to_protein.pl genome.fasta $i > protein_files/proteins.$x.fasta"
done > command.gff3_to_protein.list
ParaFly -c command.gff3_to_protein.list -CPU 9
rm command.gff3_to_protein.list*

# 获取NCBI注释的蛋白序列
#wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/349/305/GCF_000349305.1_ASM34930v2/GCF_000349305.1_ASM34930v2_protein.faa.gz -P ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/
gzip -dc /home/train/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000349305.1_ASM34930v2_protein.faa.gz > protein_files/proteins.ncbi.fasta

# BUSCO分析
mkdir busco_out
for i in `ls protein_files/proteins.*.fasta`
do
    x=${i/*\//}
    x=${x/proteins./}
    x=${x/.fasta/}
    echo "cd busco_out; busco -i ../$i -c 8 -o $x -m proteins -l /opt/biosoft/busco-4.1.2/databases/basidiomycota_odb10 --offline"
done > command.BUSCO.list
ParaFly -c command.BUSCO.list -CPU 1
rm command.BUSCO.list*

grep C: */*/short_summary*.txt | perl -pe 's/.*odb10.(.+?).txt/$1/; $str = " " x (10 - length($1)); s/^/$str/;' > BUSCO.summary.txt
cd busco_out
ln -s */short_summary* .
/opt/biosoft/busco-4.1.2/scripts/generate_plot.py -wd ./ -rt specific
perl -p -i -e 's/my_family, colour/my_family, face="italic", colour/ if m/axis.text.y/; s/size=1/size=0.4/; s/\%BUSCO/\% BUSCO/;' busco_figure.R
cat busco_figure.R | R --vanilla --slave
cd ../../


## 使用SpliceGrapher进行可变剪接分析
mkdir -p /home/train/10.gene_prediction/spliceGrapher
cd /home/train/10.gene_prediction/spliceGrapher
# 准备基因组序列和注释文件
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gff3 > genome.gff3
perl -pe 's/^\s*$//' ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gtf > genome.gtf
# 输入给SpliceGrapher的sam结果文件不能有softclip信息
cd /home/train/06.reads_aligment/hisat2
hisat2 -x genome -p 4 --min-intronlen 20 --max-intronlen 4000 --rna-strandness RF -1 A.1.fastq -2 A.2.fastq -S /home/train/10.gene_prediction/spliceGrapher/hisat2.sam --no-softclip 
cd -
samtools sort -@ 8 -O sam -o 11.sam hisat2.sam; mv 11.sam hisat2.sam
ln -s /home/train/06.reads_aligment/hisat2/A.?.fastq ./
export SG_FASTA_REF=$PWD/genome.fasta
export SG_GENE_MODEL=$PWD/genome.gff3

mkdir 1.create_classifiers
cd 1.create_classifiers
build_classifiers.py -d gt,gc -a ag -l create_classifiers.log
# real	7m41.985s
# user	7m40.815s
# sys	0m2.435s
grep roc *.cfg

mkdir ../2.filter_alignments
cd ../2.filter_alignments
ln -s ../1.create_classifiers/classifiers.zip ./
sam_filter.py ../hisat2.sam classifiers.zip -o filtered.sam -v
# real	1m7.641s
# user	1m6.824s
# sys	0m1.216s

mkdir ../3.predict_graphs
cd ../3.predict_graphs
predict_graphs.py ../2.filter_alignments/filtered.sam -v
# real	0m57.385s
# user	0m56.808s
# sys	0m0.578s

mkdir ../4.realignment_pipeline
cd ../4.realignment_pipeline
realignment_pipeline.py ../3.predict_graphs/ -1 ../A.1.fastq -2 ../A.2.fastq
# real	0m39.302s
# user	0m49.648s
# sys	0m2.183s

mkdir ../5.calculate_counts
cd ../5.calculate_counts
# 得到包含可变剪接信息的gtf文件
ls $PWD/../4.realignment_pipeline/*/*.gff > predict_graphs.lis
generate_putative_sequences.py predict_graphs.lis -A -M splicegraph.gtf
# 注意生成的splicegraph.gtf文件中第一列，其序列ID的首字母可能会由原来的小写变为大写字母，其它字母会由大写变成小写，若发生该情况，则修改还原
perl -p -i -e 's/Ms01contig/MS01Contig/' splicegraph.gtf
# 若某个基因的可变剪接转录本过多，则该基因的信息不会包含在gtf文件中，需要从genome.gtf文件中添加该基因信息。
add_geneModels_to_spliceGrapher_GTF.pl splicegraph.gtf ../genome.gtf > all.gtf
samtools sort -@ 8 -O BAM -o filtered.bam ../2.filter_alignments/filtered.sam
# 使用cufflins进行转录本的表达量计算
cuffquant -o cufflinks -b ../genome.fasta -u -p 4 all.gtf filtered.bam &> cuffquant.log
cuffnorm -o cufflinks -L A,A -p 4 --library-norm-method classic-fpkm all.gtf cufflinks/abundances.cxb cufflinks/abundances.cxb
pick_effctive_isoforms.pl all.gtf cufflinks/isoforms.count_table > splicegraph.filtered.gtf 2> pick_effctive_isoforms.log

mkdir ../6.alternative_splicing_statisctis
cd ../6.alternative_splicing_statisctis
perl -p -e 's/(.*)(exon_number.*?;)(.*)( gene_name.*?;)(.*)/$1$3$5;$4 $2/' ../5.calculate_counts/splicegraph.filtered.gtf > splicegraph.filtered.gtf
para_alternative_splicing_statisctis.pl splicegraph.filtered.gtf 8 > alternative_splicing_statisctis.txt
alternative_splicing_count.pl alternative_splicing_statisctis.txt > alternative_splicing_statisctis.stats

mkdir ../7.create_graphs
cd ../7.create_graphs
samtools index ../5.calculate_counts/filtered.bam 
spliceGrapher_create_graphs.pl ../genome.gff3 ../5.calculate_counts/splicegraph.filtered.gtf ../5.calculate_counts/filtered.bam ./ 8

## 原核生物基因预测
mkdir -p /home/train/10.gene_prediction/genemark_s
cd /home/train/10.gene_prediction/genemark_s
#wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz -P ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/
gzip -dc ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/GCF_000005845.2_ASM584v2_genomic.fna.gz > genome.ecoli.fasta
perl -p -i -e 's/^(>\S+).*/$1/' genome.ecoli.fasta
/opt/biosoft/gms2_linux_64/gms2.pl --seq genome.ecoli.fasta --genome-type bacteria --gcode 11 --format gff --output gms2.gff --fnn genes.fasta --faa proteins.fasta
# --format 参数的值可以有 lst, gff, gtf, gff3
# real	1m19.722s
# user	1m18.800s
# sys	0m0.933s
geneMarkS_gff2gff3.pl gms2.gff Ecoli > gms2.gff3
