# braker 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；容器与 conda 环境信息记录于文末「容器与 Conda 链接」。
> 官方 nf-core 仅有 `braker3`（BRAKER3，非本模块的 BRAKER2 2.1.5，不可直接互换）；snakemake-wrappers 无
> braker 实现（2026-09 抓取 404，见「版本」），故仅登记 native。

***

## native 实现

# braker / native — 自包含 BRAKER2 基因预测驱动

BRAKER2（Gaius-Augustus/BRAKER）自动化基因预测流水线的本地自包含实现（`source_type: custom`、`type: native`；Perl 驱动）。

## 功能

BRAKER（BRAKER1/BRAKER2）是一个集成 AUGUSTUS 和 GeneMark-ES/ET 的基因预测工具，可以利用 RNA-seq 数据和同源蛋白序列进行预测，BRAKER1 仅支持 RNA-seq 证据，使用软屏蔽（softmask）的基因组序列可以提高预测准确性。

三个子命令对应 BRAKER2 的预测与格式转换：

| 子命令          | 命令                                                                                            | 作用                          |
| ------------ | --------------------------------------------------------------------------------------------- | --------------------------- |
| `run`        | `braker.pl --species=... --genome=... --bam=... [--prot_seq=...] --cores N [--etpmode --softmasking]` | RNA-seq ± 同源蛋白证据预测（BRAKER2） |
| `run_rnaseq` | `braker.pl --species=... --genome=... --bam=... --cores N [--softmasking]`                        | 仅 RNA-seq 证据（BRAKER1 模式）     |
| `gtf2gff3`   | `gtf2gff3.pl <braker.gtf>`                                                                     | 将 braker.gtf 转为 GFF3（stdout） |

> 线程优先级：`--threads` > `per_subcommand_threads`（run/run_rnaseq=8 / gtf2gff3=2）> `default_cpus`；经 `--cores` 透传。

## 用法

```bash
# CLI 直跑
python main.py run --genome genome.softmask.fasta --bam rnaseq.sort.bam \
    --prot_seq homolog.fasta --species malassezia_sympodialis_braker \
    --cores 8 --etpmode --softmasking
python main.py run_rnaseq --genome genome.softmask.fasta --bam rnaseq.sort.bam \
    --species my_species --cores 8 --softmasking
python main.py gtf2gff3 braker.gtf -o braker.gff3

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（run 也可用 `--workingdir` 指定输出目录）。

## 实战示例：BRAKER2 基因预测

BRAKER2 集成 AUGUSTUS 与 GeneMark-ES/ET，用 RNA-seq 与同源蛋白证据训练并预测基因。等价能力由 `native/main.py` 的 3 个子命令提供。

### 1. 准备输入文件

```bash
mkdir -p braker && cd braker
ln -s ../genome.softmask.fasta genome.fasta
gzip -dc protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta
ln -s ../augustus/making_hints/rnaseq.sort.bam .
```

### 2. 设置环境变量（依赖工具路径）

```bash
export AUGUSTUS_CONFIG_PATH=/opt/biosoft/augustus-3.4.0/config/
export AUGUSTUS_BIN_PATH=/opt/biosoft/augustus-3.4.0/bin/
export AUGUSTUS_SCRIPTS_PATH=/opt/biosoft/augustus-3.4.0/scripts/
export BAMTOOLS_PATH=/usr/local/bin/
export SAMTOOLS_PATH=/opt/biosoft/samtools-1.10/bin/
export ALIGNMENT_TOOL_PATH=/opt/biosoft/gth-1.7.3-Linux_x86_64-64bit/bin/
export BLAST_PATH=/opt/biosoft/ncbi-rmblast-2.10.0+/bin/
export GENEMARK_PATH=/opt/biosoft/gmes_linux_64
export DIAMOND_PATH=/opt/biosoft/diamond
export CDBTOOLS_PATH=/opt/biosoft/PASApipeline.v2.4.1/bin
```

### 3. 运行 BRAKER

```bash
# 结合 RNA-seq 与同源蛋白证据（ET 模式）
braker.pl --species=malassezia_sympodialis_braker --genome=genome.fasta \
    --bam=rnaseq.sort.bam --prot_seq=homolog.fasta --cores 8 --etpmode --softmasking

# 仅 RNA-seq（BRAKER1 模式）
braker.pl --species=malassezia_sympodialis_braker_rna --genome=genome.fasta \
    --bam=rnaseq.sort.bam --cores 8 --softmasking
```

### 4. 处理结果

```bash
# 保留 CDS/exon 行并转 GFF3
gtf2gff3.pl braker.gtf > braker.gff3
```

> **桥接**：上述命令等价于 `python main.py run ... --etpmode --softmasking` / `python main.py run_rnaseq ...` / `python main.py gtf2gff3 braker.gtf -o braker.gff3`。

### 5. 参数说明

| 参数                       | 说明                     |
| ------------------------ | ---------------------- |
| `--species=`             | 物种名（AUGUSTUS training 名称） |
| `--genome=`              | 基因组序列文件（建议软屏蔽）         |
| `--bam=`                 | RNA-seq 比对 BAM 文件       |
| `--prot_seq=`            | 同源蛋白序列文件（ET 模式）         |
| `--cores`                | 并行线程数                  |
| `--etpmode`              | ET 模式（结合同源蛋白证据）         |
| `--softmasking`          | 使用软屏蔽重复序列的基因组          |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。
BRAKER 上游**不提供预编译二进制**（仅 GitHub 源码，纯 Perl 脚本），故本地安装走 conda；源码部署小节并列保留。

### 依赖工具（BRAKER2 运行依赖）

BRAKER 为 Perl 驱动流水线，运行依赖以下工具（conda 安装会自动带入）：

* **AUGUSTUS**（最终基因预测，`AUGUSTUS_CONFIG_PATH`）
* **GeneMark-ES/ET**（训练证据模型，需 `~/.gm_key` 密钥，`GENEMARK_PATH`）
* **ProtHint**（由同源蛋白生成 hints）
* **GenomeThreader（gth）**（蛋白比对，`ALIGNMENT_TOOL_PATH`）
* **samtools** / **bamtools**（BAM 处理，`SAMTOOLS_PATH` / `BAMTOOLS_PATH`）
* **ncbi-rmblast**（`BLAST_PATH`）
* **diamond**（`DIAMOND_PATH`）
* **PASA**（`CDBTOOLS_PATH`）

### 1. Conda（包管理器安装）

```bash
mamba create -n braker -c conda-forge -c bioconda braker2=2.1.5
conda activate braker
braker.pl --version   # 断言
```

> Homebrew 无 BRAKER 公式，故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `braker`；无 conda 时部署官方 GitHub Perl 脚本到 `~/software/braker-<ver>/bin` 并写 PATH（依赖工具需另装）。版本默认 2.1.5，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/braker2:2.1.5--hdfd78af_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/braker2:2.1.5--hdfd78af_3 \
    braker.pl --genome=/data/genome.fasta --bam=/data/rnaseq.sort.bam --cores 8 --softmasking
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull braker.sif docker://depot.galaxyproject.org/singularity/braker2:2.1.5--hdfd78af_3
apptainer run -B $PWD:/data -H /data braker.sif braker.pl --genome=/data/genome.fasta --bam=/data/rnaseq.sort.bam --cores 8 --softmasking
```

### 4. 官方源码部署（并列保留）

<https://github.com/Gaius-Augustus/BRAKER>（tag `v2.1.5`，tarball `https://github.com/Gaius-Augustus/BRAKER/archive/v2.1.5.tar.gz`）：

```bash
# 下载并解压（纯 Perl 脚本，无需编译）
wget https://github.com/Gaius-Augustus/BRAKER/archive/v2.1.5.tar.gz -O ~/software/BRAKER-2.1.5.tar.gz
tar zxf ~/software/BRAKER-2.1.5.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/BRAKER-2.1.5/scripts/' >> ~/.bashrc
source ~/.bashrc

# 安装缺失的 Perl 模块
cpan -i Scalar::Util::Numeric MCE::Mutex Math::Utils
braker.pl --version   # 验证

# 修改 augustus 脚本以兼容 BRAKER
perl -p -i -e 's#\(\.\*\)#\(\.\*\?\)# if m/transcript_id/;' /opt/biosoft/augustus-3.4.0/scripts/filterGenesIn_mRNAname.pl
```

> ⚠️ 源码部署仅含 BRAKER 脚本，AUGUSTUS / GeneMark / ProtHint / gth / samtools / bamtools / rmblast / diamond / PASA 需另行安装并设置上方环境变量；推荐直接走 conda。

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（BRAKER2 真实运行需大量依赖与真实 BAM）
```

## 版本

* braker `2.1.5`（bioconda::braker2=2.1.5；bioconda 另有 2.1.2/2.1.4/2.1.6）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/braker2 / depot.galaxyproject.org；本地不再自建容器）
* Perl 驱动：`braker.pl` + `gtf2gff3.pl`；依赖 AUGUSTUS / GeneMark-ES/ET / ProtHint / gth / samtools / bamtools / ncbi-rmblast / diamond / PASA
* ⚠️ 官方 nf-core 仅有 `braker3`（BRAKER3，对应上游 BRAKER 3.x），与本模块 pin 的 BRAKER2 2.1.5 不可直接互换；snakemake-wrappers 无 `bio/braker2`、`bio/braker`（2026-09 抓取 404）

## 容器与 Conda 链接

* **Github**：https://github.com/Gaius-Augustus/BRAKER
* Snakemake版BRAKER4：https://github.com/Gaius-Augustus/BRAKER4
* **Bioconda 页面**：<https://anaconda.org/bioconda/braker2>
* **Docker**：`docker pull quay.io/biocontainers/braker2:2.1.5--hdfd78af_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/braker2%3A2.1.5--hdfd78af_3>
* 安装方式（本地）：`mamba create -n braker -c conda-forge -c bioconda braker2=2.1.5`
