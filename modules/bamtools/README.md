# bamtools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# bamtools / native

BamTools 是处理 BAM 格式文件的高通量测序工具集（C++ 库 + 命令行工具），提供格式转换（convert）、统计（stats/count）、过滤（filter）、索引（index）、排序（sort）等核心能力。官网：<https://github.com/pezmaster31/bamtools>

自包含的 bamtools 驱动实现（`source_type: custom`）。

## 能力

覆盖 bamtools 高频子命令，Iso-Seq 场景下 BAM → FASTA/FASTQ 转换首选：

| 子命令       | 说明                                             |
| --------- | ---------------------------------------------- |
| `convert` | BAM → fasta/fastq/sam/bed/json/pileup/yaml（核心） |
| `count`   | 统计 BAM 比对数量                                    |
| `stats`   | 输出 BAM 基本统计                                    |
| `header`  | 打印 BAM header                                  |
| `index`   | 建立 .bai 索引                                     |
| `sort`    | 按 region/name/size 排序 BAM                      |

## 快速开始

### 1. CLI 调用

```bash
python main.py convert --bam refine.bam --outdir flnc --format fasta --prefix sample
python main.py stats --bam refine.bam
python main.py sort --bam in.bam --out sorted.bam --threads 8
python main.py index --bam sorted.bam
```

### 2. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py convert --bam x.bam --dry-run   # 只打印构建出的命令
```

### 3. 测试

```bash
bash test/run_test.sh
```

测试数据由 `test/generate_data.py` 用纯 Python 标准库动态生成合法 BGZF/BAM，
不依赖 samtools/pysam。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bamtools -c conda-forge -c bioconda bamtools=2.5.2
conda activate bamtools
bamtools --version
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 2.5.3，与 meta 登记 2.5.2 略有差异（版本以 formula 为准）
brew install bamtools
bamtools --version   # 断言
```

> 宿主机直跑 `python main.py`（convert / count / stats / header / index / sort 子命令）亦可使用文末「Conda 环境」节配方建环境（`name: bamtools-native`，含 python/pyyaml，bamtools 同为 2.5.2）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bamtools:2.5.2--hdcf5f25_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bamtools:2.5.2--hdcf5f25_2 \
    convert -format fasta -in /data/refine.bam -out /data/sample.fasta
```

> 容器内为原生工具入口；需要 Schema/自省/参数注入时在**宿主机**（已装 bamtools 或 conda env）运行 `python main.py <subcommand> ...`。
> native 固定 2.5.2（quay.io/biocontainers/bamtools:2.5.2--hdcf5f25_2，流程原配 tag）；bioconda 最新 2.5.3 容器 tag 见文末「容器与 Conda 链接」。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull bamtools.sif docker://depot.galaxyproject.org/singularity/bamtools:2.5.2--hdcf5f25_2
apptainer run -B $PWD:/data -H /data bamtools.sif \
    convert -format fasta -in /data/refine.bam -out /data/sample.fasta
```

### 4. 二进制包安装（官方源码编译 / apt，无 conda / docker 依赖）

* **GitHub Releases**：<https://github.com/pezmaster31/bamtools/releases>（官方仅分发源码 tar.gz，需 cmake + g++ 编译安装）

```bash
# 源码编译（以 v2.5.2 为例；需系统已装 cmake 与 g++）
wget https://github.com/pezmaster31/bamtools/archive/v2.5.2.tar.gz -P ~/software/
tar zxf ~/software/v2.5.2.tar.gz -C ~/software/
cd ~/software/bamtools-2.5.2/
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/software/bamtools
make -j 4
make install
echo 'export PATH=$PATH:~/software/bamtools/bin/' >> ~/.bashrc
source ~/.bashrc

# 验证安装
bamtools --version
```

> Debian / Ubuntu 亦可直接 `sudo apt install bamtools`（发行版仓库自带，版本以 apt 源为准）。

## 版本说明

* **native 二进制**：`bamtools 2.5.2`，由**官方镜像/conda 提供**（quay.io/biocontainers/bamtools、bioconda bamtools=2.5.2；宿主机安装用 mamba/conda）。

* 与流程原配版本一致（`quay.io/biocontainers/bamtools:2.5.2--hdcf5f25_2`）；
  snakemake-wrappers 侧已 bump 到 2.5.3，2.5.x API 兼容。

## 性能优化约定

* **线程**：bamtools CLI 无通用 `-@` 参数，`--threads` 作为契约字段接收，
  并在 `optimization.per_subcommand_threads` 中给出 sort 8 线程的调度建议。

* **临时目录**：`--tmpdir` 可覆盖 `TMPDIR`；`sort` 中间文件写入 `$TMPDIR`。

* **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 历史留存

BAM 转 FASTA/FASTQ 等能力由 `main.py convert` 覆盖（正式入口为 `main.py`）。

***

## snakemake 实现

# bamtools / snakemake / local — 自维护 Snakemake rule

td2 式单规则实现（config 驱动、自包含，不依赖 `workflow/lib/helpers.py`）；BAM 转换 + 写 `versions.yml` 属多步逻辑，用 `script:` + 同目录 wrapper（docker/native/conda 经共享 `modules/docker_wrapper.py` 解析）。

## 文件

| 文件                     | 作用                                                                   |
| ---------------------- | -------------------------------------------------------------------- |
| `bamtools_convert.smk` | 单规则：`bamtools convert -format <fmt> -in <bam> -out <out>`（config 驱动） |
| `bamtools_convert.py`  | wrapper（两级注入 `modules/`；docker/native/conda 三模式 + 写 versions.yml）    |
| `bamtools.yaml`        | conda env（bioconda `bamtools=2.5.2`，与 native 版本锚点一致）                 |

## 使用（config 契约见 bamtools\_convert.smk 头注与软件级 meta.yaml `snakemake_include_hint`）

在 Snakefile 中：

```python
include: "modules/bamtools/snakemake/bamtools_convert.smk"

rule all:
    input: config["bamtools_output"]   # 输出：<outdir>/<BAM 名>.<format> + .versions.yml
```

独立运行：

```bash
snakemake -s modules/bamtools/snakemake/bamtools_convert.smk \
    --config bamtools_input_bam=refine.bam --cores 2 --use-conda
```

可选 `config["bamtools"]`（缺省自动跳过；`exec_mode` 支持 conda/docker/native）：

```yaml
# config.yaml
exec_mode: conda
bamtools:
  format: "fastq"          # convert 目标格式（默认 fasta）
  extra_params: ""         # 透传附加参数
```

## 规则设计说明

* docker/native 模式由 wrapper 的 `docker_wrapper` 分派（无需流程级 `BAMTOOLS_DOCKER_IMAGE` 配置）；
  输入路径用显式 config 键 `bamtools_input_bam`（无固定 `results/refine/{sample}/{sample}.chunk{n}.bam` 模板）。

* `bamtools.bin` / `format` 由 `config["bamtools"]` 读取并内联默认值：

  * `bamtools_bin: "bamtools"`、`format: "fasta"`

* 规则写 `versions.yml`（与 nf-core 模块风格一致）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bamtools native Conda 环境配方
# 离线兜底：可另存为 bamtools-native.yml 后 mamba env create -f bamtools-native.yml；在线推荐上方 mamba create 直装命令
# 说明：容器走官方镜像（quay.io/biocontainers/bamtools），不再维护本地配方；
#      本文件仅作 HPC 无 root 场景 / 非容器场景的 Conda 兜底。
name: bamtools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bamtools=2.5.2
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/bamtools/overview>

* **Docker（最新）**：`docker pull quay.io/biocontainers/bamtools:2.5.3--he132191_0`

* **Singularity（最新）**：<https://depot.galaxyproject.org/singularity/bamtools%3A2.5.3--he132191_0>

* 安装方式（本地）：`mamba create -n bamtools -c conda-forge -c bioconda bamtools=2.5.3`

* 注：流程原配版本见上文（bamtools 历史版本），本链接为 bioconda 最新容器。

