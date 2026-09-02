# Ribo-seq 分析流程运行指南

本指南详细介绍了如何使用 `run.sh` 脚本高效运行 Ribo-seq 分析流程。该脚本整合了 RPFs、Totals 和 Downstream 分析的各个步骤，并提供了环境管理功能，简化了操作流程。

仓库本身只存放代码与文档，**测试数据与参考数据均不随仓库分发**（已在 `.gitignore` 中忽略），需要按下面说明自行下载或重建。建议按顺序：先准备[测试数据](#1-测试数据)与[参考数据](#2-参考数据)，再按[依赖安装](#3-依赖安装)建好环境，最后通过 `run.sh` 运行（见[4 环境配置](#4-环境配置)～[7 运行顺序](#7-运行顺序)）。

## 1. 测试数据

本仓库的测试数据是 GEO 数据集 GSE182201（RNA-seq + Ribo-seq）中部分样本经 **chr20 抽样**（down-sample）得到的子集 FASTQ，样本清单见 `info.csv`。

### 数据来源

- 子集 FASTQ（与 `info.csv` 一一对应）来自 [nf-core/test-datasets](https://github.com/nf-core/test-datasets/tree/riboseq) 的 `riboseq` 分支，目录 `testdata/GSE182201/`；
- 完整数据集（含全部样本的 RNA-seq 与 Ribo-seq 原始数据）来自 [GEO: GSE182201](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE182201)（PM2.5 处理下的人支气管上皮细胞）。

### 方式一：从 nf-core/test-datasets 直接下载（推荐）

在仓库根目录执行以下命令，将 FASTQ 下载到 `GSE182201/`（文件名与 `info.csv` 一致）：

```bash
base="https://raw.githubusercontent.com/nf-core/test-datasets/riboseq/testdata/GSE182201"
mkdir -p GSE182201
awk -F, 'NR>1{print $2; if ($3!="") print $3}' info.csv \
  | sort -u \
  | while read -r f; do
      wget -P GSE182201 "$base/$(basename "$f")"
    done
```

### 方式二：从 GEO 完整数据自行制作

1. 从 [GSE182201](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE182201) 下载所需样本的原始 FASTQ 并完成比对；
2. 将比对上 chr20 的 reads 取回并与原始 FASTQ 对照抽样，得到测试子集。制作流程可参考 nf-core/test-datasets 同分支下的 [`testdata/make_test_data.sh`](https://github.com/nf-core/test-datasets/blob/riboseq/testdata/make_test_data.sh)。

## 2. 参考数据

Ribo-seq 流程运行需要参考序列与比对索引，同样不随仓库分发；仓库仅保留制作 chr20 参考子集的脚本 [test/extract_chr20_transcripts.py](test/extract_chr20_transcripts.py)。

`Shell_scripts/common_variables.sh` 中默认路径均为 `reference/...`（可通过环境变量 `RIBO_SEQ_FASTA_DIR`、`RIBO_SEQ_*` 系列覆盖，指向仓库外独立的参考目录），需按下述结构自行准备：

### 目录结构（运行测试数据所需）

```
reference/
├── GENCODE/
│   └── v49/                                  # human GENCODE release 49, chr20 子集
│       ├── gencode.v49.dna_chr20.fa(.gz)     # chr20 基因组序列（STAR 比对用）
│       ├── gencode.v49.annotation_chr20.gtf  # chr20 注释（STAR 索引及计数用）
│       ├── gencode.v49.pc_transcripts_chr20.fa           # chr20 蛋白编码转录本
│       ├── gencode.v49.pc_transcripts_chr20_reformatted.fa
│       ├── gencode.v49.pc_transcripts_chr20_filtered.fa  # RPFs 比对用转录组（bbmap）
│       ├── gencode.v49.pc_translations_chr20.fa(.reformatted.fa)
│       ├── transcript_info/                  # Reformatting 脚本输出的 csv
│       │   └── gencode.v49.pc_transcripts_chr20_{gene_IDs,protein_IDs,region_lengths}.csv
│       ├── rsem_bowtie2_index/               # RSEM(bowtie2) 索引，本地生成
│       └── STAR_index/                       # STAR 索引，本地生成
├── rRNA/sortmerna_rrna.fasta                 # rRNA 序列（bbmap 过滤核糖体 RNA）
└── tRNA/hg38-mature-tRNAs-dna.fasta          # 人成熟 tRNA 序列（bbmap 过滤 tRNA）
```

### 数据来源

| 文件 | 来源 |
| :--- | :--- |
| GENCODE v49 系列 | [GENCODE Human Release 49](https://www.gencodegenes.org/human/release_49.html)（原始文件也见 [GENCODE FTP](https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/)） |
| `sortmerna_rrna.fasta` | [sortmerna](https://github.com/biocore/sortmerna) 自带 rRNA 数据库（`data/rRNA_databases/`，拼接而成） |
| `hg38-mature-tRNAs-dna.fasta` | [GtRNAdb Hsapi38](http://gtrnadb.ucsc.edu/genomes/eukaryota/Hsapi38/Hsapi38-seq.html) |
| chr20 测试 FASTQ | 见上文[测试数据](#1-测试数据)（属测试数据，不属于参考数据） |

### 重建步骤

**1) GENCODE v49 chr20 子集**

1. 下载 GENCODE v49 原始文件（解压后使用）：
   - `gencode.v49.annotation.gtf.gz`
   - `GRCh38.primary_assembly.genome.fa.gz`
   - `gencode.v49.pc_transcripts.fa.gz`、`gencode.v49.pc_translations.fa.gz`
2. 用保留脚本按 chr20 提取转录本/翻译序列（输出放到 `reference/GENCODE/v49/`）：
   ```bash
   python3 test/extract_chr20_transcripts.py \
       --gtf   gencode.v49.annotation.gtf \
       --fasta gencode.v49.pc_transcripts.fa \
       --output reference/GENCODE/v49/gencode.v49.pc_transcripts_chr20.fa \
       --chrom 20
   ```
3. 基因组序列与 GTF 只需按染色体行提取 chr20（用 `awk`/`samtools faidx`/`seqkit` 等工具即可）。
4. 后续 `*_reformatted.fa`、`*_filtered.fa`、`transcript_info/*.csv` 由
   [Python_scripts/Reformatting_GENCODE_FASTA.py](Python_scripts/Reformatting_GENCODE_FASTA.py) 与
   [Python_scripts/Filtering_GENCODE_FASTA.py](Python_scripts/Filtering_GENCODE_FASTA.py) 生成
   （这两个脚本只适用于 GENCODE 格式 FASTA，详见下文英文部分 "FASTA file" 一节）。

**2) rRNA / tRNA**

- `sortmerna_rrna.fasta`：下载 [sortmerna](https://github.com/biocore/sortmerna) 的 rRNA 数据库后拼接；
- `hg38-mature-tRNAs-dna.fasta`：从 [GtRNAdb](http://gtrnadb.ucsc.edu/genomes/eukaryota/Hsapi38/Hsapi38-seq.html) 下载 human hg38 mature tRNA 序列。

**3) 比对索引**

`run.sh` 每次运行前会自动调用 `Shell_scripts/check_and_build_indices.sh`：当检测到 `rsem_bowtie2_index` 或 `STAR_index` 缺失时，会基于上述 FASTA/GTF 自动构建，无需手工操作。如需手动构建：

```bash
# RSEM (bowtie2) 索引
rsem-prepare-reference --bowtie2 --num-threads 4 \
    reference/GENCODE/v49/gencode.v49.pc_transcripts_chr20_filtered.fa \
    reference/GENCODE/v49/rsem_bowtie2_index/gencode.v49.pc_transcripts_filtered

# STAR 索引
STAR --runMode genomeGenerate --runThreadN 4 \
    --genomeDir reference/GENCODE/v49/STAR_index \
    --genomeFastaFiles reference/GENCODE/v49/gencode.v49.dna_chr20.fa \
    --sjdbGTFfile reference/GENCODE/v49/gencode.v49.annotation_chr20.gtf \
    --sjdbOverhang 100
```

### 注意事项

- 对完整（非 chr20 测试）项目，建议把参考序列与索引放到独立的参考目录（不放在仓库内），再通过 `RIBO_SEQ_FASTA_DIR` 等环境变量或直接修改 `common_variables.sh` 指定路径。
- `.gitignore` 已忽略 `reference/` 下所有可重建的数据文件，避免误提交大文件。

## 3. 依赖安装

本流程分为三类运行环境：**RiboSeq**（RPFs）、**RNAseq**（Totals）与 **R_analysis**（Downstream）。仓库根目录提供了三个可直接使用的 Conda 环境定义文件：

| 环境定义文件 | 环境名 | 用途 |
| :--- | :--- | :--- |
| `RiboSeq_env.yml` | RiboSeq | 处理 RPFs（fastqc, cutadapt, umi_tools, bbmap, samtools, pysam, biopython 等） |
| `RNAseq_env.yml` | RNAseq | 处理 Totals / 常规 RNA-seq（额外含 rsem, bowtie2, star, bioconductor-tximport 等） |
| `R_analysis_env.yml` | R_analysis | 下游统计分析与绘图（DESeq2, tximport, fgsea, rrvgo 等） |

推荐直接用 `conda env create -f <文件>` 创建（创建后 `conda activate` 即可用）：

```console
conda env create -f RiboSeq_env.yml
conda env create -f RNAseq_env.yml
conda env create -f R_analysis_env.yml
```

### 手工创建环境（可选）

以下为手工逐步安装命令（适用于不想用 yml、或需要按历史版本约束精确安装的情况）。
**不要一次性把多行粘贴进终端，部分命令会要求交互确认（如输入 y 继续）。**

先安装 Conda/Mamba：[conda 安装说明](https://conda.io/projects/conda/en/latest/user-guide/install/linux.html)。更多参考见 [Getting started with conda](https://towardsdatascience.com/getting-started-with-python-environments-using-conda-32e9f2779307) 与 [Conda cheat sheet](https://docs.conda.io/projects/conda/en/4.6.0/_downloads/52a95608c49671267e40c689e0bc00ca/conda-cheatsheet.pdf)。

**RiboSeq 环境（处理 RPFs）**——依赖 fastQC、cutadapt、UMI-tools、bbmap、SAMtools(需 v1.9)、pysam、biopython：

```console
conda create --name RiboSeq
conda activate RiboSeq
conda install -c bioconda fastqc
conda install -c bioconda cutadapt
conda install -c bioconda umi_tools
conda install -c bioconda bbmap
conda install -c bioconda samtools=1.9
conda install -c bioconda pysam
conda install -c anaconda biopython
conda deactivate
```

**RNAseq 环境（处理 Totals）**——额外使用 RSEM + bowtie2（也可用 STAR）。RSEM 会顺带安装 samtools，需强制固定为 1.9，避免 `libcrypto.so.1.0.0` 加载错误；bowtie2 安装时曾出现需要把 tbb 降级到 2020.2 的问题（见 [biostars 讨论](https://www.biostars.org/p/494922/)）：

```console
conda create --name RNAseq
conda activate RNAseq
conda install -c bioconda fastqc
conda install -c bioconda cutadapt
conda install -c bioconda umi_tools
conda install -c bioconda rsem
conda install -c bioconda samtools=1.9 --force-reinstall
conda install -c bioconda bowtie2
conda install tbb=2020.2
conda install -c bioconda bbmap
conda install -c anaconda biopython
conda deactivate
```

## 4. 环境配置

本流程支持 **Conda** 和 **Local** 两种环境模式。

### Conda 模式 (默认/推荐)
在此模式下，`run.sh` 会自动检查并激活相应的 Conda 环境。请先按[第 3 节](#3-依赖安装)创建以下环境：
- **RiboSeq**: 用于 RPFs 流程
- **RNAseq**: 用于 Totals 流程
- **R_analysis**: 用于 Downstream 流程

### Local 模式
如果您希望使用系统自带的工具或已在当前 Shell 中手动激活了环境，请使用 `--env-mode local` 参数。
在此模式下，脚本不会尝试激活 Conda 环境，而是直接调用系统 PATH 中的工具。请确保所有必要的工具（如 `fastqc`, `cutadapt`, `Rscript` 等）均可用。

## 5. 运行方法

### 基础用法
```bash
./run.sh --pipeline [RPFs|Totals|Downstream] [选项]
```

### 常用命令示例

**1. 运行 RPFs 完整流程 (使用 Conda 环境)**
```bash
./run.sh --pipeline RPFs
```

**2. 运行 Totals 完整流程 (使用 Local 环境)**
```bash
./run.sh --pipeline Totals --env-mode local
```

**3. 运行 Downstream 分析**
```bash
./run.sh --pipeline Downstream
```

**4. 查看特定流程的步骤列表**
```bash
./run.sh --pipeline RPFs --list-steps
```

**5. 仅运行特定步骤**
例如，仅运行 RPFs 流程中的接头去除步骤：
```bash
./run.sh --pipeline RPFs --step RPFs_1_adaptor_removal.sh
```

## 6. 详细参数说明

| 参数 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `--pipeline` | **[必选]** 选择要运行的流程: `RPFs`, `Totals`, `Downstream` | - |
| `--env-mode` | 环境模式: `conda` (自动激活环境) 或 `local` (使用当前环境) | `conda` |
| `--step` | 仅运行指定步骤的脚本 (例如 `RPFs_1_adaptor_removal.sh`) | 运行所有步骤 |
| `--list-steps`| 列出所选流程的所有可用步骤并退出 | - |
| `--output-dir`| 指定输出目录 | `./results` |
| `--input-csv` | 指定样本信息文件 | `./info.csv` |
| `--threads` | 线程数 | `4` |
| `--rpf-adaptor` | RPF 接头序列 | `TGGAATTCTCGGGTGCCAAGG` |
| `--totals-adaptor` | Totals 接头序列 | `AGATCGGAAGAG` |

## 7. 运行顺序

`run.sh` 会按照预定义的顺序依次执行脚本。
- **RPFs 流程**: QC -> 接头去除 -> UMI 提取 -> 比对 -> 去重 -> 计数 -> 汇总
- **Totals 流程**: QC -> 接头去除 -> UMI 提取 -> 比对 -> 去重 -> 定量
- **Downstream 流程**: 各种 R 语言统计分析与绘图脚本

建议初次运行时使用默认设置跑通完整流程。

## 8. GSEA 基因集来源（MSigDB）

下游 GSEA（fgsea）分析使用的人源（human）基因集 `.gmt` 文件存放在
[R_scripts/gsea/MSigDB/](R_scripts/gsea/MSigDB/)，版本为 **v2026.1**，包含：
Hallmark（`h.all`）、KEGG（`c2.cp.kegg_legacy` / `c2.cp.kegg_medicus`）、
GO 生物过程 / 细胞组分 / 分子功能（`c5.go.bp` / `c5.go.cc` / `c5.go.mf`）。

- 来源：[MSigDB Collections - Human](https://www.gsea-msigdb.org/gsea/msigdb/human/collections.jsp)；
  在 MSigDB 官网注册账号后即可免费下载对应的 `.gmt` 文件；
- 如需更新或改用其他版本，请保持文件名与
  [read_human_GSEA_pathways.R](R_scripts/gsea/read_human_GSEA_pathways.R)
  中匹配的模式一致（`h.all.*`、`c5.(go.)?bp|mf|cc.*`、`c2.cp.kegg.*` 等）。

---

# Ribo-seq
This analysis pipeline processes sequencing data from both Ribosome Protected Footprints (RPFs) and the associated total RNA-seq for Ribosome-footprinting data.

**Please ensure you read the following instructions carefully before running this pipeline.**

## Dependencies
Make sure you have all dependencies installed by following the instructions in the [依赖安装](#3-依赖安装) section above (the original upstream instructions are also available [here](https://github.com/Bushell-lab/Ribo-seq/tree/main/Installation)).

## Pipeline
This pipeline is intended for use for people with basic bioinformatic skills. It is intended so that individual scripts can be easily edited to reflect the needs and choices of the user.
It uses custom shell scripts to call external programs and custom python scripts, to process the data. The processed data can then be used as input into the custom R scripts to either generate library QC plots, perform differential expression (DE) analysis with DEseq2 or to determine positional enrichment of ribosome occupancy across the length of the mRNA.

### Shell scripts
The shell scripts <.sh> are designed to serve as a template for processing the data but require the user to modify them so that they are specific to each experiment. This is because different library prep techniques are often used, such as the use of different **adaptor sequences** or the use of **UMIs**. It is therefore essential that the user knows how the libraries were prepared before starting the analysis. If this is their own data then this should already be known, but for external data sets this is often not as straight forward as expected. Also, it can be unclear whether the data uploaded to GEO is the raw unprocessed <.fastq> files or whether initial steps such as adaptor removal or de-duplication and UMI removal have already been carried out. This is why each processing step is carried out seperately and why the output from these steps is checked with fastQC, so it is essential that the user checks these files by visual inspection after each step, so that the user can be certain that the step has processed the data as expected. Each shell script has annotation at the top describing what the script does and which parts might need editing. **It is therefore strongly recommended that the user opens up each shell script and reads and understands them fully before running them**

### R scripts
The R scripts will read in the processed data generated from the custom python scripts and generate plots and perform DE analysis. These shouldn't need to be edited as the final processed data should be in a standard format, although the user is free to do what they wish with these and change the styles of the plots or add further analyses/plots should they wish. The common_variables.R (see below) script will need to be edited to add the filenames and path to the parent directory, as well as the read lengths that they wish to inspect with the library QC plots. The common_variables.R script needs to be in the current working directory when running the other <.R> scripts.

### Python scripts
The <.py> python scripts should not need to be edited. These can be used for multiple projects and so it is recommended that these are placed in a seperate directory. If you set the $PATH to this directory, they can be called from any directory and therefore be used for all Ribo-seq analyses. To do this you need to open the .bashrc file from your home directory with the following lines of code;
```console
cd
nano .bashrc
```
Then within the file add the following line
export PATH=$PATH:path/to/python_scripts/folder
This will add the folder to the path but only upon opening up a new terminal window. To check it's worked, open up a new terminal and run
```console
echo $PATH
```

## Setting up the project
- Before running any scripts, create a new directory for the experiment. This will be the parent directory which will contain all raw and processed data for the experiment as well as any plots generated.
- Then create a folder within this directory to place all the shell <.sh> and R <.R> scripts from this GitHub repository. Ensure the $PATH is set to the directory cotaining all the <.py> scripts from this repository.
- There is a common_variables.sh and common_variables.R script that will both need to be edited before running any of the other scripts. The filenames for both the RPF and Totals <.fastq> files (without the <.fastq> extension) will need to be added, as well as the path to the parent directory and the adaptor sequences. The path to the FASTA files and RSEM index which will be used for mapping also needs to be added. These should be common between all projects from the same species so should be stored in a seperate directory from the project directory.
- A region lengths <.csv> file that contains ***transcript_ID, 5'UTR length, CDS length, 3'UTR length*** in that stated order without a header line, for all transcripts within the protein coding FASTA is also required and the common_variables.sh script needs to point to this file.
- Once the common_variables.sh script has been completed, run the ***makeDirs.sh*** to set up the file structure to store all raw and processed data within the parent directory. Alternativly you can create these directories manually without the command line.
- **It is highly recommended that this data structure is followed as the scripts are designed to output the data in these locations and this makes it much easier for other people to understand what has been done and improves traceability. The filenames are also automatically generated within each script and should contain all important information. Again it is highly recommended that this is not altered for the same reasoning.**
- Once the directories have been set up, the raw <.fastq> files need to be written to the fastq_files directory. If these already exist, then simply copy them across. If these need to be downloaded from GEO, then use the ***download_fastq_files.sh*** script to download these, ensuring they get written to the fastq_files directory. If this is your own data and you have the raw bcl sequencing folder, you will need to de-mulitplex and write the <.fastq> files. Use the ***demultiplex.sh*** script for this, which uses bcl2fastq (needs to be downloaded with conda), again writing the <.fastq> files to the fastq_files directory. These <.fastq> files will be the input into the ***RPFs_0_QC.sh*** and ***RPFs_1_adaptor_removal.sh*** scripts, so check that that extensiones match. It is fine if these files are <.gz> compressed as both fastQC and cutadapt can use compressed files as input, but again make sure that the shell scripts have the .gz extension included. 

## FASTA file
It is up to the user to decide what FASTA file to use for alignments.

Protein coding FASTAs can be downloaded from the GENCODE website for mouse and human transcriptomes. It should be noted however that these possess a large number of transcripts that do not contain UTRs and have CDSs that are not equally divisible by 3, therefore are unlikely to be correctly annotated and/or undergo cap-dependent translation.

The Filtering_GENCODE_FASTA.py script will
- ensures the transcript has been manually annotated by HAVANA
- ensure the transcript has both a 5' and 3'UTR
- ensure the CDS is equally divisible by 3
- ensure the CDS starts with an nUG start codon
- ensure the CDS ends with a stop codon
- remove any PAR_Y transcripts

When this is run on the human v38 protein-coding FASTA, the filtered FASTA has 52,059 transcripts from 18,995 genes, whereas the original FASTA had 106,143 transcripts from 20,361 genes

These FASTAs also have a lot of information within the header lines eg.
>ENST00000641515.2|ENSG00000186092.7|OTTHUMG00000001094.4|OTTHUMT00000003223.4|OR4F5-201|OR4F5|2618|UTR5:1-60|CDS:61-1041|UTR3:1042-2618|

The Reformatting_GENCODE_FASTA.py script extracts this extra information and saves it into csv files that are more easily read into R, while reformatting the FASTA to just contain the transcript ID. This makes downstream analysis simpler as only the transcript ID is carried forward following alignments.

It is recoemmended to use a filtered and reformatted FASTA file by running the above python scripts on a downloaded FASTA file. Note these scripts will only work on FASTA files downloaded from GENCODE.

## Processing totals (standard RNA-seq)
The RPFs will need to be aligned to a transcriptome that contains just one transcript per gene. The best way to deal with this issue is to select the most abundant transcript per gene. RSEM estimates relative expression of each isoform within each gene, which can therefore be used to select the most abundant transcript per gene. It can take a long time for RSEM to run (normally more than 24h), depending on the number of reads and the size of the transcriptome, so it is recommended that you start by processing the totals first.

**Ensure you activate the RNAseq conda environment before running the RPF shell scripts, with the following command**
```console
conda activate RNAseq
```
### Sequencing QC
Before processing any data it is important to use fastQC to see what the structure of the sequencing reads is.

**Totals_0_QC.sh** will run fastQC on all totals <.fastq> files and output the fastQC files into the fastQC directory.

The output will tell you the number of reads for each <.fastq> file as well as some basic QC on the reads.

### Remove adaptors
The 3' adaptor used in the library prep will be sequenced immediately after the fragment (and UMIs if used). These therefore needs to be removed so that they do not affect alignment. The ***Totals_1_adaptor_removal.sh*** script uses cutadapt for this, which removes this sequence (specified in the common_variables.sh script) and any sequence downstream of this. It also trims low quality bases from the 3' end of the read below a certain quality score (user defined, we use q20) and removes reads that are shorter or longer than user defined values (we use 30nt).

After cutadapt has finished, fastQC is run on the output <.fastq> files. **Visual inspection of these fastQC files is essential to check that cutadapt has done what you think it has**

### Alignment and de-duplication
If UMIs have been used in the library prep, PCR duplicates can be removed from the analysis, ensuring that all reads originated from unique mRNAs.

This is done in a two-step process using UMI-tools. First the UMI is extracted from the read and appended to the read name using ***Totals_2_extract_UMIs.sh*** script. The UMI structure needs to be set for this. For the CORALL Total RNA-Seq Library Prep Kit, these are 12nt at the 5' end of the read.

Reads are then aligned to a reference transcriptome using the ***Totals_3a_align_reads_transcriptome.sh*** script, which uses bowtie2.

UMI-tools is then used to de-duplicate the resulting BAM file with the ***Totals_4a_deduplication_transcriptome.sh*** script.

**If the library prep did not include UMIs then *Totals_2_extract_UMIs.sh* and *Totals_4a_deduplication_transcriptome.sh* should be skipped. If this is the case you need to edit the file names of the input <.fastq> files in the** ***Totals_3a_align_reads_transcriptome.sh*** and ***Totals_5_isoform_quantification.sh*** **scripts.**

### Gene and isoform level quantification using RSEM
RSEM calculates predicted counts and tpms for every gene (.genes output) and every transcript within every gene (.isoforms output). This can be used as input into DESeq2 to do differential expression analysis. It can also be used to caluculate the most abundant transcript per gene. This is carried out with the ***Totals_5_isoform_quantification.sh*** script, which takes the de-duplicated BAM file as input.

**While it is strongly encouraged that the above scripts are used when using the pipeline for the first time or with some external data, the wrapper ***Totals_all.sh*** script combines all these into one script and can be used if the user is confident in doing so. Note that this script does not run fastQC on the intermediary files and does not have the same level of annotation as the above scripts.**

### Align reads to genome using STAR (optional)
Aligning to the genome is also essential if you want to visualise the data with a genome browser such as IGV. We therefor also align the total RNA reads to a genome using STAR, using the ***Totals_3b_align_reads_genome.sh*** script and ***Totals_4b_deduplication_genome.sh*** scripts.

**It is recommended that you create a new conda environment, specifically for STAR, to install it within and run this script from within that environment.**

### Calculating the most abundant transcript per gene
Using the RSEM as input, the ***calculate_most_abundant_transcript.R*** will create a csv file containing the most abundant transcripts (with a column for gene ID and symbol) and also a flat text file with just the transcript IDs. This flat text file needs to then be used as input to filter the protein coding fasta so that it only contains the most abundant transcripts. The ***Totals_6_write_most_abundant_transcript_fasta.sh*** will do this using the ***filter_FASTA.py*** script

The ***Totals_6b_extract_read_counts.sh*** and it's ***paired Totals_read_counts.R*** scripts extract and plot QC based on the number of reads at each stage of the pipeline and alignment rates.

## Processing RPFs
**Ensure you activate the RiboSeq conda environment before running the RPF shell scripts, with the following command**
```console
conda activate RiboSeq
```
### Sequencing QC
Before processing any data it is important to use fastQC to see what the structure of the sequencing reads is.

**RPFs_0_QC.sh** will run fastQC on all RPF <.fastq> files and output the fastQC files into the fastQC directory.

The output will tell you the number of reads for each <.fastq> file as well as some basic QC on the reads.

A good indication of whether the <.fastq> files have already been processed or not is the sequence length distribution. If no processing has been done, then all reads should be the same length, which will be the number of cycles used when sequenced. For example, if 75 cycles were selected when setting up the sequencing run, then all reads would be 75 bases long, even if the library fragment length was much shorter or much longer than this. Therefore, if for example with a standrad RPF library with 4nt UMIs on either end of the RPF, the fragment length will be roughly 30nt (RPF length) plus 8nt (UMIs) plus the length of the 3' adaptor. If the adaptors had already been removed prior to uploading the <.fastq> files to GEO, then the sequence length distribution will be a range of values, peaking at roughly 38. If the peak was closer to 30nt then it could be presumed that the UMIs had also been removed. The adaptor content will also give a good indication of this. For example, in the above example, if adaptors hadn't been removed, you should expect to see adaptor contamination coming up in the reads from roughly 38nts into the reads.

### Remove adaptors
The 3' adaptor used in the library prep will be sequenced immediately after the fragment (and UMIs if used). These therefore needs to be removed so that they do not affect alignment. The ***RPFs_1_adaptor_removal.sh*** script uses cutadapt for this, which removes this sequence (specified in the common_variables.sh script) and any sequence downstream of this. It also trims low quality bases from the 3' end of the read below a certain quality score (user defined, we use q20) and removes reads that are shorter or longer than user defined values. For RPFs (~30) with 4nt UMIs at each end, we filter reads so that they are 30-50nt. If UMIs have been used then you need to set the minimum read length to 30nt as otherwise cd-hit-dup has issues de-duplicating the reads. If UMIs haven't been used, you will need to change these settings to 20-40.

After cutadapt has finished, fastQC is run on the output <.fastq> files. **Visual inspection of these fastQC files is essential to check that cutadapt has done what you think it has**

### Alignment and de-duplication
If UMIs have been used in the library prep, PCR duplicates can be removed from the analysis, ensuring that all reads originated from unique RPFs.

This is done in a two-step process using UMI-tools. First the UMI is extracted from the read and appended to the read name using ***RPFs_2_extract_UMIs.sh*** script. The UMI structure needs to be set for this. For the nextflex library prep kit, these are 4nt at either end of the read.

Reads are then aligned to a reference transcriptome using the ***RPFs_3_align_reads.sh*** script, which uses bbmap.

The ***RPFs_3_align_reads.sh*** script uses bbmap to align reads first to the rRNAs and tRNAs. Each alignment will create two new <.fastq> files containing the reads that did and did not align. The reads that didn't align to either of these transcriptomes are then aligned to the protein coding transcriptome.

**It is very important to give some consideration to what transcriptome you use and how to handle multimapped reads.
It is strongly recommended that you use the total RNA-seq info to calculate the most abundant transcript per gene and filter a fasta file to include only these isoforms. This can be created as part of the Total_RNA pipeline (see above), by running ***calculate_most_abundant_transcript.R*** and then ***Totals_6_write_most_abundant_transcript_fasta.sh*****

It is also recommended that the protein coding transcriptome is first filtered to include;**
- only Havana protein coding transcripts
- that have both 5' and 3'UTRs
- which the CDS is equally divisble by 3, starts with a start codon and finishes with a stop codon

This can be achieved with the ***Filtering_GENCODE_FASTA.py*** accessory script.

UMI-tools is then used to de-duplicate the resulting BAM file with the ***RPFs_4_deduplication.sh*** script.

**If the library prep did not include UMIs then *RPFs_2_extract_UMIs.sh* and *RPFs_4_deduplication.sh* should be skipped. If this is the case you need to edit the input file names in the** ***RPFs_3_align_reads.sh*** and ***RPFs_5_Extract_counts_all_lengths.sh*** **scripts.**

fastQC is used to inspect the QC and read length distribution at each of these three stages and of the different alignments. You would expect to see a nice peak of read lengths 28-32nt for the protein coding aligned reads but a wider distribition for the rRNA/unaligned reads (this should reflect the size you cut on the RNA extraction gel).

### Count reads
In order to do any downstream analysis, we need to know how many reads aligned to which mRNAs at which positions. Also for library QC it is important to be able to distinguish between different read lengths, as certain read lengths may be filtered to remove those reads that are less likely to be true RPFs.

The ***counting_script.py*** script was adpated from the [RiboPlot package](https://pythonhosted.org/riboplot/ribocount.html). This script creates <.counts> files, which are plain text files in the following structure;

Transcript_1

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 150 20 34 85 34 58 75 22 27 85 53 24 85.....................................................

Transcript_2

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 103 10 37 83 24 57 45 28 7 89 43 26 55.....................................................

Transcript_3

0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 87 20 34 85 34 48 79 12 19 75 51 14 95.....................................................


where each two lines represents one transcript, with the first of each two lines containg the transcript ID and the second of each two lines containing tab seperated values of the read counts that start at that position within the transcript. The number of values for each transcript should therefore match the length of that transcript.

The ***RPFs_5_Extract_counts_all_lengths.sh*** uses the ***counting_script.py*** script to generate a <.counts> file for each sample for each read length defined in the for loop and stores all thes files in the Counts_files directory. This uses the sorted <.BAM> file as input and also needs the associated index <.BAI> file to be in the same directory. These are the input files for the downstream analysis.

### Library QC
The ***RPFs_6a_summing_region_counts.sh; RPFs_6b_summing_spliced_counts.sh and RPFs_6c_periodicity.sh*** scripts utlise the custom python scripts, reading in the counts files generated above and creating <.csv> files that the ***region_counts.R; heatmaps.R; offset_plots.R and periodicity.R*** scripts use to generate the library QC plots. From these plots you should be able to determine whether the RPF libraries have the properties that would argue they are truelly RPFs. These are;
- read length distribution peaking at 28-32nt
- strong periodicity
- strong enrichment of reads within the CDS and depletion of reads within the 3'UTR

From these plots you can then determine what read lengths you want to include in your downstream analysis for DE and codon level analyses.

The offset plots should also allow you to determine what to use for the offset. This is the value that you use in the ***RPFs_8_Extract_final_counts.sh*** so that the counts in the final <.counts> files are referring to the position within each transcript which is the first nt of the codon positioned within the P-site of the ribosome which was protecting that RPF, rather than the start of the read. This can be determined from the position at which the first peak of reads is observed just upstream of the start codon, as these reads correspond to RPFs which were protected by ribosomes with the P-site situated at the start codon. This is typically 12-13nt, but it is likely that different read lengths will require slightly different offsets.

The ***RPFs_6d_extract_read_counts.sh*** and it's ***paired RPF_read_counts.R*** scripts extract and plot QC based on the number of reads at each stage of the pipeline and alignment rates.

**While it is strongly encouraged that the above scripts are used when using the pipeline for the first time or with some external data, the wrapper ***RPFs_all.sh*** script combines all these into one script and can be used if the user is confident in doing so. Note that this script does not run fastQC on the intermediary files and does not have the same level of annotation as the above scripts.**

### Extract final counts
Once you know what read lengths and offsets to use, you can use these values with the ***RPFs_7_Extract_final_counts.sh*** script to create a final <.counts> file that contains only the specified read lengths with the specified offsets applied.

### Summing CDS counts
The ***RPFs_8a_CDS_counts.sh*** uses the ***summing_CDS_counts.py*** to sum all the read counts that are within the CDS. **This will be the input into DESeq2.**

The *summing_CDS_counts.py* has an option to remove the first 20 and last 10 codons, which is recommended (and set as default in *RPFs_8a_CDS_counts.sh* script) to avoid biases at the start and stop codons, essentially meaning that only activly elongating ribosomes are counted.

There is also the option to only include reads that are in frame. However, although periodicty indicates that the majority of the reads are truely RPFs, it doesn't neccessarily mean that those reads that are not in frame are not RPFs and the majority of the reads in the CDS will most likely be RPFs. **It is therefore recommended to include reads in all frames for DE analysis. For codon level analyses, only reads in frame should be used as it is not possible to confidently determine codon level resolution with high confidence for reads not in frame.**

### Summing 5'UTR counts
You may also want to count the reads within the 5'UTR to look at translation within upstream Open Reading Frames (uORFs). The ***RPFs_8b_UTR5_counts.sh*** uses the ***summing_UTR5_counts.py*** to sum all the read counts that are within the 5'UTR. Note that this counts all reads within the whole 5'UTR, not specific for individual uORFs.

### Counts to csv
In order to read in counts files into R, it is easier to have them written as csv files. ***RPFs_8c_counts_to_csv.sh*** will do this

### Counting codon occupancy
The ***RPFs_8d_count_codon_occupancy.sh*** uses the ***count_codon_occupancy.py*** to determine which codon was positioned at the A,P and E-site plus two codons either side, for every RPF read and sum them all together. The ***codon_occupancy.R*** script then takes this data and uses it to measure relative elongation rates for each codon based on the number of RPFs where that codon was at the A-site compared to the number of RPFs where that codon was at either of the 7 sites described above. This therefore accounts for differing mRNA abundances and initiation rates transcriptome-wide.

**Once you are happy that the data has been processed properly you can delete the intermediary files that are no longer required**

**Do not delete the raw <.fastq> files**

# Common troubleshooting
### remove \r end lines
The end of line character for windows is \r but for linux and mac it is \n. Sometimes, when you open a script on your PC in a text editor it will automatically add both \n and \r to the end of any new lines created. However, as the shell scripts are intended to be run on a linux/mac platform, this will cause issues and will return the following error message.

***/usr/bin/env: ‘bash\r’: No such file or directory***

To check if this is the case, in notepad++ select View->Show symbol->Show all characters to see hidden characters. If \r characters have been added to the end of lines, use find and replace (with regular expressions ticked) to remove them all, leaving just \n characters in their place
### check the path to directories is right
The path to the parent directory needs to be set in both the common_variables.sh and the common_variables.R scripts. Although these should point to the same directory, the path will be slightly different as the path in the shell script needs to be the linux path and the path for the R script needs to be the PC path.

- To find the linux path, go to that directory in the terminal and use pwd to see what the full path is and then copy this into the shell script
- To find the PC path, open R studio by doubleclicking on the common_variables.R script and use the getwd() function to find the current working directory. The parent directory will be a couple of directories up from this
