# Dependencies
依赖
Use conda to install the following dependencies
使用 conda 安装以下依赖软件。

Install conda by following the instuctions here:
请按照以下链接的说明安装 conda：
[conda installation instructions](https://conda.io/projects/conda/en/latest/user-guide/install/linux.html)

For more information on conda, see [here](https://towardsdatascience.com/getting-started-with-python-environments-using-conda-32e9f2779307) and [Conda cheat sheet](https://docs.conda.io/projects/conda/en/4.6.0/_downloads/52a95608c49671267e40c689e0bc00ca/conda-cheatsheet.pdf)
关于 conda 的更多背景和用法可参考：[示例教程](https://towardsdatascience.com/getting-started-with-python-environments-using-conda-32e9f2779307) 和 [Conda 速查表](https://docs.conda.io/projects/conda/en/4.6.0/_downloads/52a95608c49671267e40c689e0bc00ca/conda-cheatsheet.pdf)。

**Make a seperate environment for processing the RPFs and for processing the total RNA-seq data**
**强烈建议分别为 RPFs 处理和总 RNA‑seq 处理创建独立的 conda 环境。**

## RiboSeq environment
RiboSeq 环境
The RiboSeq environment is for processing RPFs and requires the following programs to be installed
RiboSeq 环境用于处理 RPFs，需要安装以下程序：
#### fastQC [manual](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
#### cutadapt [manual](https://cutadapt.readthedocs.io/en/stable/guide.html)
#### UMItools [manual](https://umi-tools.readthedocs.io/en/latest/QUICK_START.html)
#### bbmap [manual](https://jgi.doe.gov/data-and-tools/bbtools/bb-tools-user-guide/bbmap-guide/)
#### SAMtools (this has to be v1.9) [manual](http://www.htslib.org/doc/samtools.html)

It also requires the python packaes [pysam](https://github.com/pysam-developers/pysam) and [biopython](https://biopython.org/)
此外还需要 Python 包 [pysam](https://github.com/pysam-developers/pysam) 和 [biopython](https://biopython.org/)。

This environment can be created as follows
可以按如下步骤创建该环境：
**Do not copy and paste multiple lines into the terminal at once as some commands will require you to follow prompts, i.e. typing y to proceed with installation**
**请不要一次性将多行命令全部粘贴到终端，因为部分命令需要你在安装过程中根据提示输入 y 等确认信息。**

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

## RNAseq environment
RNAseq 环境
The RNAseq environment is for processing totals and requires the following programs to be installed. This environment can also be used to process standard RNA-seq data
RNAseq 环境用于处理总 RNA‑seq（totals）数据，也可用于处理标准 RNA‑seq 数据，需要安装以下程序：
#### RSEM [manual](https://deweylab.github.io/RSEM/README.html)
RSEM also requires either bowtie, bowtie2 or STAR to align the reads. We use [bowtie2](http://bowtie-bio.sourceforge.net/bowtie2/manual.shtml).
RSEM 需要配合 bowtie、bowtie2 或 STAR 进行比对，本流程使用 [bowtie2](http://bowtie-bio.sourceforge.net/bowtie2/manual.shtml)。

Installing RSEM with conda will also install samtools, however you need to force it to install version 1.9 to avoid getting an error while loading shared libraries: libcrypto.so.1.0.0
通过 conda 安装 RSEM 时会同时安装 samtools，但需要强制安装 1.9 版本，以避免出现 `libcrypto.so.1.0.0` 相关的动态库加载错误。

There was an issue when installing bowtie2 with conda that required downgrading the tbb package [see here](https://www.biostars.org/p/494922/)
使用 conda 安装 bowtie2 时曾遇到需要降级 tbb 包的问题，可参考：[讨论链接](https://www.biostars.org/p/494922/)。

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



