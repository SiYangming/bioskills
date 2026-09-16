mkdir -p /home/train/15.qiime/
cd /home/train/15.qiime/
# 本流程来自：https://docs.qiime2.org/2017.12/tutorials/moving-pictures

# 载入QIIME 2运行环境
PATH=/opt/biosoft/miniconda3_for_QIIME2/bin:$PATH
source activate qiime2-2020.6
source tab-qiime

## 1. 准备QIIME 2的输入文件。

# 准备 sample metadata 文件，该文件是使用TAB键分割的文本文件，用于对样品信息进行汇总。
# sample metadata 格式：
# （1）必须是TAB键分割。
# （2）以#开头或空行都将被忽略。
# （3）第一个非空非注释行信息为表头，或者以#SampleID开头的第一行为表头。
# （4）除了表头之外，至少有额外一行非空非注释行信息为数据信息。
# （5）第一列是必须是样品名信息，且不能有相同的样品名。
# （6）表头所有列的值不能含有怪异字符。
#wget https://data.qiime2.org/2017.12/tutorials/moving-pictures/sample_metadata.tsv
mkdir 03.qimme2_prepare_data/
cp ~/00.incipient_data/data_for_qiime2/sample-metadata.tsv ./03.qimme2_prepare_data/

# 准备测序数据文件
# 示例数据是EMP（Earth Microbiome Project）格式的单端测序数据。EMP组织产出的单端测序数据是2个文件：sequences fastq文件，包含所有样品的所有测序数据，该文件中不同样品的数据是混在一起的，称之为multiplex数据；barcodes fastq文件，该文件和sequences fastq文件行数一致，每行都逐一对应，只是第二行序列是barcode信息。EMP的双末端测序数据则是3个文件：2个sequences fastq文件和1个barcodes fastq文件。
mkdir 01.emp-single-end-sequences/
#wget https://data.qiime2.org/2017.12/tutorials/moving-pictures/emp-single-end-sequences/barcodes.fastq.gz -P emp-single-end-sequences/
#wget https://data.qiime2.org/2017.12/tutorials/moving-pictures/emp-single-end-sequences/sequences.fastq.gz -P emp-single-end-sequences/
cp ~/00.incipient_data/data_for_qiime2/barcodes.fastq.gz ./01.emp-single-end-sequences/
cp ~/00.incipient_data/data_for_qiime2/sequences.fastq.gz ./01.emp-single-end-sequences/

# 将测序数据文件转换成 qza 格式。
# QIMME2流程中每个步骤的输入文件和输出文件都是qza（artifact）格式文件，该文件是一个二进制文件，包含有各种信息。可以使用相关命令对qza文件进行解析，得到qzv（visualization）文件。qzv文件则可以用于可视化。
qiime tools import \
  --type EMPSingleEndSequences \
  --input-path 01.emp-single-end-sequences \
  --output-path 03.qimme2_prepare_data//emp-single-end-sequences.qza
# real	0m2.841s
# user	0m2.756s
# sys	0m0.532s

# 使用 qiime tools peek 命令可以查看 qza 文件的属性（数据类型，数据格式）。
qiime tools peek 03.qimme2_prepare_data/emp-single-end-sequences.qza

# 对测序数据按样品进行分割。
# 若本来从公司拿到的数据就是分样之后的数据，则不需要进行此步骤。
# sample-metadata.tsv文件中第一行第二列的值是BarcodeSequence，将该值作为--m-barcodes-category参数的值。
qiime demux emp-single \
  --i-seqs 03.qimme2_prepare_data/emp-single-end-sequences.qza \
  --m-barcodes-file 03.qimme2_prepare_data/sample-metadata.tsv \
  --m-barcodes-category BarcodeSequence \
  --o-per-sample-sequences 03.qimme2_prepare_data/demux.qza
# real	0m25.722s
# user	0m25.599s
# sys	0m0.580s

# 使用 qiime tools export 命令可以导出 qza 文件的数据。
qiime tools export --output-dir 02.Illumina_fastq_data 03.qimme2_prepare_data/demux.qza
# 生成文件夹demux_data，其中包含各个样品的fastq文件。

# 对demux.qza数据进行统计
cd 03.qimme2_prepare_data/
qiime demux summarize --i-data demux.qza --o-visualization demux.qzv
# 使用 qiime tools view 对 qzv 文件进行可视化查看
qiime tools view demux.qzv

# 对数据按照碱基质量进行质量控制
# 默认设置下：只要连续3个碱基的质量值都低于4，则对其进行截断；若截断后的read产度低于原长度的75%，则去除该read。此默认阈值不是太好，最好使用相应参数调整一下。
# 例如，对于双末端各测250bp数据，我个人推荐阈值为：连续3个碱基的质量值都低于10，则对其进行截断；若截断后的read产度低于原长度的50%（低于50%后，则两端reads可能刚好没有足够的重叠长度），则去除该read。（默认阈值是：--p-min-quality 4 --p-quality-window 3 --p-min-length-fraction 0.75）
qiime quality-filter q-score \
 --i-demux demux.qza \
 --o-filtered-sequences demux-filtered.qza \
 --o-filter-stats demux-filter-stats.qza \
 --p-min-quality 10 \
 --p-quality-window 3 \
 --p-min-length-fraction 0.5
# real	0m28.940s
# user	0m28.837s
# sys	0m0.562s
# 个人推荐优先对数据使用trimmomatic进行处理，速度更快，还能并行化计算。
cd ..

#########################################################################
# 以上是使用示例数据做的qza文件准备，其示例数据EMP格式的数据。而很多人从测序公司拿到的数据不是EMP格式，多样品的数据，每个样品双末端测序得到两个fastq文件。对此类数据进行qza格式准备，首先要准备一个Manifest文件。
# Manifest文件格式：a.	该文件内容分3列，以逗号分割；b.	第一行必须是"sample-id,absolute-filepath,direction"；c.	后面每两行表示一个样品，第一列的样品名必须和sample metadata文件一致，第二列是其fastq文件绝对路径，第三列是数据方向forward或reverse。因此，双末端测序数据每个样品用两行进行描述。
# 推荐优先使用Trimmomatic对fastq文件进行质量控制
# 再使用tools import转换得到qza文件。
# qiime tools import \
#  --type 'SampleData[PairedEndSequencesWithQuality]' \
#  --input-path illumina_data.manifest \
#  --output-path illumina_data.qza \
#  --source-format PairedEndFastqManifestPhred33
#########################################################################


## 2. 使用QIIME 2进行OTU（Feature Table）分析
# 有两种方法可以选择 dada2 或 deblur。
# dada2能够多线程进行计算，速度比deblur快；dada2支持双末端测序数据，deblur仅支持单短测序数据；deblur在进行OTU计算前，可以利用内置的16s reference或使用参数选择一个指定的18s reference对数据进行过滤。
# 因此，一般情况下更多人会使用dada2进行分析。

# 使用dada2进行OTU分析
# dada2可以对数据进行质量控制。但仅能进行5'和3'端整体截短。若是之前进行了碱基质量控制，则可以不进行截短：--p-trim-left 0 --p-trunc-len 0
# dada2可以进行并行化运算：--p-n-threads 0 表示使用所有可用CPU线程
# dada2默认能分别对各个样品去除嵌合体数据。
mkdir 04.feature_table
cd 04.feature_table
qiime dada2 denoise-single \
  --i-demultiplexed-seqs ../03.qimme2_prepare_data/demux.qza \
  --p-trim-left 0 \
  --p-trunc-len 120 \
  --o-representative-sequences rep-seqs-dada2.qza \
  --o-table table-dada2.qza \
  --p-n-threads 0
# real	1m7.540s
# user	3m26.111s
# sys	0m3.747s

#########################################################################
# 对使用Trimomatic做过质量控制的双末端测序数据，则使用如下命令行：
# qiime dada2 denoise-paired \
#  --i-demultiplexed-seqs illumina_data.qza \
#  --p-trim-left 0 \
#  --p-trunc-len 0 \
#  --o-representative-sequences rep-seqs.qza \
#  --o-table table.qza \
#  --p-n-threads 0
#########################################################################

# 使用deblur进行OTU分析
# 软件说明中设置--p-trim-length参数值为-1，表示不进行reads截短，但是其参数值为-1，会导致程序运行失败。
qiime deblur denoise-16S \
  --i-demultiplexed-seqs ../03.qimme2_prepare_data/demux-filtered.qza \
  --p-trim-length 120 \
  --o-representative-sequences rep-seqs-deblur.qza \
  --o-table table-deblur.qza \
  --o-stats deblur-stats.qza
# real	2m36.198s
# user	2m33.083s
# sys	0m3.304s

mv rep-seqs-dada2.qza rep-seqs.qza
mv table-dada2.qza table.qza

# 导出代表性序列
qiime tools export --output-dir ./ rep-seqs.qza
# 导出OTU（Feature Table）
qiime tools export --output-dir ./ table.qza
biom convert -i feature-table.biom -o feature-table.tsv --to-tsv

# 对OTU进行统计
qiime feature-table summarize \
  --i-table table.qza \
  --o-visualization table.qzv \
  --m-sample-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv
qiime feature-table tabulate-seqs \
  --i-data rep-seqs.qza \
  --o-visualization rep-seqs.qzv
# 导出OTU统计信息
qiime tools export --output-dir ./OTU_summarize table.qzv
cd ..


## 3. 进行系统发育树分析
mkdir 05.phylogenetic_tree
cd 05.phylogenetic_tree
# 先调用mafft进行多序列比对
# --p-n-threads 参数设置成 -1 表示使用全部可用的CPU线程数。
qiime alignment mafft \
  --i-sequences ../04.feature_table/rep-seqs.qza \
  --p-n-threads -1 \
  --o-alignment aligned-rep-seqs.qza
# real	0m2.048s
# user	0m2.278s
# sys	0m0.567s

# 再去除多序列比对结果中的掉非保守位点
# 默认设置下，若某个位点一致性的碱基占低于40%，则去除该位点。
qiime alignment mask \
  --i-alignment aligned-rep-seqs.qza \
  --o-masked-alignment masked-aligned-rep-seqs.qza
# real	0m2.744s
# user	0m2.682s
# sys	0m0.511s

# 最后，调用fasttree进行系统发育树构建
qiime phylogeny fasttree \
  --i-alignment masked-aligned-rep-seqs.qza \
  --p-n-threads -1 \
  --o-tree unrooted-tree.qza
# real	0m3.631s
# user	0m3.553s
# sys	0m0.526s
# 使用midpoint的方法，将无根树变成有根树
qiime phylogeny midpoint-root \
  --i-tree unrooted-tree.qza \
  --o-rooted-tree rooted-tree.qza
# real	0m1.650s
# user	0m1.587s
# sys	0m0.510s

# 导出树文件
qiime tools export --output-dir ./ rooted-tree.qza
# real	0m1.537s
# user	0m1.490s
# sys	0m0.494s

# 使用figtree画树
perl -pe 's/root//' tree.nwk > tree.txt
java -jar /opt/biosoft/FigTree_v1.4.2/lib/figtree.jar tree.txt
cd ..


## 4. alpha和beta多样性分析
mkdir 06.diversity_analysis
cd 06.diversity_analysis
# 进行多样性矩阵计算。先查看各个samples的count总数，再决定一个--p-sampling-depth参数值：低于此值的samples则被忽略掉，高于此值的samples则随机挑选出该指定数值的counts数据进行多样性矩阵计算。
qiime diversity core-metrics-phylogenetic \
  --i-phylogeny ../05.phylogenetic_tree/rooted-tree.qza \
  --i-table ../04.feature_table/table.qza \
  --p-sampling-depth 1109 \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --output-dir core-metrics-results
# real	0m3.253s
# user	0m3.129s
# sys	0m1.780s

# 进行alpha多样性分析（样品内生物种类的多样性）
qiime diversity alpha-group-significance \
  --i-alpha-diversity core-metrics-results/faith_pd_vector.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --o-visualization core-metrics-results/faith-pd-group-significance.qzv
# real	0m1.805s
# user	0m1.723s
# sys	0m0.528s
qiime diversity alpha-group-significance \
  --i-alpha-diversity core-metrics-results/evenness_vector.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --o-visualization core-metrics-results/evenness-group-significance.qzv
# real	0m1.805s
# user	0m1.690s
# sys	0m0.563s

# 进行beta多样性分析（表明不同样品的多样性）
qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --m-metadata-category BodySite \
  --o-visualization core-metrics-results/unweighted-unifrac-body-site-significance.qzv \
  --p-pairwise
# real	0m2.708s
# user	0m2.777s
# sys	0m1.699s
qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --m-metadata-category Subject \
  --o-visualization core-metrics-results/unweighted-unifrac-subject-group-significance.qzv \
  --p-pairwise
# real	0m2.140s
# user	0m2.146s
# sys	0m1.262s

# PCoA分析
qiime emperor plot \
  --i-pcoa core-metrics-results/unweighted_unifrac_pcoa_results.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --p-custom-axis DaysSinceExperimentStart \
  --o-visualization core-metrics-results/unweighted-unifrac-emperor.qzv
# real	0m1.861s
# user	0m1.780s
# sys	0m0.528s

qiime emperor plot \
  --i-pcoa core-metrics-results/bray_curtis_pcoa_results.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --p-custom-axis DaysSinceExperimentStart \
  --o-visualization core-metrics-results/bray-curtis-emperor.qzv
# real	0m1.857s
# user	0m1.732s
# sys	0m0.572s
cd ..


## 5. 群落组成分析
mkdir 07.taxonomic_analysis
cd 07.taxonomic_analysis
# 首先，根据引物序列和Greengenes 13_8 99% OTUs (16S)数据进行classifier training。
# Greengenes数据库收集了较全的细菌16S序列，包含OTUs信息；13_8是2013年8月释放的最新版本数据；99%指OTU按99% Identity进行16S序列分类。
# 若分析其它数据，则选用其它对应的数据库（http://qiime.org/home_static/dataFiles.html）。16S/18S混合选用SLIVA数据库；ITS数据选用UNITE OTU数据库。
mkdir classifier_training
cd classifier_training/
# 准备classifier training数据
#wget ftp://greengenes.microbio.me/greengenes_release/gg_13_5/gg_13_8_otus.tar.gz
tar zxf ~/00.incipient_data/data_for_qiime2/gg_13_8_otus.tar.gz
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path gg_13_8_otus/rep_set/99_otus.fasta \
  --output-path 99_otus.qza
# real	0m48.255s
# user	0m47.200s
# sys	0m0.737s
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --source-format HeaderlessTSVTaxonomyFormat \
  --input-path gg_13_8_otus/taxonomy/99_otu_taxonomy.txt \
  --output-path ref-taxonomy.qza
# real	0m2.690s
# user	0m2.635s
# sys	0m0.501s
# 使用引物序列提取reference序列
# 使用515F/806R primer pair进行扩增子测序
# 之前进行OTU分析时，将reads截短到了120bp，进行referece提取，同样截短到120bp
qiime feature-classifier extract-reads \
  --i-sequences 99_otus.qza \
  --p-f-primer GTGCCAGCMGCCGCGGTAA \
  --p-r-primer GGACTACHVGGGTWTCTAAT \
  --p-trunc-len 120 \
  --o-reads ref-seqs.qza
# real	6m58.575s
# user	6m58.241s
# sys	0m0.947s
# 进行classifier training
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads ref-seqs.qza \
  --i-reference-taxonomy ref-taxonomy.qza \
  --o-classifier classifier.qza
# real	2m32.348s
# user	2m19.289s
# sys	0m11.871s
cd ..

# 或下载官网已经使用Greengenes 13_8 99% OTUs training完毕的classifer数据
# 进行群落组成分析
#wget https://data.qiime2.org/2017.12/common/gg-13-8-99-515-806-nb-classifier.qza
cp ~/00.incipient_data/data_for_qiime2/gg-13-8-99-515-806-nb-classifier.qza ./
qiime feature-classifier classify-sklearn \
  --i-classifier gg-13-8-99-515-806-nb-classifier.qza \
  --i-reads ../04.feature_table/rep-seqs.qza \
  --o-classification taxonomy.qza
# real	0m32.614s
# user	0m31.646s
# sys	0m1.413s
qiime metadata tabulate \
  --m-input-file taxonomy.qza \
  --o-visualization taxonomy.qzv
# real	0m1.905s
# user	0m1.824s
# sys	0m0.521s
# 对结果进行统计画图
qiime taxa barplot \
  --i-table ../04.feature_table/table.qza \
  --i-taxonomy taxonomy.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --o-visualization taxa-bar-plots.qzv
# real	0m1.911s
# user	0m1.813s
# sys	0m0.540s
cd ..


## 6. 使用ANCOM进行样品间OTU丰度差异分析
mkdir 08.ANCOM
cd 08.ANCOM
# ANCOM分析需要满足一个假设：绝大部分features（>75%）在两个需要进行比较的样品中是没有丰度差异的。
# 由于进行分析的所有数据不能满足上述假设，在这里，仅提取BodySite='gut'的数据进行分析，这些数据采集自同一个组织，差异较小，能使用ANCOM进行分析。
qiime feature-table filter-samples \
  --i-table ../04.feature_table/table.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --p-where "BodySite='gut'" \
  --o-filtered-table gut-table.qza

# 由于进行差异分析，数据中不能含有零值，因此要对零值增加一个pseudocount；默认对每个count都增加1，这样矩阵文件中就没有零值了。
qiime composition add-pseudocount \
  --i-table gut-table.qza \
  --o-composition-table comp-gut-table.qza

# 进行ANCOM分析
# 仅能对两类不同的样品进行OTU丰度差异分析，以下使用Subject进行分析。在sample-metadata.tsv中，Subject一列有且仅有两种不同的值，否则程序会出错。
# 以下分析数据中Subject两种不同类型样品间的差异比较
qiime composition ancom \
  --i-table comp-gut-table.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --m-metadata-category Subject \
  --o-visualization ancom-Subject.qzv

# 以上是对level 7进行的分析，也可以对其它level水平上进行ANCOM分析
qiime taxa collapse \
  --i-table gut-table.qza \
  --i-taxonomy ../07.taxonomic_analysis/taxonomy.qza \
  --p-level 6 \
  --o-collapsed-table gut-table-l6.qza

qiime composition add-pseudocount \
  --i-table gut-table-l6.qza \
  --o-composition-table comp-gut-table-l6.qza

qiime composition ancom \
  --i-table comp-gut-table-l6.qza \
  --m-metadata-file ../03.qimme2_prepare_data/sample-metadata.tsv \
  --m-metadata-category Subject \
  --o-visualization l6-ancom-Subject.qzv
