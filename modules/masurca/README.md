# masurca 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 masurca 子模块（2026-09 抓取 404），故本模块只提供 `native/` 实现。

***

## native 实现

# masurca / native — 自包含混合组装驱动

MaSuRCA 的本地自包含实现（`source_type: custom`、`type: native`；二代+三代混合组装）。

## 功能

三个子命令覆盖 MaSuRCA 的配置→生成脚本→运行链路：

| 子命令      | 命令（核心）                                                  | 作用                              |
| -------- | ------------------------------------------------------- | ------------------------------- |
| `config` | `masurca <config.txt>`                                  | 由配置生成组装驱动脚本 `assemble.sh`         |
| `simple` | `masurca -t <N> -i <R1,R2> [-r <long.fa>]`              | 简化模式直跑全流程（PE + 可选长读）            |
| `run`    | `bash assemble.sh`                                      | 执行生成的组装脚本（日志重定向由 shell 完成）       |

## 用法

```bash
# CLI 直跑（文档流程：写 config.txt → 生成 assemble.sh → 运行）
python main.py config config.txt
python main.py run --script assemble.sh --log masurca.log

# 简化模式（无需 config.txt，直接给 PE reads + 可选长读）
python main.py simple -i illumina.1.fastq,illumina.2.fastq --long-reads subreads.fasta -t 32

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`simple` 注入 `-t`；`config`/`run` 的并发由 `config.txt` 的 `NUM_THREADS` 或 `assemble.sh` 自身控制）。

## 实战示例：二代 + 三代混合组装

MaSuRCA （Maryland Super Read-Corrected Assembler）支持二代与三代数据联合组装（super-read + mega-read），内部集成多种组装算法。以下为文档给出的混合组装用法；等价能力由 `native/main.py` 的 `config` / `run` 子命令提供。

```bash
mkdir -p 04.genome_assembling/MaSuRCA
cd 04.genome_assembling/MaSuRCA

# 建立数据符号链接（Illumina PE）
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq ./

# 转换 PacBio BAM 为 fasta
bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam

# 创建配置文件 config.txt（DATA 段 + PARAMETERS 段）
cat > config.txt <<EOF
DATA
PE= p1 268 66 $PWD/illumina.1.fastq $PWD/illumina.2.fastq
PACBIO=$PWD/subreads.fasta
END

PARAMETERS
GRAPH_KMER_SIZE=auto
USE_LINKING_MATES=0
USE_GRID=0
LHE_COVERAGE=40
MEGA_READS_ONE_PASS=0
CA_PARAMETERS =  cgwErrorRate=0.15
CLOSE_GAPS=1
NUM_THREADS=8
JF_SIZE=40000000
SOAP_ASSEMBLY=0
FLYE_ASSEMBLY=1
END
EOF

# 生成组装脚本
masurca config.txt

# 运行组装
./assemble.sh &> masurca.log
```

> 桥接句：`masurca config.txt` 与 `./assemble.sh` 等价能力由 `native/main.py` 的 `config` 与 `run` 子命令提供（`python main.py config config.txt`；`python main.py run --script assemble.sh --log masurca.log`）。

### 配置文件参数说明

| 参数                                              | 说明                                        |
| ----------------------------------------------- | ----------------------------------------- |
| `PE= p1 268 66 illumina.1.fastq illumina.2.fastq` | 二代 paired-end 数据（文库名、平均插入长度、标准差、R1、R2） |
| `PACBIO=`                                       | 三代 PacBio 数据路径                            |
| `GRAPH_KMER_SIZE=auto`                          | k-mer 长度自动选择                               |
| `USE_LINKING_MATES=0`                           | 不使用 linking mates                         |
| `FLYE_ASSEMBLY=1`                               | 使用 Flye 进行组装                              |
| `NUM_THREADS=8`                                 | 线程数                                       |
| `JF_SIZE=40000000`                              | Jellyfish hash 表大小                         |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方仅分发源码（release 无预编译资产），生产组装推荐官方源码编译。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n masurca-native -c conda-forge -c bioconda masurca=3.4.1
conda activate masurca-native
masurca --version   # 断言
```

> ⚠️ **官方警告**：MaSuRCA 官方 README 明确「通过 Bioconda 安装 MaSuRCA 不受支持」，可能因 Mummer 等包冲突导致安装损坏（组装报错 `mummer.pm`）；生产环境推荐下方的官方源码编译路线。

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap；仅 x86_64 Linux bottle）
brew tap brewsci/bio
brew install masurca
masurca --version   # 断言
```

> 📌 brew 公式为 `brewsci/bio/masurca`（v3.4.1，与 meta 登记版本一致）；homebrew-core 无 masurca（2026-09 核实 404）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/masurca:3.4.1--pl526h66be062_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/masurca:3.4.1--pl526h66be062_0 \
    masurca config.txt
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull masurca.sif docker://depot.galaxyproject.org/singularity/masurca:3.4.1--pl526h66be062_0
apptainer run -B $PWD:/data -H /data masurca.sif masurca /data/config.txt
```

### 4. 官方源码编译（官方推荐；无预编译二进制资产）

2026-09 核实：GitHub release v3.4.1 **无预编译产物**（assets 为空），官方仅分发源码；编译需 Boost：

```bash
wget https://github.com/alekseyzimin/masurca/releases/download/v3.4.1/MaSuRCA-3.4.1.tar.gz -P ~/software/
mkdir -p ~/software
tar zxf ~/software/MaSuRCA-3.4.1.tar.gz -C ~/software/
cd ~/software/MaSuRCA-3.4.1
export BOOST_ROOT=~/software/boost_1_64_0/    # 指定 Boost 安装根
./install.sh                                   # 编译 + 组装驱动脚本
export PATH=$PATH:~/software/MaSuRCA-3.4.1/bin/
masurca --version                              # 验证
```

> 💡 一键安装可走 `bash native/install.sh --method source --boost-root ~/software/boost_1_64_0`（含 make/g++ 探测与 BOOST_ROOT 校验）。
> 平台说明：MaSuRCA 仅支持 Linux；conda 版本亦仅 Linux，macOS 请走源码编译（官方注明可能性有限）。

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（组装需真实数据且耗时极长）
```

## 版本

* masurca 3.4.1（文档版本；bioconda::masurca=3.4.1 / 容器 tag `3.4.1--pl526h66be062_0`）
* 官方当前最新 4.1.4（bioconda=4.1.4）；本模块按文档 pin 3.4.1
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/masurca / depot.galaxyproject.org；本地不再自建容器）；生产组装推荐官方源码编译（BOOST_ROOT + ./install.sh）
* ⚠️ 官方警告 bioconda 安装可能因 mummer 冲突损坏

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/masurca/overview>
* **Docker**：`docker pull quay.io/biocontainers/masurca:3.4.1--pl526h66be062_0`（4.1.4 为 `4.1.4--h6b3f7d6_0`）
* **Singularity**：<https://depot.galaxyproject.org/singularity/masurca%3A3.4.1--pl526h66be062_0>
* **GitHub**：<https://github.com/alekseyzimin/masurca>（releases：v3.4.1 / v4.1.4，均仅源码）
* 安装方式（本地）：`mamba create -n masurca -c conda-forge -c bioconda masurca=3.4.1`（或用官方源码编译）
