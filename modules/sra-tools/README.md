# sra-tools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# sra-tools / native — 自包含 SRA 数据获取驱动

NCBI SRA Toolkit 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对应
`native/batch_prefetch.sh`（prefetch 下载）与
`batch_sra_to_fastq.sh` / `batch_sra_to_fastq_parallel.sh`（fastq-dump 转 FASTQ），
并补充官方推荐的高速版 fasterq-dump。

## 功能

三个子命令对应 bioconda sra-tools 包内的三个可执行：

| 子命令            | 可执行            | 作用                                                   |
| -------------- | -------------- | ---------------------------------------------------- |
| `prefetch`     | `prefetch`     | SRA accession → 本地 .sra（nanoseq 默认 `-f yes -t http`） |
| `fasterq-dump` | `fasterq-dump` | .sra → FASTQ（官方推荐高速版，`-e` 线程 / `-t` 临时目录）            |
| `fastq-dump`   | `fastq-dump`   | .sra → FASTQ（兼容旧版，nanoseq 脚本原用法 `--split-3 --gzip`）  |

## 用法

```bash
# CLI 直跑
python main.py prefetch SRR12345678 -O sra/ --threads 2
python main.py fasterq-dump sra/SRR12345678/SRR12345678.sra -O fastq/ --threads 8
python main.py fastq-dump sra/SRR12345678/SRR12345678.sra --split-3 --gzip -O fastq/

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：SRA 下载与 FASTQ 转换（双端拆分 / 序列名定制）

SRA Toolkit 是 NCBI SRA （Sequence Read Archive）数据库数据的标准存取工具集：`prefetch` 下载 SRA 文件、`fastq-dump` / `fasterq-dump` 将 SRA 转为 FASTQ（等价能力见上「用法」三个子命令）。以下为直接使用原生 CLI 的典型场景。

### 1. prefetch 下载 SRA 文件

```bash
# 下载的 SRA 默认保存在 ~/ncbi/public/sra/<accession>/ 目录下
prefetch SRR2131197

# 指定输出目录（文件位于 <dir>/<accession>/<accession>.sra）
prefetch SRR2131197 -O sra/
```

### 2. fastq-dump 转 FASTQ（双端拆分）

```bash
# --split-files：将双端数据拆分为 *_1.fastq 与 *_2.fastq 两个文件
fastq-dump --split-files SRR2131197.sra
# 生成：SRR2131197_1.fastq、SRR2131197_2.fastq

# 存在未配对 reads 时用 --split-3 更稳（可多产出第三个文件；本模块默认即此）
fastq-dump --split-3 --gzip -O fastq/ SRR2131197.sra
```

### 3. 自定义序列名格式（--defline-seq / -A）

```bash
# --defline-seq 自定义序列名格式：@$sn[_$rn]/$ri = 样本名_读取名/读取索引
fastq-dump --split-files --defline-seq '@$sn[_$rn]/$ri' input.sra

# -A 指定输出文件前缀
fastq-dump --split-files -A sample input.sra
```

### 4. 参数速查

| 参数 | 说明 |
|------|------|
| `--split-files` | 将双端数据拆分为两个文件（`*_1.fastq` / `*_2.fastq`） |
| `--defline-seq` | 自定义序列名格式，如 `@$sn[_$rn]/$ri` = 样本名_读取名/读取索引 |
| `-A` | 指定输出文件前缀 |

> 💡 **数据量注意**：数据量较大时建议先截取部分数据测试流程。粗估参考：基因组约 7.5 MB 的物种，取 900 万行（约 225 万条 reads）约为 50x 覆盖度；基因组约 4.6 MB 的物种（如 E. coli），取 800 万行（约 200 万条 reads）约为 80x 覆盖度；若计算性能足够，推荐使用全部数据以获得更完整的分析结果。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda（宿主机直跑 main.py / HPC 无 root）

```bash
mamba create -n sra-tools-native -c conda-forge -c bioconda sra-tools=3.2.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate sra-tools-native
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/sra-tools:3.2.0--h4304569_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/sra-tools:3.2.0--h4304569_0 prefetch SRR12345678 -O sra/
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull sra-tools.sif docker://depot.galaxyproject.org/singularity/sra-tools:3.2.0--h4304569_0
apptainer run -B $PWD:/data -H /data sra-tools.sif fastq-dump \
    /data/sra/SRR12345678/SRR12345678.sra --split-3 --gzip -O /data/fastq/
```

### 4. 二进制包安装（官方 SDK，无 conda / docker 依赖）

SRA Toolkit 由 NCBI 官方维护，预编译二进制在官网 SDK 下载目录与 GitHub release 提供；Debian/Ubuntu 亦收录（apt 包名为 `sra-toolkit`，版本较旧但工具集一致）。**宿主机与容器路线建议固定 3.2.0**（3.4.x 在部分环境出现过运行/下载问题）。

**方式一：二进制包安装（推荐）**

```bash
cd ~/software
# 官网 SDK 版本化下载（3.2.0；另有 sratoolkit.3.2.0-ubuntu64.tar.gz 等平台包，见 https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/3.2.0/）
wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/3.2.0/sratoolkit.3.2.0-centos_linux64.tar.gz -P ~/software/
tar zxf ~/software/sratoolkit.3.2.0-centos_linux64.tar.gz -C ~/software/
NEW=`ls -dt ~/software/sratoolkit* | head -n 1`
ln -sfn $NEW ~/software/sratoolkit
echo 'export PATH=$PATH:~/software/sratoolkit/bin/' >> ~/.bashrc
source ~/.bashrc

# 初始化配置（首次使用前）
vdb-config --interactive   # 或非交互：vdb-config -i
prefetch --version         # 验证安装
```

**方式二：CentOS 6 及以下兼容（→ 2.8.1）**

> **⚠️ 兼容性警告**：高版本 sratoolkit 依赖较新 glibc，在 CentOS 6 等老系统上可能出现 `SIGNAL - Segmentation fault` 错误，建议使用 2.8.1 或更低版本。

```bash
# 2.8.1（CentOS 6 兼容）
cd ~/software
wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.8.1/sratoolkit.2.8.1-centos_linux64.tar.gz
tar zxf sratoolkit.2.8.1-centos_linux64.tar.gz -C ~/software/
ln -sfn ~/software/sratoolkit.2.8.1-centos_linux64 ~/software/sratoolkit
echo 'export PATH=$PATH:~/software/sratoolkit/bin/' >> ~/.bashrc
source ~/.bashrc
vdb-config -i   # 初始化配置（首次使用前）
```

**版本兼容性说明**

官方针对 **CentOS 平台的预编译包仅提供到 3.2.0**（后续版本不再提供 CentOS 包）；可用平台：CentOS Linux 64 / Alma Linux 64 / Ubuntu 64 / macOS x86\_64 / macOS ARM64 / Windows 64。下载页：<https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/>

| 版本        | 大小  | 适用场景                               |
| :-------- | :-- | :--------------------------------- |
| **3.2.0** | 88M | CentOS 7+ / 现代 Linux（本模块推荐，见「方式一」） |
| **2.8.1** | 74M | CentOS 6 兼容版本（见「方式二」）              |
| **2.5.7** | 59M | 旧版 CentOS 兼容版本                     |

> **💡 Segmentation fault 解决方案**：该错误通常由高版本 sratoolkit 依赖的较新 glibc 与老版本 CentOS 不兼容导致。若必须使用新版功能，建议在支持较新 glibc 的容器环境（AlmaLinux 8+、Ubuntu 20.04+）中运行（见上「### 2. Docker / 3. Apptainer」路线），或升级宿主机系统。

* **官方 GitHub**：<https://github.com/ncbi/sra-tools>

* **apt（Debian/Ubuntu）**：`sudo apt install sra-toolkit`（含 prefetch / fasterq-dump / fastq-dump / vdb-config）

> 官方 SDK 包内为原生工具入口（仅工具，无 main.py）；需要 Schema/自省/参数注入时在**宿主机**（conda env 装 sra-tools=3.2.0，见下「版本」节）运行 `python main.py prefetch ...`（见「用法」）。

## 测试

```bash
bash test/run_test.sh   # prefetch/dump 需要网络 + 真实 SRA，本脚本退化为 argv 构造验证
```

## 版本

* sra-tools 推荐固定 **3.2.0**（bioconda；3.4.x 在部分环境出现过运行/下载问题，故 native 与容器路线统一 3.2.0；包内可执行 prefetch / fasterq-dump / fastq-dump）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/sra-tools / depot.galaxyproject.org；本地不再自建容器）

* 版本锚点对照：native / 容器 / conda 推荐 **3.2.0**；nf-core 子模块 pin sra-tools=3.2.1；snakemake-wrappers bio/sra-tools/fasterq-dump pin 3.4.1（本模块 snakemake 本地规则 `sra-tools.yaml` 同 pin 3.4.1，如需避开 3.4.1 可将其同步改为 3.2.0）

## 历史留存

原始批处理脚本 `batch_prefetch.sh` / `batch_sra_to_fastq.sh` / `batch_sra_to_fastq_parallel.sh`（单一命令的批量循环：prefetch 下载 / fastq-dump 转 FASTQ，串行或 GNU parallel）保留于本模块 `native/`（硬编码项目路径，仅供追溯对照 / 一键运行，正式能力请走 `main.py` 的 prefetch / fasterq-dump / fastq-dump 原子子命令）。

***

## snakemake 实现

# sra-tools / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/sra-tools` 目前只有 `fasterq-dump` 一个 wrapper，
因此本目录为 prefetch（下载）与 fastq-dump / fasterq-dump（转换）提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。
td2 式：每 rule 一个 config 驱动 `.smk`，共用同目录 conda env `sra-tools.yaml`
（bioconda `sra-tools=3.4.1`）。

## 规则文件

* `sra_prefetch.smk` — `rule sra_prefetch`（下载）：`prefetch -f yes -t http -O <dir> <srr_id>`

* `sra_fastq_dump.smk` — `rule sra_fastq_dump`（转换）：`fastq-dump --split-3 --gzip -O <dir> <sra>`

* `sra_fasterq_dump.smk` — `rule sra_fasterq_dump`（高速转换）：`fasterq-dump <sra> --split-3 -O <dir> -e N -t <tmpdir>`（官方推荐高速版）

* `sra-tools.yaml` — conda env（bioconda `sra-tools=3.4.1`，提供 prefetch / fasterq-dump / fastq-dump）

去除 while 串行循环 / GNU parallel 外部依赖 / 绝对路径
（`./sratoolkit.3.2.0-centos_linux64/bin/`）；失败 SRR 列表由 Snakemake 的重试/日志机制覆盖，
不再写 `failed_*.txt`。dump 规则输出为 `directory()`——`--split-3` 的产物按文库布局命名
（SE 单文件 / PE `_1`/`_2`），无法静态预知文件名，详见两 .smk 头注。

## 用法（config 契约见各 .smk 头注与软件级 meta.yaml `snakemake_include_hint`）

```python
# Snakefile 中（按需 include）
include: "modules/sra-tools/snakemake/sra_prefetch.smk"
include: "modules/sra-tools/snakemake/sra_fastq_dump.smk"
include: "modules/sra-tools/snakemake/sra_fasterq_dump.smk"

rule all:
    input: config["sra_prefetch_sra"]   # 或 sra_dump_dir（转换产物目录）
```

```bash
# 独立运行
snakemake -s modules/sra-tools/snakemake/sra_prefetch.smk \
    --config sra_srr_id=SRR12345678 sra_outdir=sra_out --cores 2 --use-conda
snakemake -s modules/sra-tools/snakemake/sra_fastq_dump.smk \
    --config sra_input_sra=sra_out/SRR12345678/SRR12345678.sra --cores 4 --use-conda
```

## 依赖环境

conda env 文件同目录 `sra-tools.yaml`（`conda:` 相对 .smk 目录解析，`--use-conda` 时自动创建）：

```yaml
# snakemake/sra-tools.yaml
name: sra-tools
channels: [conda-forge, bioconda, defaults]
dependencies:
  - bioconda::sra-tools==3.4.1
```

## 与其它实现的关系

* `fasterq-dump` 场景也可直接切到官方 wrapper：`wrapper: "v3.13.0/bio/sra-tools/fasterq-dump"`

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# sra-tools native Conda 环境配方
# 离线兜底：可另存为 sra-tools-native.yml 后 mamba env create -f sra-tools-native.yml；在线推荐上方 mamba create 直装命令
# 说明：sra-tools 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      官方镜像（quay.io/biocontainers/sra-tools）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def（见上「环境安装」）。
name: sra-tools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - sra-tools=3.2.0    # 提供 prefetch / fasterq-dump / fastq-dump
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/sra-tools/overview>

* **Docker**：`docker pull quay.io/biocontainers/sra-tools:3.2.0--h4304569_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/sra-tools%3A3.2.0--h4304569_0>

* 安装方式（本地）：`mamba create -n sra-tools -c conda-forge -c bioconda sra-tools=3.2.0`

