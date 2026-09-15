# exonerate 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方「环境安装」，容器与 conda 信息记录于文末。
> 本模块仅登记 native 实现（官方 nf-core / snakemake-wrappers 均无 exonerate，见文末「官方实现登记」）。

***

## native 实现

# exonerate / native — 自包含同源序列比对基因预测驱动

exonerate 的本地自包含实现（`source_type: custom`、`type: native`；同源蛋白/DNA 比对基因预测）。

## 功能

exonerate 是一个通用的序列比对工具，支持多种比对类型，包括 DNA-DNA、蛋白-DNA 比对，常用于基于同源蛋白的基因结构预测。MAKER 使用它进行蛋白序列比对。

两个子命令覆盖教学文档（docs/10.md 第四节）的同源比对链路：

| 子命令        | 命令                                                                              | 作用                                   |
| ---------- | ------------------------------------------------------------------------------- | ------------------------------------ |
| `align`    | `exonerate --model <m> --showtargetgff yes [--bestn N] [--percent P] [--score S] <query> <target>` | 单次比对（protein2genome 最常用），命中以 GFF 写 stdout |
| `parallel` | `exonerate_parallel.pl --cpu N [--coverage_ratio R] [--evalue E] <protein.fasta> <genome.fasta>` | 全基因组并行比对封装                   |

常用比对模型：`protein2genome`（蛋白→基因组，最常用）、`est2genome`、`cdna2genome`、`coding2genome`、`protein2dna`、`affine:local`。

## 用法

```bash
# CLI 直跑（单条/批量 protein2genome 比对，输出 GFF）
python main.py align --model protein2genome --showtargetgff yes homolog.fasta genome.fasta -o exonerate.out
python main.py parallel --coverage_ratio 0.4 --evalue 1e-9 --threads 8 homolog.fasta genome.fasta

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`parallel` 注入 `--cpu N`）。

## 实战示例：同源蛋白辅助基因预测（protein2genome）

exonerate 是通用成对比对器，支持 DNA-DNA / 蛋白-DNA 等多种模式，常用于基于同源蛋白的基因结构预测。以下为典型用法；等价能力由 `native/main.py` 的 `align`（单次比对出 GFF）与 `parallel`（全基因组并行封装）子命令提供（见上「用法」）。

```bash
mkdir -p exonerate && cd exonerate

# 1) 准备输入：目标基因组（建议 hardmask 重复序列后）与同源蛋白
ln -s ../genome.hardmaskN.fasta genome.fasta
gzip -dc ../GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta

# 2) protein2genome 模式比对（--showtargetgff yes 让命中以 GFF 输出）
exonerate --model protein2genome --showtargetgff yes homolog.fasta genome.fasta > exonerate.out

# 3) 全基因组并行比对（封装脚本）
# exonerate_parallel.pl --cpu 8 --coverage_ratio 0.4 --evalue 1e-9 homolog.fasta genome.fasta
```

| 参数                        | 说明                       |
| ------------------------- | ------------------------ |
| `--model protein2genome`  | 指定比对模型（最常用于基因预测）         |
| `--showtargetgff yes`     | 输出目标 GFF 格式结果            |
| `--bestn 1`               | 仅显示最佳 n 个比对结果            |
| `--percent 50`            | 最小相似性百分比                 |
| `--score 100`             | 最小得分阈值                   |
| `--coverage_ratio` / `--evalue` | `parallel` 封装脚本的覆盖度 / E-value 阈值 |

> 说明：exonerate 运行较慢，全基因组水平建议用 `parallel`（`exonerate_parallel.pl`）并行化；MAKER 等综合工具内置 exonerate 调用。对于大规模数据，推荐使用 GenomeThreader 或 Diamond 等更快的工具作为替代。比对结果需要进行过滤和格式转换才能用于基因预测流程。

### 常用比对模型

| 模型             | 说明                           |
| ---------------- | ------------------------------ |
| `protein2genome` | 蛋白序列比对到基因组（最常用） |
| `est2genome`     | EST/cDNA 序列比对到基因组      |
| `cdna2genome`    | cDNA 序列比对到基因组          |
| `coding2genome`  | 编码序列比对到基因组           |
| `protein2dna`    | 蛋白序列比对到 DNA 序列        |
| `affine:local`   | 局部比对                       |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（EBI 预编译二进制 + 官方源码；bioconda → quay.io/biocontainers → depot.galaxyproject.org 已有官方镜像），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。**官方两条路线（预编译二进制包 / 源码编译）均保留**，预编译为首选。

### 1. 官方预编译二进制包（首选）

```bash
# EBI 官方预编译二进制（linux-x86_64）
curl -fSL -o exonerate-2.2.0-x86_64.tar.gz \
    http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0-x86_64.tar.gz
tar zxf exonerate-2.2.0-x86_64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/exonerate-2.2.0-x86_64/bin/' >> ~/.bashrc
source ~/.bashrc
exonerate --version
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `exonerate`，无 conda 时自动下载官方 EBI 预编译二进制到 `~/software/exonerate-<ver>` 并写 PATH；版本默认 2.2.0，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档（EBI FTP）
curl -fSL -o exonerate-2.2.0.tar.gz \
    http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0.tar.gz
tar zxf exonerate-2.2.0.tar.gz && cd exonerate-2.2.0
# 编译需要 glib / pcre（Debian：apt-get install -y --no-install-recommends build-essential pkg-config libglib2.0-dev libpcre3-dev）
./configure && make -j 4 && make install        # 或 --prefix=$HOME/software/exonerate-2.2.0
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n exonerate-native -c conda-forge -c bioconda exonerate=2.2.0
conda activate exonerate-native
exonerate --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install exonerate
exonerate --version      # 断言
# 注：brewsci/bio 公式当前为 2.4.0，与 meta 登记 2.2.0 略有差异（版本以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/exonerate:2.2.0--1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/exonerate:2.2.0--1 \
    exonerate --model protein2genome --showtargetgff yes homolog.fasta genome.fasta > exonerate.out
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull exonerate.sif docker://depot.galaxyproject.org/singularity/exonerate:2.2.0--1
apptainer run -B $PWD:/data -H /data exonerate.sif \
    exonerate --model protein2genome --showtargetgff yes /data/homolog.fasta /data/genome.fasta
```

## 官方实现登记（nf-core / snakemake-wrappers）

* **nf-core**：`modules/nf-core/exonerate` 不存在（2026-09-11 核实 404）→ 未建立 nextflow 说明层，Nextflow 场景请以本模块 `native/` 为兜底。
* **snakemake-wrappers**：`bio/exonerate` 不存在（2026-09-11 核实 404）→ 未建立 snakemake 说明层，Snakemake 场景请以本模块 `native/` 为兜底。

## 测试

```bash
bash test/run_test.sh   # align/parallel 退化为 argv 构造验证（不依赖已安装 exonerate）
```

## 版本

* exonerate 2.2.0（EBI 官方预编译二进制 / 官方源码；bioconda::exonerate=2.2.0，容器 tag `2.2.0--1`）
* 备注：bioconda 现有更新版本 2.4.0；本模块按教学文档固定 2.2.0
* 构建路线：官方预编译二进制（首选）+ 官方源码编译（并列）；另有官方镜像/conda 提供（quay.io/biocontainers / depot.galaxyproject.org；本地不再自建容器）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/exonerate/overview>
* **Docker**：`docker pull quay.io/biocontainers/exonerate:2.2.0--1`
* **Singularity**：<https://depot.galaxyproject.org/singularity/exonerate:2.2.0--1>
* **官方预编译二进制**：<http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0-x86_64.tar.gz>
* **官方源码**：<http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0.tar.gz>
* 安装方式（本地）：`mamba create -n exonerate -c conda-forge -c bioconda exonerate=2.2.0`
