# trinity 软件模块

> 汇总说明：本 README 合并各实现（native/官方 wrapper）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# trinity / native — 自包含转录组组装驱动

Trinity 的本地自包含实现（`source_type: custom`、`type: native`）。主程序 `Trinity` 由 Inchworm / Chrysalis / Butterfly 三模块串联而成，并附带 `util/` 下的统计、定量与矩阵脚本。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `denovo` | `Trinity --seqType fq --max_memory <mem> --left ... --right ... --CPU N --output ...` | 无参考 de novo 组装（Inchworm→Chrysalis→Butterfly） |
| `genome_guided` | `Trinity --genome_guided_bam <bam> --genome_guided_max_intron N --CPU N --output ...` | 基于比对 BAM 的有参组装 |
| `stats` | `util/TrinityStats.pl <Trinity.fasta>` | 组装统计（contig 数 / N50） |
| `longest_isoforms` | `util/extract_longest_isoforms_from_TrinityFasta.pl <Trinity.fasta>` | 提取每基因最长 isoform（Unigene） |
| `align_estimate` | `util/align_and_estimate_abundance.pl --transcripts ... --est_method RSEM --aln_method bowtie2` | 比对并估计表达量 |
| `abundance_matrix` | `util/abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix genes *.results` | 合并多样本定量结果为表达矩阵 |

## 用法

```bash
# CLI 直跑
python main.py denovo --left A1.1.fastq,A2.1.fastq --right A1.2.fastq,A2.2.fastq \
    --seqtype fq --max-memory 2G --normalize-reads --output trinity_denovo --threads 8
python main.py genome_guided merged.sort.bam --genome-guided-max-intron 4000 --output trinity_genomeGuided --threads 8
python main.py stats trinity_denovo/Trinity.fasta -o trinity_denovo/Trinity.fasta.stats
python main.py longest_isoforms trinity_denovo/Trinity.fasta -o trinity_denovo/unigene.longest.fasta
python main.py abundance_matrix --est_method RSEM --out_prefix genes *.genes.results

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：De novo / genome-guided 组装与下游统计

Trinity是目前使用最广泛的转录组De novo组装软件，由Broad Institute开发，包含三个独立模块：Inchworm 将 RNA-seq reads 组装成 unique 序列、Chrysalis 将 contigs 聚类并构建 De Bruijn 图、Butterfly 处理 De Bruijn 图识别可变剪接转录本。以下为文档典型链路；等价能力由 `native/main.py` 的 `denovo` / `genome_guided` / `stats` / `longest_isoforms` / `abundance_matrix` 子命令提供（见上「用法」）。

### 1. De novo 组装（无参考基因组）

```bash
mkdir -p trinity_denovo && cd trinity_denovo
Trinity --seqType fq --max_memory 2G \
    --left `ls *.1.fastq | perl -pe 's/\n/,/' | perl -pe 's/,$//'` \
    --right `ls *.2.fastq | perl -pe 's/\n/,/' | perl -pe 's/,$//'` \
    --CPU 8 --jaccard_clip --normalize_reads --output trinity_denovo --bflyCalculateCPU &> trinity_denovo.log
```

### 2. Genome-guided 组装（有参考基因组）

```bash
# 先合并并排序 hisat2 的比对结果
samtools merge -@ 8 merged.bam ~/06.reads_aligment/hisat2/*.sam
samtools sort -@ 8 -O BAM -o merged.sort.bam merged.bam

Trinity --max_memory 2G --CPU 8 --jaccard_clip --normalize_reads \
    --genome_guided_bam merged.sort.bam --genome_guided_max_intron 4000 \
    --output trinity_genomeGuided --bflyCalculateCPU &> trinity_genomeGuided.log
```

### 3. 统计组装结果并提取最长 Unigene

```bash
util/TrinityStats.pl trinity_denovo/Trinity.fasta > trinity_denovo/Trinity.fasta.stats
extract_longest_isoforms_from_TrinityFasta.pl trinity_denovo/Trinity.fasta > trinity_denovo/unigene.longest.fasta
```

### 4. 构建表达量矩阵（供 DESeq2 / edgeR）

```bash
util/abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix genes  *.genes.results
util/abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix isoforms *.isoforms.results
# 产物：*.counts.matrix / *.TMM.EXPR.matrix / *.TPM.not_cross.matrix
```

### 5. 参数说明

| 参数 | 说明 |
| --- | --- |
| `--seqType` | 序列类型，fq 表示 fastq |
| `--max_memory` | 最大内存使用量 |
| `--left/--right` | 双端测序数据（多样本逗号分隔） |
| `--CPU` | CPU 线程数 |
| `--jaccard_clip` | 去除高表达基因的过度组装（基因密集物种） |
| `--normalize_reads` | 对测序深度进行归一化 |
| `--SS_lib_type` | 链特异性测序类型，RF 表示 fr-firststrand |
| `--bflyCalculateCPU` | 自动计算 Butterfly 线程数 |
| `--genome_guided_bam` | 基因组比对结果 BAM（需排序） |
| `--genome_guided_max_intron` | 最大内含子长度，默认 10000bp |
| `--genome_guided_min_coverage` | 鉴定表达区域的最小覆盖度，默认1 |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。**已核实官方未提供按平台划分的预编译二进制包**（GitHub release 仅有 `trinityrnaseq-v2.11.0.FULL.tar.gz` 源码归档，需 `make` 编译），因此非容器场景走 conda 或官方 FULL 源码编译。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n trinity-native -c conda-forge -c bioconda trinity=2.11.0
conda activate trinity-native
Trinity --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install trinity
Trinity --version   # 断言（brew 当前 2.15.2，与 meta 登记 2.11.0 略有差异，以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `trinity`，无 conda 时下载官方 FULL 源码包编译到 `~/software/trinity-<ver>` 并写 PATH；版本默认 2.11.0，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/trinity:2.11.0--h5ef6573_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/trinity:2.11.0--h5ef6573_1 \
    Trinity --seqType fq --left A1.1.fastq,A2.1.fastq --right A1.2.fastq,A2.2.fastq \
    --CPU 8 --max_memory 2G --output /data/trinity_denovo
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull trinity.sif docker://depot.galaxyproject.org/singularity/trinity:2.11.0--h5ef6573_1
apptainer run -B $PWD:/data -H /data trinity.sif Trinity --version
```

### 4. 官方源码编译（FULL 包，并列保留）

官方当前（v2.11.0）未发布预编译二进制，唯一非容器官方路线是 FULL 源码归档（含依赖源码，需 `make` 编译 + `make plugins`）：

```bash
wget https://github.com/trinityrnaseq/trinityrnaseq/releases/download/v2.11.0/trinityrnaseq-v2.11.0.FULL.tar.gz -P ~/software/
tar zxf ~/software/trinityrnaseq-v2.11.0.FULL.tar.gz -C ~/software/
cd ~/software/trinityrnaseq-v2.11.0
make -j 4          # 编译主程序与 Inchworm/Chrysalis/Butterfly
make plugins       # 安装 plugins（如需要）
echo 'export PATH=$PATH:~/software/trinityrnaseq-v2.11.0/' >> ~/.bashrc
source ~/.bashrc
Trinity --version  # 断言
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（denovo/genome_guided/util 脚本），无需已安装 Trinity
```

## 版本

* trinity 2.11.0（bioconda::trinity=2.11.0；quay tag `2.11.0--h5ef6573_1`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/trinity / depot.galaxyproject.org；本地不再自建容器）；官方另提供 FULL 源码归档（源码编译并列保留）

## 容器与 Conda 链接

* **官网**：https://github.com/trinityrnaseq/trinityrnaseq/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/trinity/overview>

* **Docker**：`docker pull quay.io/biocontainers/trinity:2.11.0--h5ef6573_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/trinity%3A2.11.0--h5ef6573_1>

* 安装方式（本地）：`mamba create -n trinity -c conda-forge -c bioconda trinity=2.11.0`

***

## 官方实现登记（不建目录）

* **nf-core modules**：`modules/nf-core/trinity`（扁平模块，含 `main.nf` / `meta.yml` / `environment.yml`），pin `bioconda::trinity=2.15.2`。执行前请 `nf-core modules install trinity` 安装到项目自身目录，不要直接引用本仓库示例。

* **snakemake-wrappers**：`bio/trinity`（扁平 wrapper，含 `wrapper.py` / `environment.yaml`），pin `trinity=2.15.2`。运行时靠 `wrapper: "v9.17.1/bio/trinity"` 句柄解析，不要把本地示例当 `wrapper_path`。
