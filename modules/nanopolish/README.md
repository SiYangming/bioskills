# nanopolish 软件模块

> 汇总说明：本 README 合并各实现（native 等）的用法；安装方式见下方「环境安装」，容器与 conda
> 环境信息见文末「容器与 Conda 链接」。
>
> nanopolish 是 Oxford Nanopore 数据的**信号级**分析工具（官网 <https://github.com/jts/nanopolish>）：
> 基于原始 fast5 信号做一致性序列修正、甲基化检测与事件比对。本模块仅实现 `native/`
> （index / variants / vcf2fasta / methylation / eventalign / phase-reads 六段链路）；官方登记：
> **nf-core `modules/nf-core/nanopolish` 404、snakemake-wrappers `bio/nanopolish` 404**（2026-09 核实）
> → 不建 nextflow/、snakemake/ 目录。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/nanopolish/` **不存在**（2026-09 抓取返回 404）。Nextflow 场景请容器化后
  直调 `nanopolish`，或走本模块 `native/` 子命令。

* **snakemake-wrappers**：`bio/nanopolish` **不存在**（2026-09 抓取返回 404）。Snakemake 场景请容器化后
  直调，或走本模块 `native/` 子命令。

***

## native 实现

# nanopolish / native — ONT 信号级修正驱动（nanopolish 0.14.0）

nanopolish 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `index` | `nanopolish index [-d <fast5dir>...] <reads...>` | 建立 fast5 与 reads 的索引 |
| `variants` | `nanopolish variants [--consensus] -o <vcf> -w <region> -r <reads> -b <bam> -g <fa> -t N` | 信号级变异调用 / 一致性序列 |
| `vcf2fasta` | `nanopolish vcf2fasta -g <fa> <vcf>` | VCF → 修正后 FASTA（写 stdout） |
| `methylation` | `nanopolish methylation -r <reads> -b <bam> -g <fa> -t N` | 甲基化修饰检测 |
| `eventalign` | `nanopolish eventalign -r <reads> -b <bam> -g <fa> [--scale-events] -t N` | reads 事件序列比对到参考 |
| `phase-reads` | `nanopolish phase-reads <bam> <vcf> -t N` | reads 单倍型分型 |

## 用法

```bash
# CLI 直跑（对齐教学文档 doc 04 §22）
python main.py index -d fast5/ nanopore_reads.fastq
python main.py variants --consensus -o variants.vcf -w "tig00000001:1-100000" \
    -r nanopore_reads.fastq -b reads.sorted.bam -g draft.fasta --threads 8
python main.py vcf2fasta -g draft.fasta variants.vcf > nanopolish.fasta
python main.py methylation -r nanopore_reads.fastq -b reads.sorted.bam -g draft.fasta --threads 8
python main.py eventalign -r nanopore_reads.fastq -b reads.sorted.bam -g draft.fasta --scale-events
python main.py phase-reads reads.sorted.bam variants.vcf --threads 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 优先级：用户显式 >
`optimization.per_subcommand_threads`（variants/methylation/eventalign 默认 8）> `default_cpus`。

## 实战示例：Nanopore 基因组多轮修正

> 典型流程如下；**等价能力由 `native/main.py` 的
> `index` / `variants` / `vcf2fasta` / `methylation` / `eventalign` / `phase-reads` 子命令提供**
> （比对由 minimap2、排序索引由 samtools 完成，见各自模块）。

```bash
# 0) 数据准备：draft 基因组 + nanopore reads + 原始 fast5 信号目录
ln -s Canu.fasta draft.fasta
ln -s nanopore_reads.fastq ./
ln -s nanopore_fast5/ ./fast5

# 1) 建立索引（等价能力由 native/main.py 的 index 子命令提供）
nanopolish index -d fast5/ nanopore_reads.fastq
#   python main.py index -d fast5/ nanopore_reads.fastq

# 2) 将 reads 比对到 draft 基因组并排序索引（minimap2 + samtools）
minimap2 -ax map-ont -t 8 draft.fasta nanopore_reads.fastq | samtools sort -@ 4 -o reads.sorted.bam
samtools index reads.sorted.bam

# 3) 信号级修正（variants 模式；等价能力由 native/main.py 的 variants 子命令提供）
nanopolish variants --consensus -o variants.vcf \
    -w "tig00000001:1-100000" \
    -r nanopore_reads.fastq \
    -b reads.sorted.bam \
    -g draft.fasta \
    -t 8
#   python main.py variants --consensus -o variants.vcf -w "tig00000001:1-100000" \
#       -r nanopore_reads.fastq -b reads.sorted.bam -g draft.fasta --threads 8

# 4) 生成修正后的基因组序列（等价能力由 native/main.py 的 vcf2fasta 子命令提供）
nanopolish vcf2fasta -g draft.fasta variants.vcf > nanopolish.fasta
#   python main.py vcf2fasta -g draft.fasta variants.vcf > nanopolish.fasta

# 5) 多轮修正（通常 2–3 轮；每轮用上一轮输出作为新参考）
for i in 1 2 3; do
    minimap2 -ax map-ont -t 8 round${i}.fasta nanopore_reads.fastq | samtools sort -@ 4 -o reads.sorted.bam
    samtools index reads.sorted.bam
    nanopolish variants --consensus -o round${i}.vcf \
        -r nanopore_reads.fastq -b reads.sorted.bam -g round${i}.fasta -t 8
    nanopolish vcf2fasta -g round${i}.fasta round${i}.vcf > round$((i+1)).fasta
done
```

### 参数说明（main.py 常用项）

| 参数 | 说明 |
| --- | --- |
| `-t` / `--threads` | 线程数（驱动自动注入） |
| `-g` / `--genome` | 参考基因组序列 |
| `-r` / `--reads` | Nanopore reads 文件 |
| `-b` / `--bam` | 比对的 BAM 文件 |
| `-o` / `--output` | 输出文件 |
| `-w` / `--window` | 处理的基因组区域（如 `tig00000001:1-100000`） |
| `--consensus` | 生成一致性序列 |
| `--methylation-aware=dcm,dam` | 考虑甲基化修饰 |
| `-d` / `--fast5-dir` | index 子命令的 fast5 目录（可重复） |

> 💡 nanopolish 需要原始 fast5 信号数据（而非仅 basecalled 的 fastq）才能做高质量修正；若只有 fastq，
> 可用 medaka 替代。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具
二进制；main.py 驱动在宿主机跑。官方**无预编译二进制发布**（仅源码 + bioconda），故源码编译与镜像并列。

### 1. Conda（包管理器安装）

```bash
mamba create -n nanopolish-native -c conda-forge -c bioconda nanopolish=0.14.0   # 或文末「Conda 环境」配方
conda activate nanopolish-native
nanopolish --version   # 断言
```

> homebrew 两源均无 nanopolish（homebrew-core `nanopolish.json` 404、brewsci/bio
> `Formula/nanopolish.rb` 404，2026-09 核实）→ 不提供 brew 块。
> 一键安装直接 `bash native/install.sh`（有 conda/mamba 时建 bioconda 环境 `nanopolish`；无 conda 时
> 走官方源码编译到 `~/software/nanopolish-<ver>`；版本默认 0.14.0，与 `software_versions` 对齐）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/nanopolish:0.14.0--h5ca1c30_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/nanopolish:0.14.0--h5ca1c30_6 \
    variants --consensus -o /data/variants.vcf -w "tig00000001:1-100000" \
    -r /data/nanopore_reads.fastq -b /data/reads.sorted.bam -g /data/draft.fasta -t 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull nanopolish.sif docker://depot.galaxyproject.org/singularity/nanopolish:0.14.0--h5ca1c30_6
apptainer run -B $PWD:/data -H /data nanopolish.sif \
    variants --consensus -o /data/variants.vcf -w "tig00000001:1-100000" \
    -r /data/nanopore_reads.fastq -b /data/reads.sorted.bam -g /data/draft.fasta -t 8
```

### 4. 官方源码编译（官方无预编译二进制，并列保留）

官方源码见 <https://github.com/jts/nanopolish>，`git clone --recursive` + `make`（依赖 htslib / eigen /
hdf5 开发库）：

```bash
sudo apt-get install -y --no-install-recommends build-essential libhdf5-dev libeigen3-dev zlib1g-dev  # Debian/Ubuntu
git clone --recursive https://github.com/jts/nanopolish.git ~/software/nanopolish
cd ~/software/nanopolish && git checkout v0.14.0 && make -j 8
echo 'export PATH=$HOME/software/nanopolish:$PATH' >> ~/.bashrc && source ~/.bashrc
nanopolish --version   # 断言
```

## 测试

```bash
bash modules/nanopolish/native/test/run_test.sh   # 自省 + 六子命令 argv 构造断言恒跑；nanopolish 已装时真跑 --version 冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/nanopolish/overview>
* **Docker**：`docker pull quay.io/biocontainers/nanopolish:0.14.0--h5ca1c30_6`
* **Singularity**：<https://depot.galaxyproject.org/singularity/nanopolish%3A0.14.0--h5ca1c30_6>
* **官方源码**：<https://github.com/jts/nanopolish>
* 安装方式（本地）：`mamba create -n nanopolish -c conda-forge -c bioconda nanopolish=0.14.0`

## 版本

* nanopolish **0.14.0**（bioconda latest，2026-09 核实；quay/depot tag `0.14.0--h5ca1c30_6`）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/nanopolish / depot.galaxyproject.org；本地不自建容器）；官方另有源码编译路线（htslib/eigen/hdf5）
* 官方无 Nextflow / Snakemake wrapper（`modules/nf-core/nanopolish`、`bio/nanopolish` 均 404）
