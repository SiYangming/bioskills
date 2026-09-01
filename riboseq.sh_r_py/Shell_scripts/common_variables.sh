#!/usr/bin/env bash

###filenames
#These are the filenames for all RPF and Total RNA-seq samples (without the <.fastq> or any alternative extension)
#这些是所有 RPF 和总 RNA‑seq 样本的文件名（不包含 <.fastq> 或其他扩展名）。
#RPF 样本文件名
RPF_filenames='RPF_1 RPF_2 RPF_3'
#总 RNA‑seq 样本文件名
Totals_filenames='Totals_1 Totals_2 Totals_3'

###set the sumber of threads available to use
#设置可用的线程数量。
#It is recomended to use one or two less than what is available and also consider whether any else is being run at the same time
#建议比实际可用核心数少用一到两个线程，并考虑是否有其他任务同时运行。
#Some of the packages used do not support multi-threading and so the for loops run in parallel, so that all files are run at the same time. For this reason do not run on more files than the number of cores available to use
#部分工具不支持多线程，此时通过并行 for 循环让所有文件同时运行，因此样本数量不要超过可用核心数。
threadN=16

###adaptors
#接头序列
#RPF adaptors
#RPF 接头
#This is the sequence of the 3' adaptor that was used in the library prep. Common sequences are below, unhash the correct one if present, or if not enter it as a variable
#这里是建库时使用的 3' 接头序列。下面给出了一些常见序列，如适用请取消注释；若都不合适，请自行设置新的接头序列。

RPF_adaptor='TGGAATTCTCGGGTGCCAAGG' #this is the adaptor used in the nextflex small RNA library kit
#这是 Nextflex small RNA 文库制备试剂盒使用的接头序列。
#RPF_adaptor='CTGTAGGCACCATCAAT' #this is the adaptor that seems to have been more commonly used in older ribosome-footprinting studies such as Wolfe 2014
#这是在较早的核糖体脚印研究（如 Wolfe 2014）中更常使用的接头序列。
#RPF_adaptor='AGATCGGAAGAGCAC' #this is the one stated in the McGlincy and Ingolia 2017 methods paper
#这是 McGlincy 和 Ingolia 2017 方法学论文中使用的接头序列。
#RPF_adaptor=''

#Totals adaptors
#Totals 接头
Totals_adaptor='AGATCGGAAGAG' #this is the adaptor used in the LEXOGEN CORALL Total RNA-Seq Library Prep Kit
#这是 LEXOGEN CORALL Total RNA‑Seq 文库制备试剂盒使用的接头序列。

###paths
#路径
parent_dir='/Path/to/data' #This is the path to the parent directory that contains all the data and where all the processed data will be saved
#这是包含所有数据且用于保存所有处理结果的父目录路径。

#The following directories are where all the processed data will be saved. These all need to be created prior to starting the analysis
#下面这些目录用于保存所有处理后的数据，在开始分析前需要提前创建。

#set the directory where the raw bcl data is. the directory that contains the raw sequencing data in bcl format. This is what you get from a sequencing run and needs to be demulitplexed to write the <.fastq> files.
#设置原始 bcl 数据所在目录，即包含原始测序 bcl 文件的目录；这些文件需要通过拆分流程转换为 <.fastq>。
#If you have more than one bcl directory (you will get one for each sequencing run), then hash one out and write a new one below, each time you re-run the demultiplex.sh script script, so that this acts as a log for all the bcl directories associated with this project
#如果有多个 bcl 目录（每次测序运行一个），每次重新运行 demultiplex.sh 时，将旧路径注释掉并在下方写入新的路径，以此作为该项目所有 bcl 目录的记录。
bcl_dir='Path/to/bcl/data'

fastq_dir=${parent_dir}/fastq_files
fastqc_dir=${parent_dir}/fastQC_files
SAM_dir=${parent_dir}/SAM_files
BAM_dir=${parent_dir}/BAM_files
log_dir=${parent_dir}/logs
counts_dir=${parent_dir}/Counts_files
csv_counts_dir=${parent_dir}/Counts_files/csv_files
csv_R_objects=${parent_dir}/Counts_files/R_objects

STAR_dir=${parent_dir}/STAR
rsem_dir=${parent_dir}/rsem

#The following directories are where all the csv files that are used as input into R will be saved
#下面这些目录用于保存作为 R 输入的所有 csv 文件。
analysis_dir=${parent_dir}/Analysis

region_counts_dir=${analysis_dir}/region_counts
spliced_counts_dir=${analysis_dir}/spliced_counts
periodicity_dir=${analysis_dir}/periodicity
cds_counts_dir=${analysis_dir}/CDS_counts
UTR5_counts_dir=$analysis_dir/UTR5_counts
codon_counts_dir=${analysis_dir}/codon_counts
most_abundant_transcripts_dir=${analysis_dir}/most_abundant_transcripts
DESeq2_dir=${analysis_dir}/DESeq2_output
reads_summary_dir=${analysis_dir}/reads_summary
fgsea_dir=${analysis_dir}/fgsea

#The following directories are where all the plots generated in R will be saved
#下面这些目录用于保存 R 生成的所有图形结果。
plots_dir=${parent_dir}/plots

summed_counts_plots_dir=${plots_dir}/summed_counts
periodicity_plots_dir=${plots_dir}/periodicity
offset_plots_dir=${plots_dir}/offset
heatmaps_plots_dir=${plots_dir}/heatmaps
DE_analysis_dir=${plots_dir}/DE_analysis
PCA_dir=${plots_dir}/PCAs
Interactive_scatters_dir=${plots_dir}/Interactive_scatters
fgsea_plots_dir=${plots_dir}/fgsea
fgsea_scatters_dir=${plots_dir}/fgsea/scatters
fgsea_interactive_scatters_dir=${plots_dir}/fgsea/Interactive_scatters
read_counts_summary_dir=${plots_dir}/read_counts_summary
binned_plots_dir=${plots_dir}/binned_plots
single_transcript_binned_plots_dir=${plots_dir}/binned_plots/single_transcripts
normalisation_binned_plots_dir=${plots_dir}/binned_plots/normalisation


#Fastas
#FASTAs 文件
fasta_dir='/Path/to/FASTAs'

rRNA_fasta=${fasta_dir}/rRNA/human_rRNA.fa #this needs to point to a fasta file containing rRNA sequences for the correct species
#需指向包含目标物种 rRNA 序列的 fasta 文件。
tRNA_fasta=${fasta_dir}/tRNA/human_mature_tRNA.fa #this needs to point to a fasta file containing tRNA sequences for the correct species
#需指向包含目标物种 tRNA 序列的 fasta 文件。
pc_fasta=${fasta_dir}/GENCODE/v38/filtered/gencode.v38.pc_transcripts_filtered.fa #this needs to point to a protein coding fasta. See GitHub README file for more information on what is most recommended
#需指向蛋白编码转录本的 fasta，推荐设置见 GitHub README。
rsem_index=${fasta_dir}/GENCODE/v38/filtered/rsem_bowtie2_index/gencode.v38.pc_transcripts_filtered #this needs to point to a index that has been generated for alignment, that is also compatible for RSEM usage. Bowtie2 is recommended for this
#需指向已生成的比对索引，并且可与 RSEM 兼容，推荐使用 Bowtie2 索引。
STAR_index=${fasta_dir}/GENCODE/v38/original/STAR_index #This needs to point to a STAR genome index that needs to have been previously created
#需指向预先生成的 STAR 基因组索引。
STAR_GTF=${fasta_dir}/GENCODE/v38/original/gencode.v38.annotation.gtf #This needs to point to the GTF file used to create the STAR index
#需指向用于构建 STAR 索引的 GTF 文件。
most_abundant_fasta=$most_abundant_transcripts_dir/most_abundant_transcripts.fa #this needs to be created for each specific project (see GitHub README file for more information)
#该 fasta 需针对每个具体项目生成（详见 GitHub README）。

###fasta info
#The below needs to point to a <.csv> file that contains the following information for all transcripts within the protein coding FASTA
#下面的路径需指向一个 <.csv> 文件，包含蛋白编码 FASTA 中所有转录本的如下信息：
#transcript_ID,5'UTR length,CDS length,3'UTR length
#transcript_ID,5'UTR 长度,CDS 长度,3'UTR 长度
#Running the Filter_GENCODE_FASTA.py script will generate this file as one of its outputs
#运行 Filter_GENCODE_FASTA.py 脚本会生成该文件作为输出之一。

region_lengths=${fasta_dir}/GENCODE/v38/transcript_info/gencode.v38.pc_transcripts_region_lengths.csv
