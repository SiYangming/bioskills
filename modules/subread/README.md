# subread 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09 逐渠道核实）。
> Subread 是高效的 reads 比对与定量工具包，含 featureCounts（基因/外显子水平计数，RNA-seq 定量首选）、subread-align（gapped 基因组比对）、subjunc（剪接感知比对 + 剪接位点/融合检测）。

***

## native 实现

# subread / native — Subread / featureCounts 自包含驱动

Subread 的本地自包含实现（`source_type: custom`、`type: native`）。三个子命令分属同一 subread 包内的
三个可执行文件，驱动统一注入线程（`-T`）与临时目录。

## 功能

Subread软件包包含featureCounts、subread-align、subjunc等工具，其中featureCounts是最常用的基因表达量计数工具，速度是HTSeq的数倍到数十倍。

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `featureCounts` | `featureCounts -T N [-p] -t exon -g gene_id [-s 0] [-Q n] -a <gtf> -o <out> <bam...>` | 基因/外显子水平 reads 计数（定量） |
| `subread-align` | `subread-align -i <index> -r <r1> [-R <r2>] -o <out> -T N [-t 0]` | Subread gapped 基因组比对 |
| `subjunc` | `subjunc -i <index> -r <r1> [-R <r2>] -o <out> -T N` | 剪接感知比对 + 剪接位点/融合检测 |

参数说明（featureCounts）：

| 参数 | 说明 |
| --- | --- |
| `-T` | 线程数（自动注入） |
| `-p` | 双端测序数据，按片段（fragment）计数 |
| `-t` | 特征类型，默认 `exon` |
| `-g` | 分组属性，默认 `gene_id`（转录本水平可用 `transcript_id`） |
| `-a` | 参考注释 GTF 文件 |
| `-o` | 输出计数表 |
| `-s` | 链特异性：0=非链特异，1=正向，2=反向 |
| `-Q` | 最小比对质量值，默认 0 |

## 用法

```bash
# CLI 直跑
python main.py featureCounts -a genome.gtf -o counts.txt -T 8 -p sample1.bam sample2.bam
python main.py featureCounts -a genome.gtf -o counts.txt -t exon -g gene_id -s 0 -Q 10 sample.bam
python main.py subread-align -i subread_index -r reads_1.fq -R reads_2.fq -o aln.bam --threads 8
python main.py subjunc -i subread_index -r reads_1.fq -R reads_2.fq -o junction.bam --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：基因组比对 → featureCounts 批量定量 → count 矩阵

以下为有参转录组（HISAT2 比对后）典型定量用法；等价能力由 `native/main.py` 的 `featureCounts` 子命令提供（见上「用法」）。

### 1. 多 BAM 一次性基因水平计数（推荐）

```bash
mkdir -p featureCounts_out && cd featureCounts_out

# 基因水平计数（双端测序，按外显子计数；-T 线程，-p 按片段）
featureCounts -T 8 \
    -p \
    -t exon \
    -g gene_id \
    -a ../genome.gtf \
    -o gene_counts.txt \
    ../hisat2/*.bam

# 提取 counts 矩阵（去除前 2 行注释/表头行）
tail -n +3 gene_counts.txt | cut -f1,7- > gene_counts.matrix
```

### 2. 链特异性 / 质量过滤

```bash
# 反向链特异文库（dUTP 法）用 -s 2；正向用 -s 1；最小比对质量 -Q 10
featureCounts -T 8 -p -s 2 -Q 10 -t exon -g gene_id \
    -a ../genome.gtf -o gene_counts.txt ../hisat2/*.bam
```

### 3. 桥接 native 驱动

```bash
# 等价（驱动会自动注入 -T，并按参数拼装；子命令后可用 --threads 覆盖）
python main.py featureCounts -a ../genome.gtf -o gene_counts.txt -T 8 -p -s 2 -Q 10 ../hisat2/*.bam
```

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方渠道已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有 subread），容器/镜像
直接拉官方即可；此外官方在 SourceForge 另提供**预编译二进制包**，因此宿主机安装保留**两条官方路线**
（预编译包 / 源码编译），conda / brew / 容器作为并列备选。

### 1. 官方预编译二进制包（官方 SourceForge，首选）

```bash
# Linux x86_64（官方预编译包，解压到用户前缀，免 root）
wget https://sourceforge.net/projects/subread/files/subread-2.0.1/subread-2.0.1-Linux-x86_64.tar.gz/download \
     -O ~/software/subread-2.0.1.tar.gz
tar zxf ~/software/subread-2.0.1.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/subread-2.0.1-Linux-x86_64/bin' >> ~/.bashrc
source ~/.bashrc

# macOS x86_64 对应包名为 subread-2.0.1-MacOS-x86_64.tar.gz（同一下载页）
featureCounts -v   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `subread`，无 conda 时
> 自动下载官方 SourceForge 预编译包到 `~/software/subread-<ver>` 并写 PATH；版本默认 2.0.1，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

官方同时提供源码归档 `subread-2.0.1-source.tar.gz`（`src/` + `make`）：

```bash
wget https://sourceforge.net/projects/subread/files/subread-2.0.1/subread-2.0.1-source.tar.gz/download \
     -O ~/software/subread-2.0.1-source.tar.gz
tar zxf ~/software/subread-2.0.1-source.tar.gz -C ~/software/
cd ~/software/subread-2.0.1-source/src && make -j 4
# 产物生成到 ../bin/（featureCounts / subread-align / subjunc / subread-buildindex 等），写 PATH 即可
export PATH=$PATH:~/software/subread-2.0.1-source/bin
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n subread-native -c conda-forge -c bioconda subread=2.0.1
conda activate subread-native
featureCounts -v   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install subread
featureCounts -v   # 断言（brewsci/bio 公式当前 2.0.1，与 meta 登记 2.0.1 一致，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/subread:2.0.1--h7132678_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/subread:2.0.1--h7132678_2 \
    featureCounts -T 8 -p -t exon -g gene_id -a /data/genome.gtf -o /data/counts.txt /data/sample.bam
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull subread.sif docker://depot.galaxyproject.org/singularity/subread:2.0.1--h7132678_2
apptainer exec -B $PWD:/data subread.sif \
    featureCounts -T 8 -p -a /data/genome.gtf -o /data/counts.txt /data/sample.bam
```

## 测试

```bash
bash test/run_test.sh   # 自省 + 三子命令 argv 构造断言恒跑；已装 featureCounts 时做 -v 冒烟
```

## 官方实现登记（nextflow / snakemake，不建目录）

* **nf-core**：`modules/nf-core/subread/featurecounts`（2026-09 抓取目录 HTTP 200）。执行前请用
  `nf-core modules install subread/featurecounts` 安装到项目自身目录；版本锚点 `bioconda::subread=2.1.1`。
* **snakemake-wrappers**：`bio/subread/featurecounts`（目录 HTTP 200）。运行时靠 Snakemake 解析
  `wrapper: "v3.13.0/bio/subread/featurecounts"`，**不要把本地示例 wrapper 当作 wrapper_path**；
  版本锚点 `subread=2.1.1`。未在本地建 `snakemake/` 目录。
* **版本差异**：native 2.0.1（本文档/预编译包）；nf-core 与 snakemake-wrappers 当前 pin **2.1.1**，
  跨引擎迁移请核对 `-s`/`-p` 等参数（详见 `meta.yaml software_versions`）。

## 版本

* subread 2.0.1（bioconda::subread=2.0.1；官方 SourceForge 预编译包 subread-2.0.1-{Linux,MacOS}-x86_64.tar.gz）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/subread:2.0.1--h7132678_2 / depot.galaxyproject.org；本地不再自建容器）
* 与 nf-core / smk-wrappers 的 bioconda pin（2.1.1）存在一个 minor 差异（见上）

## 容器与 Conda 链接

* **官网**：http://subread.sourceforge.net/
* **SourceForge**：https://sourceforge.net/projects/subread/
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/subread/overview>
* **Docker**：`docker pull quay.io/biocontainers/subread:2.0.1--h7132678_2`
* **Singularity**：<https://depot.galaxyproject.org/singularity/subread%3A2.0.1--h7132678_2>
* **官方预编译包**：<https://sourceforge.net/projects/subread/files/subread-2.0.1/>
* **官方源码**：<https://sourceforge.net/projects/subread/files/subread-2.0.1/subread-2.0.1-source.tar.gz/download>
* **Homebrew（brewsci/bio）**：<https://github.com/brewsci/homebrew-bio/blob/master/Formula/subread.rb>
* 安装方式（本地）：`mamba create -n subread -c conda-forge -c bioconda subread=2.0.1`

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# subread native Conda 环境配方
# 离线兜底：可另存为 subread-native.yml 后 mamba env create -f subread-native.yml；在线推荐上方 mamba create 直装命令
name: subread-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - subread=2.0.1
  - pyyaml>=6.0
  - pip
```
