# canu 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 **nf-core** 有 `canu` 模块（2026-09 抓取 200，pin bioconda::canu=2.3）；**snakemake-wrappers** 无 `bio/canu`（404）→ 官方实现不建目录，只在 `meta.yaml` 的 `software_versions` 与本 README 登记。

***

## native 实现

# canu / native — 自包含长读组装驱动

Canu 的本地自包含实现（`source_type: custom`、`type: native`；PacBio / Nanopore 长读 OLC 组装）。

## 功能

三个子命令对应 Canu 的错误纠正—修剪—组装链路：

| 子命令        | 命令（核心）                                                                    | 作用                        |
| ---------- | -------------------------------------------------------------------------- | ------------------------- |
| `assemble` | `canu -p <prefix> genomeSize=<size> useGrid=false maxThreads=N -pacbio-raw <reads>` | 完整组装 correct→trim→assemble |
| `correct`  | 同上，追加 `-correct`                                                             | 仅纠错阶段                     |
| `trim`     | 同上，追加 `-trim`                                                                | 仅修剪阶段                     |

数据类型由 `--data-type` 选择：`pacbio-raw`（默认，`-pacbio-raw`）| `pacbio-corrected` | `nanopore-raw` | `nanopore-corrected` | `pacbio-hifi`。

> ⚠️ **注意**：Canu 的 `-p` 是**输出前缀**，不是线程数；单机并发由 `useGrid=false` + `maxThreads=N` 控制（本驱动自动注入 `maxThreads`）。

## 用法

```bash
# CLI 直跑（仿文档示例：lambda 基因组，genomeSize=58000）
python main.py assemble subreads.fasta --prefix out --genome-size 58000 --data-type pacbio-raw --threads 8

# Nanopore 数据 + 仅纠错
python main.py correct reads.fastq --prefix out --genome-size 8m --data-type nanopore-raw --threads 8

# 仅修剪
python main.py trim subreads.fasta --prefix out --genome-size 8m --threads 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例

Canu 基于 Overlap-Layout-Consensus，专为 PacBio 与 Oxford Nanopore 高噪音长读设计。以下为文档给出的 Lambda 与 Malassezia_sympodialis 组装用法；等价能力由 `native/main.py` 的 `assemble` 子命令提供。

```bash
mkdir -p 04.genome_assembling/Canu
cd 04.genome_assembling/Canu

# --- Lambda 基因组组装 ---
mkdir lamda; cd lamda
# 将 PacBio BAM 转为 fasta（smrtlink 的 bam2fasta）
bam2fasta -o subreads -u /path/to/lambdaTINY/*.bam
canu -p out genomeSize=58000 useGrid=false -pacbio-raw subreads.fasta
cd ..

# --- Malassezia_sympodialis 基因组组装（8Mb）---
mkdir Malassezia_sympodialis; cd Malassezia_sympodialis
bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
# -p out: 输出前缀；genomeSize=8000000: 估计基因组大小；useGrid=false: 不使用集群；-pacbio-raw: 原始 PacBio 数据
canu -p out genomeSize=8000000 useGrid=false -pacbio-raw subreads.fasta &> canu.log
cd ..
```

> 桥接句：`canu -p out genomeSize=8000000 useGrid=false -pacbio-raw subreads.fasta` 等价能力由 `native/main.py` 的 `assemble` 子命令提供（`python main.py assemble subreads.fasta --prefix out --genome-size 8000000 --data-type pacbio-raw --threads 8`，本驱动额外注入 `maxThreads`）。

### 参数说明

| 参数                     | 说明                          |
| ---------------------- | --------------------------- |
| `genomeSize=8000000`   | 估计的基因组大小（支持单位：k、m、g）        |
| `useGrid=false`        | 不使用集群（单机运行）                 |
| `-pacbio-raw`          | 输入原始 PacBio 数据              |
| `-pacbio-corrected`    | 输入已校正的 PacBio 数据            |
| `-nanopore-raw`        | 输入原始 Nanopore 数据            |
| `-p out`               | 输出前缀                        |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），且官方 release v2.0 提供预编译二进制包；直接拉官方镜像或取官方预编译包运行，main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n canu-native -c conda-forge -c bioconda canu=2.0
conda activate canu-native
canu --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap）
brew tap brewsci/bio
brew install canu
canu --version   # 断言
```

> 📌 brew 当前公式为 **v2.2**（`brewsci/bio/canu`），与 meta 登记 **2.0** 略有差异（以 formula 为准）；homebrew-core 无 canu（2026-09 核实 404）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/canu:2.0--he1b5a44_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/canu:2.0--he1b5a44_0 \
    canu -p out genomeSize=8000000 useGrid=false -pacbio-raw subreads.fasta
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull canu.sif docker://depot.galaxyproject.org/singularity/canu:2.0--he1b5a44_0
apptainer run -B $PWD:/data -H /data canu.sif \
    canu -p out genomeSize=8000000 useGrid=false -pacbio-raw /data/subreads.fasta
```

### 4. 官方预编译二进制包（首选）

官方 release **v2.0** 提供 Linux / Darwin amd64 预编译包（2026-09 核实存在）：

```bash
# 下载（Linux）
wget https://github.com/marbl/canu/releases/download/v2.0/canu-2.0.Linux-amd64.tar.xz -P ~/software/
# macOS：canu-2.0.Darwin-amd64.tar.xz

# 解压到用户目录（无需 root；禁 /opt/biosoft）
tar xJf ~/software/canu-2.0.Linux-amd64.tar.xz -C ~/software/
echo 'export PATH=$PATH:~/software/canu-2.0/Linux-amd64/bin/' >> ~/.bashrc
source ~/.bashrc

# 验证
canu --version
```

> 一键安装可走 `bash native/install.sh --method binary`（内嵌 v2.0 官方 sha256：Linux `29352586…c295`、macOS `5cf5d621…eab1`）。
> ⚠️ 2026-09 核实：官方 release **v2.3 已不再提供预编译资产**（assets 为空），如需 2.3 请走 conda/容器或源码 `make`。

### 5. 官方源码编译（并列保留）

```bash
# 文档所用源码 tag 为 end-of-big-meryl（Canu 2.0 源码分支）
wget https://github.com/marbl/canu/archive/end-of-big-meryl.tar.gz -O ~/software/canu-2.0.tar.gz
tar zxf ~/software/canu-2.0.tar.gz -C ~/software/
mv ~/software/canu-end-of-big-meryl ~/software/canu-2.0
cd ~/software/canu-2.0/src/
make -j 8
echo 'export PATH=$PATH:~/software/canu-2.0/Linux-amd64/bin/' >> ~/.bashrc
source ~/.bashrc
canu --version
```

## 官方实现登记（nf-core，不建目录）

* nf-core 模块 **`modules/nf-core/canu`**（单模块，无子目录；2026-09 抓取 200），pin `bioconda::canu=2.3=h3fb4750_1` + `minimap2=2.28` + `samtools=1.21`。
* 执行请用 `nf-core modules install nf-core canu` 安装到项目自身目录，**不要直接引用本仓库示例**：

```bash
nf-core modules install nf-core/canu
```

```groovy
include { CANU } from '../modules/nf-core/canu/main'
```

* 强提示：本仓库**未**创建 `nextflow/` 目录；nf-core 官方模块缺失/需定制时才走本地自定义。native 版本 2.0 与 nf-core pin 2.3 相差一个 minor，跨引擎迁移请核对。

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（组装需真实长读且耗时极长）
```

## 版本

* canu 2.0（文档版本；bioconda::canu=2.0 / 容器 tag `2.0--he1b5a44_0` / 官方 release v2.0 预编译包）
* 官方当前最新 2.3（bioconda=2.3，但 release v2.3 无预编译资产）；nf-core 模块 pin 2.3
* 构建路线：官方镜像/conda/官方预编译包提供（quay.io/biocontainers/canu / depot.galaxyproject.org；本地不再自建容器）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/canu/overview>
* **Docker**：`docker pull quay.io/biocontainers/canu:2.0--he1b5a44_0`（2.3 为 `2.3--h636b4d1_3`）
* **Singularity**：<https://depot.galaxyproject.org/singularity/canu%3A2.0--he1b5a44_0>
* **GitHub**：<https://github.com/marbl/canu>（releases：v2.0 / v2.3）
* 安装方式（本地）：`mamba create -n canu -c conda-forge -c bioconda canu=2.0`
