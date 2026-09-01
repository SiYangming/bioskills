# Ribo-seq
This analysis pipeline processes sequencing data from both Ribosome Protected Footprints (RPFs) and the associated total RNA-seq for Ribosome-footprinting data.
该分析流程用于同时处理核糖体保护片段（RPFs, Ribosome Protected Footprints）以及对应的总 RNA‑seq 数据，用于核糖体足迹（Ribosome-footprinting）分析。

**Please ensure you read the following instructions carefully before running this pipeline.**
**在运行本流程之前，请务必仔细阅读以下说明。**

## Dependencies
依赖环境
Make sure you have all dependencies installed by following the instructrions [here](https://github.com/Bushell-lab/Ribo-seq/tree/main/Installation)
请按照[此处说明](https://github.com/Bushell-lab/Ribo-seq/tree/main/Installation)安装和检查所有依赖软件。

## Pipeline
流程概览
This pipeline is intended for use for people with basic bioinformatic skills. It is intended so that individual scripts can be easily edited to reflect the needs and choices of the user.
本流程适合具有基础生物信息学技能的用户使用，脚本设计为可根据用户需求方便修改。
It uses custom shell scripts to call external programs and custom python scripts, to process the data. The processed data can then be used as input into the custom R scripts to either generate library QC plots, perform differential expression (DE) analysis with DEseq2 or to determine positional enrichment of ribosome occupancy across the length of the mRNA.
本流程通过自定义 Shell 脚本调用外部程序与自定义 Python 脚本完成数据处理，并将处理后的结果作为输入交给自定义 R 脚本，用于生成文库 QC 图、利用 DESeq2 进行差异表达分析，以及评估 mRNA 全长范围内的核糖体占据位置富集情况。

### Shell scripts
The shell scripts <.sh> are designed to serve as a template for processing the data but require the user to modify them so that they are specific to each experiment. This is because different library prep techniques are often used, such as the use of different **adaptor sequences** or the use of **UMIs**. It is therefore essential that the user knows how the libraries were prepared before starting the analysis. If this is their own data then this should already be known, but for external data sets this is often not as straight forward as expected. Also, it can be unclear whether the data uploaded to GEO is the raw unprocessed <.fastq> files or whether initial steps such as adaptor removal or de-duplication and UMI removal have already been carried out. This is why each processing step is carried out seperately and why the output from these steps is checked with fastQC, so it is essential that the user checks these files by visual inspection after each step, so that the user can be certain that the step has processed the data as expected. Each shell script has annotation at the top describing what the script does and which parts might need editing. **It is therefore strongly recommended that the user opens up each shell script and reads and understands them fully before running them**
该 Shell 脚本集合（<.sh>）提供了数据处理的模板，但需要根据具体实验进行修改，因为不同的建库方案可能使用不同的接头序列（**adaptor sequences**）和 UMI。用户必须在分析前清楚建库方式，尤其是对外部数据要额外小心，搞清 GEO 上的 <.fastq> 是原始文件还是已经做过去接头、去重复和 UMI 去除等预处理。因此本流程将每个步骤拆开，并在每一步后用 fastQC 检查输出文件，要求用户逐步人工检查 fastQC 报告，以确保每一步确实按预期运行。每个 Shell 脚本开头都有说明脚本功能和需修改部分的注释，**强烈建议在运行前打开并充分阅读、理解这些脚本。**

### R scripts
The R scripts will read in the processed data generated from the custom python scripts and generate plots and perform DE analysis. These shouldn't need to be edited as the final processed data should be in a standard format, although the user is free to do what they wish with these and change the styles of the plots or add further analyses/plots should they wish. The common_variables.R (see below) script will need to be edited to add the filenames and path to the parent directory, as well as the read lengths that they wish to inspect with the library QC plots. The common_variables.R script needs to be in the current working directory when running the other <.R> scripts.
这些 R 脚本会读取自定义 Python 脚本生成的处理后数据，用于绘图和差异表达分析。通常不需要修改 R 脚本本身，因为最终数据格式是标准化的；不过你可以自由修改作图风格或添加额外分析。需要重点修改的是 common_variables.R（见下文），包括：文件名、父目录路径，以及用于文库 QC 检查的 read 长度等。运行其他 <.R> 脚本时，common_variables.R 必须位于当前工作目录。

### Python scripts
The <.py> python scripts should not need to be edited. These can be used for multiple projects and so it is recommended that these are placed in a seperate directory. If you set the $PATH to this directory, they can be called from any directory and therefore be used for all Ribo-seq analyses. To do this you need to open the .bashrc file from your home directory with the following lines of code;
这些 <.py> Python 脚本通常不需要修改，可以在多个项目间复用。建议将它们放在单独的目录中，并把该目录加入 $PATH，这样在任意目录都可以直接调用这些脚本用于 Ribo-seq 分析。为此，可以在 home 目录下编辑 .bashrc 并加入以下内容：
```console
cd
nano .bashrc
```
Then within the file add the following line
在 .bashrc 文件中添加如下这一行：
export PATH=$PATH:path/to/python_scripts/folder
This will add the folder to the path but only upon opening up a new terminal window. To check it's worked, open up a new terminal and run
这会将该目录添加到 PATH 中，但只有重新打开终端窗口后才会生效。要检查是否添加成功，可打开一个新的终端并运行：
```console
echo $PATH
```

## Setting up the project
- Before running any scripts, create a new directory for the experiment. This will be the parent directory which will contain all raw and processed data for the experiment as well as any plots generated.
- 在运行任何脚本之前，为本次实验创建一个新的目录作为父目录，用于存放本实验的所有原始数据、处理后数据以及生成的所有图形。
- Then create a folder within this directory to place all the shell <.sh> and R <.R> scripts from this GitHub repository. Ensure the $PATH is set to the directory cotaining all the <.py> scripts from this repository.
- 然后在该目录下创建一个子目录，用于存放本 GitHub 仓库中的所有 Shell <.sh> 和 R <.R> 脚本，并确保 $PATH 中包含本仓库所有 <.py> 脚本所在的目录。
- There is a common_variables.sh and common_variables.R script that will both need to be edited before running any of the other scripts. The filenames for both the RPF and Totals <.fastq> files (without the <.fastq> extension) will need to be added, as well as the path to the parent directory and the adaptor sequences. The path to the FASTA files and RSEM index which will be used for mapping also needs to be added. These should be common between all projects from the same species so should be stored in a seperate directory from the project directory.
- 在运行其他脚本之前，需要先编辑 common_variables.sh 和 common_variables.R：为 RPF 和 Totals 的 <.fastq> 文件设置文件名前缀（不含 .fastq 后缀），指定父目录路径和接头序列，以及用于比对的 FASTA 文件和 RSEM index 路径。通常同一物种的不同项目可以共用这些 FASTA 和 index，建议将它们存放在独立于项目目录的路径下。
- A region lengths <.csv> file that contains ***transcript_ID, 5'UTR length, CDS length, 3'UTR length*** in that stated order without a header line, for all transcripts within the protein coding FASTA is also required and the common_variables.sh script needs to point to this file.
- 还需要一个区域长度（region lengths）<.csv> 文件，按 ***transcript_ID, 5'UTR length, CDS length, 3'UTR length*** 的顺序排列且不含表头，涵盖蛋白编码 FASTA 中所有转录本，并在 common_variables.sh 中指向该文件。
- Once the common_variables.sh script has been completed, run the ***makeDirs.sh*** to set up the file structure to store all raw and processed data within the parent directory. Alternativly you can create these directories manually without the command line.
- 在完成 common_variables.sh 的编辑后，运行 ***makeDirs.sh*** 以在父目录下建立完整的目录结构，用于存放所有原始和处理后的数据；也可以不通过命令行而手动创建相同的目录结构。
- **It is highly recommended that this data structure is followed as the scripts are designed to output the data in these locations and this makes it much easier for other people to understand what has been done and improves traceability. The filenames are also automatically generated within each script and should contain all important information. Again it is highly recommended that this is not altered for the same reasoning.**
- **强烈建议严格遵循这一目录结构，因为脚本的输出路径是基于该结构设计的，这有助于他人理解和追踪分析过程；脚本会自动生成包含关键信息的文件名，也不建议随意更改。**
- Once the directories have been set up, the raw <.fastq> files need to be written to the fastq_files directory. If these already exist, then simply copy them across. If these need to be downloaded from GEO, then use the ***download_fastq_files.sh*** script to download these, ensuring they get written to the fastq_files directory. If this is your own data and you have the raw bcl sequencing folder, you will need to de-mulitplex and write the <.fastq> files. Use the ***demultiplex.sh*** script for this, which uses bcl2fastq (needs to be downloaded with conda), again writing the <.fastq> files to the fastq_files directory. These <.fastq> files will be the input into the ***RPFs_0_QC.sh*** and ***RPFs_1_adaptor_removal.sh*** scripts, so check that that extensiones match. It is fine if these files are <.gz> compressed as both fastQC and cutadapt can use compressed files as input, but again make sure that the shell scripts have the .gz extension included. 
- 当目录结构搭建完成后，需要将原始 <.fastq> 文件写入 fastq_files 目录：若文件已经存在则直接复制；若需要从 GEO 下载，则使用 ***download_fastq_files.sh*** 并确保输出到 fastq_files；若是自己的原始测序 bcl 文件，则需先进行 demultiplex，再生成 <.fastq> 文件，可使用依赖 bcl2fastq 的 ***demultiplex.sh***（可通过 conda 安装）。这些 <.fastq> 文件将作为 ***RPFs_0_QC.sh*** 和 ***RPFs_1_adaptor_removal.sh*** 的输入，注意脚本中的扩展名要与实际文件一致。如果文件是 .gz 压缩的，fastQC 和 cutadapt 也能直接使用，但要保证 Shell 脚本中的文件名包含 .gz 扩展名。

## FASTA file
It is up to the user to decide what FASTA file to use for alignments.
选择用于比对的 FASTA 文件由用户自行决定。

Protein coding FASTAs can be downloaded from the GENCODE website for mouse and human transcriptomes. It should be noted however that these possess a large number of transcripts that do not contain UTRs and have CDSs that are not equally divisible by 3, therefore are unlikely to be correctly annotated and/or undergo cap-dependent translation.
小鼠和人类的蛋白编码转录组 FASTA 可以从 GENCODE 网站下载，但其中包含大量不带 UTR 或 CDS 长度不能被 3 整除的转录本，这类转录本往往注释质量欠佳，且不一定发生典型的帽依赖起始翻译。

The Filtering_GENCODE_FASTA.py script will
- ensures the transcript has been manually annotated by HAVANA
- ensure the transcript has both a 5' and 3'UTR
- ensure the CDS is equally divisible by 3
- ensure the CDS starts with an nUG start codon
- ensure the CDS ends with a stop codon
- remove any PAR_Y transcripts
Filtering_GENCODE_FASTA.py 脚本会进行如下过滤：
- 确保转录本由 HAVANA 手工注释
- 确保转录本同时具有 5'UTR 和 3'UTR
- 确保 CDS 长度可被 3 整除
- 确保 CDS 以 nUG 起始密码子开始
- 确保 CDS 以终止密码子结束
- 移除所有 PAR_Y 转录本

When this is run on the human v38 protein-coding FASTA, the filtered FASTA has 52,059 transcripts from 18,995 genes, whereas the original FASTA had 106,143 transcripts from 20,361 genes
以人类 v38 蛋白编码 FASTA 为例，过滤后 FASTA 含有 52,059 个转录本、18,995 个基因，而原始 FASTA 为 106,143 个转录本、20,361 个基因。

These FASTAs also have a lot of information within the header lines eg.
>ENST00000641515.2|ENSG00000186092.7|OTTHUMG00000001094.4|OTTHUMT00000003223.4|OR4F5-201|OR4F5|2618|UTR5:1-60|CDS:61-1041|UTR3:1042-2618|
这些 FASTA 的头信息（header）通常非常冗长，例如上面这个例子。

The Reformatting_GENCODE_FASTA.py script extracts this extra information and saves it into csv files that are more easily read into R, while reformatting the FASTA to just contain the transcript ID. This makes downstream analysis simpler as only the transcript ID is carried forward following alignments.
Reformatting_GENCODE_FASTA.py 脚本会提取这些额外信息并写入更易于 R 读取的 CSV 文件，同时将 FASTA 的头重写为仅包含 transcript ID，从而在比对后的下游分析中只需携带 transcript ID。

It is recoemmended to use a filtered and reformatted FASTA file by running the above python scripts on a downloaded FASTA file. Note these scripts will only work on FASTA files downloaded from GENCODE.
推荐的做法是：先从 GENCODE 下载 FASTA，然后依次运行上述 Python 脚本获得过滤且重格式化的 FASTA。注意，这些脚本仅适用于从 GENCODE 下载的 FASTA。

## Processing totals (standard RNA-seq)
The RPFs will need to be aligned to a transcriptome that contains just one transcript per gene. The best way to deal with this issue is to select the most abundant transcript per gene. RSEM estimates relative expression of each isoform within each gene, which can therefore be used to select the most abundant transcript per gene. It can take a long time for RSEM to run (normally more than 24h), depending on the number of reads and the size of the transcriptome, so it is recommended that you start by processing the totals first.
在进行 RPF 分析时，需要将 reads 比对到「每个基因仅包含一个代表转录本」的转录组。最佳方式是先利用 RSEM 估计每个基因内各 isoform 的相对表达量，从而选出最丰的转录本。RSEM 运行时间可能较长（通常超过 24 小时，取决于 reads 数量和转录组大小），因此建议先从 totals（总 RNA‑seq）开始处理。

**Ensure you activate the RNAseq conda environment before running the RPF shell scripts, with the following command**
**在运行 RPF 相关 Shell 脚本之前，请先激活 RNAseq conda 环境，使用以下命令：**
```console
conda activate RNAseq
```
### Sequencing QC
Before processing any data it is important to use fastQC to see what the structure of the sequencing reads is.
在处理任何数据之前，先使用 fastQC 查看测序 reads 的结构非常重要。

**Totals_0_QC.sh** will run fastQC on all totals <.fastq> files and output the fastQC files into the fastQC directory.
**Totals_0_QC.sh** 会对所有 totals <.fastq> 文件运行 fastQC，并将结果输出到 fastQC 目录。

The output will tell you the number of reads for each <.fastq> file as well as some basic QC on the reads.
输出报告会给出每个 <.fastq> 的 reads 数量以及若干基础 QC 指标。

### Remove adaptors
The 3' adaptor used in the library prep will be sequenced immediately after the fragment (and UMIs if used). These therefore needs to be removed so that they do not affect alignment. The ***Totals_1_adaptor_removal.sh*** script uses cutadapt for this, which removes this sequence (specified in the common_variables.sh script) and any sequence downstream of this. It also trims low quality bases from the 3' end of the read below a certain quality score (user defined, we use q20) and removes reads that are shorter or longer than user defined values (we use 30nt).
建库过程中使用的 3' 接头（以及可选的 UMI）会紧接在片段之后被测序，为避免影响比对，需要去除这些序列。***Totals_1_adaptor_removal.sh*** 使用 cutadapt 完成这一操作：根据 common_variables.sh 中指定的接头序列去除 3' adaptor 及其下游所有碱基，同时从 3' 端剪切低质量碱基（质量阈值可自定义，这里使用 q20），并丢弃长度短于或长于指定值的 reads（此处使用 30nt）。

After cutadapt has finished, fastQC is run on the output <.fastq> files. **Visual inspection of these fastQC files is essential to check that cutadapt has done what you think it has**
cutadapt 运行完成后会对输出的 <.fastq> 再次运行 fastQC。**务必人工检查这些 fastQC 报告，确认 cutadapt 确实按预期完成了处理。**

### Alignment and de-duplication
If UMIs have been used in the library prep, PCR duplicates can be removed from the analysis, ensuring that all reads originated from unique mRNAs.
如果建库中使用了 UMI，可以在分析中去除 PCR duplicates，从而保证保留下来的 reads 尽可能代表不同的 mRNA 分子。

This is done in a two-step process using UMI-tools. First the UMI is extracted from the read and appended to the read name using ***Totals_2_extract_UMIs.sh*** script. The UMI structure needs to be set for this. For the CORALL Total RNA-Seq Library Prep Kit, these are 12nt at the 5' end of the read.
该步骤分两步通过 UMI-tools 完成：首先由 ***Totals_2_extract_UMIs.sh*** 从 reads 中提取 UMI 并附加到 read 名称中，需在脚本中设置 UMI 结构；以 CORALL Total RNA‑Seq Library Prep Kit 为例，UMI 为 read 5' 端的 12 个碱基。

Reads are then aligned to a reference transcriptome using the ***Totals_3a_align_reads_transcriptome.sh*** script, which uses bowtie2.
随后使用 ***Totals_3a_align_reads_transcriptome.sh*** 脚本调用 bowtie2，将 reads 比对到参考转录组。

UMI-tools is then used to de-duplicate the resulting BAM file with the ***Totals_4a_deduplication_transcriptome.sh*** script.
接着通过 ***Totals_4a_deduplication_transcriptome.sh*** 脚本调用 UMI-tools 对生成的 BAM 文件进行去重复。

**If the library prep did not include UMIs then *Totals_2_extract_UMIs.sh* and *Totals_4a_deduplication_transcriptome.sh* should be skipped. If this is the case you need to edit the file names of the input <.fastq> files in the** ***Totals_3a_align_reads_transcriptome.sh*** and ***Totals_5_isoform_quantification.sh*** **scripts.**
**如果建库没有使用 UMI，则应跳过 *Totals_2_extract_UMIs.sh* 和 *Totals_4a_deduplication_transcriptome.sh*，并在 ***Totals_3a_align_reads_transcriptome.sh*** 和 ***Totals_5_isoform_quantification.sh*** 中相应修改输入 <.fastq> 文件名。**

### Gene and isoform level quantification using RSEM
RSEM calculates predicted counts and tpms for every gene (.genes output) and every transcript within every gene (.isoforms output). This can be used as input into DESeq2 to do differential expression analysis. It can also be used to caluculate the most abundant transcript per gene. This is carried out with the ***Totals_5_isoform_quantification.sh*** script, which takes the de-duplicated BAM file as input.
RSEM 会为每个基因（.genes 输出）和每个基因内的每条转录本（.isoforms 输出）计算预测计数和 TPM，可作为 DESeq2 的输入用于差异表达分析，也可用于计算每个基因最丰的转录本。相关步骤由 ***Totals_5_isoform_quantification.sh*** 完成，该脚本以去重复后的 BAM 文件为输入。

**While it is strongly encouraged that the above scripts are used when using the pipeline for the first time or with some external data, the wrapper ***Totals_all.sh*** script combines all these into one script and can be used if the user is confident in doing so. Note that this script does not run fastQC on the intermediary files and does not have the same level of annotation as the above scripts.**
**对于首次使用本流程或处理外部数据，强烈建议按上述分步脚本执行；熟悉后可以考虑使用封装脚本 ***Totals_all.sh*** 将这些步骤合并执行。但需要注意，该脚本不会对中间文件运行 fastQC，且注释信息也少于分步脚本。**

### Align reads to genome using STAR (optional)
Aligning to the genome is also essential if you want to visualise the data with a genome browser such as IGV. We therefor also align the total RNA reads to a genome using STAR, using the ***Totals_3b_align_reads_genome.sh*** script and ***Totals_4b_deduplication_genome.sh*** scripts.
如果希望在 IGV 等基因组浏览器中可视化数据，将 reads 比对到基因组也很重要。为此，可以使用 STAR，将 totals reads 比对到基因组：对应脚本为 ***Totals_3b_align_reads_genome.sh*** 和 ***Totals_4b_deduplication_genome.sh***。

**It is recommended that you create a new conda environment, specifically for STAR, to install it within and run this script from within that environment.**
**推荐为 STAR 单独创建一个新的 conda 环境，在该环境中安装并运行上述脚本。**

### Calculating the most abundant transcript per gene
Using the RSEM as input, the ***calculate_most_abundant_transcript.R*** will create a csv file containing the most abundant transcripts (with a column for gene ID and symbol) and also a flat text file with just the transcript IDs. This flat text file needs to then be used as input to filter the protein coding fasta so that it only contains the most abundant transcripts. The ***Totals_6_write_most_abundant_transcript_fasta.sh*** will do this using the ***filter_FASTA.py*** script
以 RSEM 的结果为输入，***calculate_most_abundant_transcript.R*** 会生成一个包含最丰转录本的 CSV（带有 gene ID 和 symbol 列），以及一个只含 transcript ID 的纯文本文件。之后使用该文本文件作为输入，通过 ***Totals_6_write_most_abundant_transcript_fasta.sh*** 调用 ***filter_FASTA.py*** 过滤蛋白编码 FASTA，仅保留这些最丰转录本。

The ***Totals_6b_extract_read_counts.sh*** and it's ***paired Totals_read_counts.R*** scripts extract and plot QC based on the number of reads at each stage of the pipeline and alignment rates.
***Totals_6b_extract_read_counts.sh*** 及其配套的 ***Totals_read_counts.R*** 会提取并绘制各步骤的 reads 数量和比对率等 QC 统计信息。

## Processing RPFs
**Ensure you activate the RiboSeq conda environment before running the RPF shell scripts, with the following command**
**在运行 RPF 相关 Shell 脚本之前，请先激活 RiboSeq conda 环境，使用以下命令：**
```console
conda activate RiboSeq
```
### Sequencing QC
Before processing any data it is important to use fastQC to see what the structure of the sequencing reads is.
在处理任何 RPF 数据之前，先使用 fastQC 查看 reads 的结构同样非常重要。

**RPFs_0_QC.sh** will run fastQC on all RPF <.fastq> files and output the fastQC files into the fastQC directory.
**RPFs_0_QC.sh** 会对所有 RPF <.fastq> 文件运行 fastQC，并将结果输出到 fastQC 目录。

The output will tell you the number of reads for each <.fastq> file as well as some basic QC on the reads.
输出报告会显示每个 <.fastq> 的 reads 数量以及一些基础 QC 指标。

A good indication of whether the <.fastq> files have already been processed or not is the sequence length distribution. If no processing has been done, then all reads should be the same length, which will be the number of cycles used when sequenced. For example, if 75 cycles were selected when setting up the sequencing run, then all reads would be 75 bases long, even if the library fragment length was much shorter or much longer than this. Therefore, if for example with a standrad RPF library with 4nt UMIs on either end of the RPF, the fragment length will be roughly 30nt (RPF length) plus 8nt (UMIs) plus the length of the 3' adaptor. If the adaptors had already been removed prior to uploading the <.fastq> files to GEO, then the sequence length distribution will be a range of values, peaking at roughly 38. If the peak was closer to 30nt then it could be presumed that the UMIs had also been removed. The adaptor content will also give a good indication of this. For example, in the above example, if adaptors hadn't been removed, you should expect to see adaptor contamination coming up in the reads from roughly 38nts into the reads.
判断 <.fastq> 是否已经做过预处理的一个重要指标是序列长度分布：若完全未处理，所有 reads 长度应等于测序循环数（例如 75 cycles 对应 75bp）；以典型 RPF 文库为例，若两端各有 4nt UMI，则片段长度约为 30nt（RPF）+8nt（UMI）+3' adaptor 长度。若在上传 GEO 前已去接头，则长度分布会变成一段范围，峰值约在 38nt；若峰值靠近 30nt，则可能说明 UMI 也已去除。adaptor content 模块也能提供线索：若未去接头，应在约第 38nt 之后看到明显的 adaptor 污染信号。

### Remove adaptors
The 3' adaptor used in the library prep will be sequenced immediately after the fragment (and UMIs if used). These therefore needs to be removed so that they do not affect alignment. The ***RPFs_1_adaptor_removal.sh*** script uses cutadapt for this, which removes this sequence (specified in the common_variables.sh script) and any sequence downstream of this. It also trims low quality bases from the 3' end of the read below a certain quality score (user defined, we use q20) and removes reads that are shorter or longer than user defined values. For RPFs (~30) with 4nt UMIs at each end, we filter reads so that they are 30-50nt. If UMIs have been used then you need to set the minimum read length to 30nt as otherwise cd-hit-dup has issues de-duplicating the reads. If UMIs haven't been used, you will need to change these settings to 20-40.
建库中使用的 3' adaptor（以及可选的 UMI）会紧接片段之后被测序，为避免影响比对，需要去除这些序列。***RPFs_1_adaptor_removal.sh*** 通过 cutadapt 完成：根据 common_variables.sh 中指定的序列去除 3' adaptor 及其下游所有碱基，同时从 3' 端剪切低质量碱基（质量阈值可自定义，这里使用 q20），并丢弃长度不在设定范围内的 reads。对于长度约 30nt 且两端各有 4nt UMI 的 RPF，我们通常保留 30–50nt 的 reads；若使用 UMI，最小长度需设为 30nt，否则 cd-hit-dup 在去重复时会出问题；若未使用 UMI，建议将范围改为 20–40nt。

After cutadapt has finished, fastQC is run on the output <.fastq> files. **Visual inspection of these fastQC files is essential to check that cutadapt has done what you think it has**
cutadapt 完成后会对输出 <.fastq> 再次运行 fastQC。**务必人工检查这些 fastQC 报告，确认 cutadapt 的效果确实符合预期。**

### Alignment and de-duplication
If UMIs have been used in the library prep, PCR duplicates can be removed from the analysis, ensuring that all reads originated from unique RPFs.
如果建库使用了 UMI，可以去除 PCR duplicates，从而确保保留下来的 reads 尽可能代表不同的 RPF。

This is done in a two-step process using UMI-tools. First the UMI is extracted from the read and appended to the read name using ***RPFs_2_extract_UMIs.sh*** script. The UMI structure needs to be set for this. For the nextflex library prep kit, these are 4nt at either end of the read.
该过程分两步通过 UMI-tools 完成：首先由 ***RPFs_2_extract_UMIs.sh*** 从 reads 中提取 UMI 并附加到 read 名称中，需要指定 UMI 结构；以 nextflex 文库为例，UMI 为 read 两端各 4nt。

Reads are then aligned to a reference transcriptome using the ***RPFs_3_align_reads.sh*** script, which uses bbmap.
随后通过 ***RPFs_3_align_reads.sh*** 调用 bbmap 将 reads 比对到参考转录组。

The ***RPFs_3_align_reads.sh*** script uses bbmap to align reads first to the rRNAs and tRNAs. Each alignment will create two new <.fastq> files containing the reads that did and did not align. The reads that didn't align to either of these transcriptomes are then aligned to the protein coding transcriptome.
***RPFs_3_align_reads.sh*** 首先使用 bbmap 将 reads 比对到 rRNA 和 tRNA 转录组，每次比对会生成两个新的 <.fastq>：一个为成功比对的 reads，另一个为未比对的 reads；随后将未比对到上述转录组的 reads 再比对到蛋白编码转录组。

**It is very important to give some consideration to what transcriptome you use and how to handle multimapped reads.
It is strongly recommended that you use the total RNA-seq info to calculate the most abundant transcript per gene and filter a fasta file to include only these isoforms. This can be created as part of the Total_RNA pipeline (see above), by running ***calculate_most_abundant_transcript.R*** and then ***Totals_6_write_most_abundant_transcript_fasta.sh*****
**在选择参考转录组以及处理多重比对（multimapped）reads 时需要特别谨慎。强烈建议利用 totals RNA‑seq 信息计算每个基因最丰的转录本，并据此过滤 FASTA 只保留这些 isoform；可以在 totals 流程中通过运行 ***calculate_most_abundant_transcript.R*** 和 ***Totals_6_write_most_abundant_transcript_fasta.sh*** 来完成。**

It is also recommended that the protein coding transcriptome is first filtered to include;**
- only Havana protein coding transcripts
- that have both 5' and 3'UTRs
- which the CDS is equally divisble by 3, starts with a start codon and finishes with a stop codon
同样建议先对蛋白编码转录组做额外过滤，仅保留：
- HAVANA 标注的蛋白编码转录本
- 具有 5' 和 3' UTR 的转录本
- CDS 长度可被 3 整除，且以起始密码子开头、以终止密码子结束

This can be achieved with the ***Filtering_GENCODE_FASTA.py*** accessory script.
上述过滤可通过 ***Filtering_GENCODE_FASTA.py*** 附属脚本完成。

UMI-tools is then used to de-duplicate the resulting BAM file with the ***RPFs_4_deduplication.sh*** script.
之后通过 ***RPFs_4_deduplication.sh*** 调用 UMI-tools 对生成的 BAM 文件进行去重复。

**If the library prep did not include UMIs then *RPFs_2_extract_UMIs.sh* and *RPFs_4_deduplication.sh* should be skipped. If this is the case you need to edit the input file names in the** ***RPFs_3_align_reads.sh*** and ***RPFs_5_Extract_counts_all_lengths.sh*** **scripts.**
**若建库没有使用 UMI，则应跳过 *RPFs_2_extract_UMIs.sh* 和 *RPFs_4_deduplication.sh*，并在 ***RPFs_3_align_reads.sh*** 和 ***RPFs_5_Extract_counts_all_lengths.sh*** 中相应修改输入文件名。**

fastQC is used to inspect the QC and read length distribution at each of these three stages and of the different alignments. You would expect to see a nice peak of read lengths 28-32nt for the protein coding aligned reads but a wider distribition for the rRNA/unaligned reads (this should reflect the size you cut on the RNA extraction gel).
在上述三个阶段及各类比对结果中，可使用 fastQC 检查 QC 指标和长度分布：对蛋白编码转录组比对后的 reads，通常期望在 28–32nt 处看到一个尖锐峰；而 rRNA/未比对 reads 的长度分布则更宽，反映了 RNA 提取时在凝胶上截取的大小范围。

### Count reads
In order to do any downstream analysis, we need to know how many reads aligned to which mRNAs at which positions. Also for library QC it is important to be able to distinguish between different read lengths, as certain read lengths may be filtered to remove those reads that are less likely to be true RPFs.
为了进行下游分析，需要知道每条 mRNA 上各位置的 reads 数量；在文库 QC 中按 read 长度区分也同样重要，因为某些长度的 reads 可能被认为不是典型 RPF 而被过滤。

The ***counting_script.py*** script was adpated from the [RiboPlot package](https://pythonhosted.org/riboplot/ribocount.html). This script creates <.counts> files, which are plain text files in the following structure;
***counting_script.py*** 脚本改写自 [RiboPlot 包](https://pythonhosted.org/riboplot/ribocount.html)，用于生成 <.counts> 文件，这是一类纯文本文件，结构如下：

Transcript_1

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 150 20 34 85 34 58 75 22 27 85 53 24 85.....................................................

Transcript_2

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 103 10 37 83 24 57 45 28 7 89 43 26 55.....................................................

Transcript_3

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 87 20 34 85 34 48 79 12 19 75 51 14 95.....................................................


where each two lines represents one transcript, with the first of each two lines containg the transcript ID and the second of each two lines containing tab seperated values of the read counts that start at that position within the transcript. The number of values for each transcript should therefore match the length of that transcript.
每两行描述一个转录本：第一行是 transcript ID，第二行是从转录本起始位点开始、以制表符分隔的 read 起始计数；计数的个数应与该转录本的长度一致。

The ***RPFs_5_Extract_counts_all_lengths.sh*** uses the ***counting_script.py*** script to generate a <.counts> file for each sample for each read length defined in the for loop and stores all thes files in the Counts_files directory. This uses the sorted <.BAM> file as input and also needs the associated index <.BAI> file to be in the same directory. These are the input files for the downstream analysis.
***RPFs_5_Extract_counts_all_lengths.sh*** 使用 ***counting_script.py*** 为 for 循环中设定的每个 read 长度、每个样本生成一个 <.counts> 文件，并统一存放在 Counts_files 目录中。该脚本以排序后的 <.BAM> 及其索引 <.BAI> 文件为输入，这些 <.counts> 文件是后续分析的输入。
### Library QC
The ***RPFs_6a_summing_region_counts.sh; RPFs_6b_summing_spliced_counts.sh and RPFs_6c_periodicity.sh*** scripts utlise the custom python scripts, reading in the counts files generated above and creating <.csv> files that the ***region_counts.R; heatmaps.R; offset_plots.R and periodicity.R*** scripts use to generate the library QC plots. From these plots you should be able to determine whether the RPF libraries have the properties that would argue they are truelly RPFs. These are;
***RPFs_6a_summing_region_counts.sh***、***RPFs_6b_summing_spliced_counts.sh*** 和 ***RPFs_6c_periodicity.sh*** 等脚本会调用自定义 Python 脚本读取上述 <.counts> 文件并生成 <.csv>，供 ***region_counts.R***、***heatmaps.R***、***offset_plots.R*** 和 ***periodicity.R*** 等 R 脚本绘制文库 QC 图。通过这些图你可以判断 RPF 文库是否具有典型特征，例如：
- read length distribution peaking at 28-32nt
- strong periodicity
- strong enrichment of reads within the CDS and depletion of reads within the 3'UTR
- 长度分布在 28–32nt 处有明显峰
- 具有明显的三核苷酸周期性
- 在 CDS 区域显著富集，而在 3'UTR 中相对缺乏

From these plots you can then determine what read lengths you want to include in your downstream analysis for DE and codon level analyses.
根据这些图，你可以决定在差异表达分析和密码子水平分析中要保留哪些 read 长度。

The offset plots should also allow you to determine what to use for the offset. This is the value that you use in the ***RPFs_8_Extract_final_counts.sh*** so that the counts in the final <.counts> files are referring to the position within each transcript which is the first nt of the codon positioned within the P-site of the ribosome which was protecting that RPF, rather than the start of the read. This can be determined from the position at which the first peak of reads is observed just upstream of the start codon, as these reads correspond to RPFs which were protected by ribosomes with the P-site situated at the start codon. This is typically 12-13nt, but it is likely that different read lengths will require slightly different offsets.
offset 图还能帮助确定 P‑site 偏移量（offset）。在 ***RPFs_8_Extract_final_counts.sh*** 中使用该值，可将计数位置从 read 起始转换为对应 RPF 所在核糖体的 P‑site 密码子第一个核苷酸位置。offset 通常可通过观察起始密码子上游首个 read 峰值位置来确定（这些 reads 对应 P‑site 位于起始密码子的 RPF），典型值在 12–13nt 不等，不同 read 长度可能需要略微不同的 offset。

The ***RPFs_6d_extract_read_counts.sh*** and it's ***paired RPF_read_counts.R*** scripts extract and plot QC based on the number of reads at each stage of the pipeline and alignment rates.
***RPFs_6d_extract_read_counts.sh*** 及其配套的 ***RPF_read_counts.R*** 会提取并绘制各步骤的 reads 数量和比对率等 QC 统计。

**While it is strongly encouraged that the above scripts are used when using the pipeline for the first time or with some external data, the wrapper ***RPFs_all.sh*** script combines all these into one script and can be used if the user is confident in doing so. Note that this script does not run fastQC on the intermediary files and does not have the same level of annotation as the above scripts.**
**与 totals 部分类似，首次使用本流程或处理外部数据时强烈建议按上述分步脚本执行；熟悉后可以使用封装脚本 ***RPFs_all.sh*** 将这些步骤合并，但该脚本不会对中间文件运行 fastQC，且注释信息较少。**

### Extract final counts
Once you know what read lengths and offsets to use, you can use these values with the ***RPFs_7_Extract_final_counts.sh*** script to create a final <.counts> file that contains only the specified read lengths with the specified offsets applied.
在确定要使用的 read 长度范围和 offset 后，可在 ***RPFs_7_Extract_final_counts.sh*** 中设置这些值，生成仅包含指定 read 长度并应用对应 offset 的最终 <.counts> 文件。

### Summing CDS counts
The ***RPFs_8a_CDS_counts.sh*** uses the ***summing_CDS_counts.py*** to sum all the read counts that are within the CDS. **This will be the input into DESeq2.**
***RPFs_8a_CDS_counts.sh*** 使用 ***summing_CDS_counts.py*** 汇总落在 CDS 区域内的所有 read 计数，**该结果将作为 DESeq2 的输入。**

The *summing_CDS_counts.py* has an option to remove the first 20 and last 10 codons, which is recommended (and set as default in *RPFs_8a_CDS_counts.sh* script) to avoid biases at the start and stop codons, essentially meaning that only activly elongating ribosomes are counted.
*summing_CDS_counts.py* 可以选择去除 CDS 前 20 个和后 10 个密码子（在 *RPFs_8a_CDS_counts.sh* 中默认启用），以减小起始和终止密码子附近的偏倚，本质上只统计处于活跃延伸阶段的核糖体。

There is also the option to only include reads that are in frame. However, although periodicty indicates that the majority of the reads are truely RPFs, it doesn't neccessarily mean that those reads that are not in frame are not RPFs and the majority of the reads in the CDS will most likely be RPFs. **It is therefore recommended to include reads in all frames for DE analysis. For codon level analyses, only reads in frame should be used as it is not possible to confidently determine codon level resolution with high confidence for reads not in frame.**
脚本也可以选择只保留 in‑frame 的 reads。然而，尽管周期性表明大多数 reads 是真实 RPF，但 out‑of‑frame 的 reads 并不一定全是噪音，CDS 区域的大部分 reads 依然很可能是 RPF。**因此推荐在 DE 分析中包含所有 reading frame 的 reads，而在密码子水平分析中仅保留 in‑frame 的 reads，因为对 out‑of‑frame reads 很难高置信度地解读到具体密码子层面。**

### Summing 5'UTR counts
You may also want to count the reads within the 5'UTR to look at translation within upstream Open Reading Frames (uORFs). The ***RPFs_8b_UTR5_counts.sh*** uses the ***summing_UTR5_counts.py*** to sum all the read counts that are within the 5'UTR. Note that this counts all reads within the whole 5'UTR, not specific for individual uORFs.
如果你希望分析上游开放阅读框（uORFs）的翻译情况，可以统计 5'UTR 中的 reads。***RPFs_8b_UTR5_counts.sh*** 调用 ***summing_UTR5_counts.py*** 汇总 5'UTR 全长的 read 计数，注意这是一整个 5'UTR 的总计，并非针对单个 uORF 的精细统计。

### Counts to csv
In order to read in counts files into R, it is easier to have them written as csv files. ***RPFs_8c_counts_to_csv.sh*** will do this
为了在 R 中更方便地读取 counts 文件，通常先将它们转为 CSV 格式，***RPFs_8c_counts_to_csv.sh*** 可完成这一转换。

### Counting codon occupancy
The ***RPFs_8d_count_codon_occupancy.sh*** uses the ***count_codon_occupancy.py*** to determine which codon was positioned at the A,P and E-site plus two codons either side, for every RPF read and sum them all together. The ***codon_occupancy.R*** script then takes this data and uses it to measure relative elongation rates for each codon based on the number of RPFs where that codon was at the A-site compared to the number of RPFs where that codon was at either of the 7 sites described above. This therefore accounts for differing mRNA abundances and initiation rates transcriptome-wide.
***RPFs_8d_count_codon_occupancy.sh*** 调用 ***count_codon_occupancy.py***，对每条 RPF read 判定其 A、P、E 位点以及前后各两个密码子所对应的三联体，并累积所有 reads 的占据情况；***codon_occupancy.R*** 则使用这些数据，根据某密码子处于 A‑site 时的 RPF 数量与该密码子位于上述 7 个位置任一时的总 RPF 数量比较，估计该密码子的相对延伸速率，从而在全转录组范围内同时考虑不同 mRNA 的丰度和起始速率差异。

**Once you are happy that the data has been processed properly you can delete the intermediary files that are no longer required**
**当你确认数据已被正确处理并完成所有需要的 QC 后，可以删除不再需要的中间文件。**

**Do not delete the raw <.fastq> files**
**但请务必保留原始 <.fastq> 文件，不要删除。**

# Common troubleshooting
### remove \r end lines
The end of line character for windows is \r but for linux and mac it is \n. Sometimes, when you open a script on your PC in a text editor it will automatically add both \n and \r to the end of any new lines created. However, as the shell scripts are intended to be run on a linux/mac platform, this will cause issues and will return the following error message.
Windows 的行结束符是 \r，而 Linux 和 mac 的行结束符是 \n。有时在 Windows 上用文本编辑器打开脚本并编辑时，会在新行末尾自动添加 \n 和 \r。但这些 Shell 脚本是用于 Linux/mac 平台的，此类行结束符会导致脚本运行失败，并出现如下错误：

***/usr/bin/env: ‘bash\r’: No such file or directory***

To check if this is the case, in notepad++ select View->Show symbol->Show all characters to see hidden characters. If \r characters have been added to the end of lines, use find and replace (with regular expressions ticked) to remove them all, leaving just \n characters in their place
要检查是否存在这个问题，可以在 Notepad++ 中选择 View->Show symbol->Show all characters 显示所有隐藏字符；若看到行尾出现 \r，可使用查找替换（勾选正则表达式）将所有 \r 删除，仅保留 \n。
### check the path to directories is right
The path to the parent directory needs to be set in both the common_variables.sh and the common_variables.R scripts. Although these should point to the same directory, the path will be slightly different as the path in the shell script needs to be the linux path and the path for the R script needs to be the PC path.
父目录路径需要在 common_variables.sh 和 common_variables.R 两个脚本中都进行设置；它们应指向同一目录，但写法略有不同：Shell 脚本中使用 Linux 路径，而 R 脚本中使用 PC 端路径。

- To find the linux path, go to that directory in the terminal and use pwd to see what the full path is and then copy this into the shell script
- 获取 Linux 路径时，在终端进入该目录并运行 pwd，然后将输出的完整路径复制到 Shell 脚本中。
- To find the PC path, open R studio by doubleclicking on the common_variables.R script and use the getwd() function to find the current working directory. The parent directory will be a couple of directories up from this
- 获取 PC 路径时，可在文件管理器中双击 common_variables.R 打开 RStudio，通过 getwd() 函数查看当前工作目录，父目录通常在其上两级左右。 
