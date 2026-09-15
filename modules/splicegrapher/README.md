# splicegrapher 软件模块

> 汇总说明：本 README 记录 splicegrapher native 实现的用法与环境安装。官方 **无 bioconda 包、无官方容器、
> 无预编译二进制**（2026-09 逐渠道核实全无），故走**官方源码安装优先 + 自建容器兜底**；官方 nf-core /
> snakemake-wrappers 亦无（仅登记于 `meta.yaml software_versions` 与本文档）。

***

## native 实现

# splicegrapher / native — 自包含可变剪接分析驱动

SpliceGrapher 0.2.7 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

SpliceGrapher 是一个用于可变剪接分析的工具，可以从 RNA-seq 数据中识别可变剪接事件。

四个子命令对应官方 `scripts/` 下的四个脚本（可变剪接流水线）：

| 子命令                    | 命令                                                                       | 作用                        |
| ---------------------- | ------------------------------------------------------------------------ | ------------------------- |
| `build_classifiers`    | `build_classifiers.py -d gt,gc -a ag [-n N] [-l <log>]`                   | 训练剪接位点 SVM 分类器（输出 classifiers.zip） |
| `sam_filter`           | `sam_filter.py <input.sam> <classifiers.zip> [-o <filtered.sam>] [-v]`    | 用分类器过滤比对                  |
| `predict_graphs`       | `predict_graphs.py <input.sam> [-o <outdir>] [-v]`                        | 预测剪接图                     |
| `realignment_pipeline` | `realignment_pipeline.py <graph_dir> -1 <fq1> -2 <fq2>`                   | 剪接图重比对                    |

> 运行前需设置环境变量 `SG_FASTA_REF`（参考基因组 FASTA）与 `SG_GENE_MODEL`（基因模型 GFF3/GFF）。
> 输入 SAM **不能含 softclip**（`hisat2 ... --no-softclip`）。脚本无统一线程参数，`--threads` 仅用于调度。

## 用法

```bash
export SG_FASTA_REF=$PWD/genome.fasta
export SG_GENE_MODEL=$PWD/genome.gff3

# 1. 训练分类器（-d gt,gc -a ag；-n 可减小训练样本加速）
python main.py build_classifiers -d gt,gc -a ag -n 400 -l create_classifiers.log

# 2. 过滤比对
python main.py sam_filter filtered_in.sam classifiers.zip -o filtered.sam -v

# 3. 预测剪接图
python main.py predict_graphs filtered.sam -v

# 4. 重新比对（-1/-2 为双端 FASTQ）
python main.py realignment_pipeline graphs/ -1 A.1.fastq -2 A.2.fastq

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`--threads` 不注入脚本）。

## 实战示例：RNA-seq 可变剪接事件识别

SpliceGrapher 从 RNA-seq 比对 + 基因模型出发，用 SVM 分类器识别真实剪接位点，预测剪接图并统计可变剪接。
以下为有参可变剪接分析典型用法（等价能力由 `native/main.py` 的子命令提供，见上「用法」）：

```bash
# 0. 准备输入：hisat2 比对时禁用 softclip；SAM 排序
hisat2 -x genome -p 4 --rna-strandness RF --no-softclip -1 A.1.fastq -2 A.2.fastq -S hisat2.sam
samtools sort -@ 8 -O sam -o hisat2.sorted.sam hisat2.sam
export SG_FASTA_REF=$PWD/genome.fasta
export SG_GENE_MODEL=$PWD/genome.gff3

# 1. 创建分类器
mkdir -p 1.create_classifiers && cd 1.create_classifiers
python ../main.py build_classifiers -d gt,gc -a ag -l create_classifiers.log
grep roc *.cfg
cd ..

# 2. 过滤比对（依赖上一步的 classifiers.zip）
mkdir -p 2.filter_alignments && cd 2.filter_alignments
ln -s ../1.create_classifiers/classifiers.zip ./
python ../main.py sam_filter ../hisat2.sorted.sam classifiers.zip -o filtered.sam -v
cd ..

# 3. 预测剪接图
mkdir -p 3.predict_graphs && cd 3.predict_graphs
python ../main.py predict_graphs ../2.filter_alignments/filtered.sam -v
cd ..

# 4. 重新比对（可选，SpliceGrapherXT -> 转录本预测）
mkdir -p 4.realignment_pipeline && cd 4.realignment_pipeline
python ../main.py realignment_pipeline ../3.predict_graphs/ -1 ../A.1.fastq -2 ../A.2.fastq
```

### 参数说明

| 参数     | 说明                                          |
| ------ | ------------------------------------------- |
| `-d`   | 供体剪接位点类型（build_classifiers，默认 gt,gc）        |
| `-a`   | 受体剪接位点类型（build_classifiers，默认 ag）          |
| `-n`   | 每个位点训练样本数（默认 2000；减小可加速）                    |
| `-l`   | 日志文件（build_classifiers）                     |
| `-o`   | 输出文件/目录（sam_filter/predict_graphs）          |
| `-v`   | 详细输出（sam_filter/predict_graphs）             |
| `-1/-2`| 双端 FASTQ（realignment_pipeline）               |

## 依赖说明（务必先装）

SpliceGrapher 依赖较多，且部分为 Python 2.7 时代代码：

* **Python 2.7**（0.2.7 源码为 py2 语法）与 **PyML**（剪接位点分类器训练，≥0.7.14）
* **matplotlib**（可视化，≥1.1.0）、**pysam**（SAM/BAM 读写，≥0.5）
* **IsoLasso**（可选 SpliceGrapherXT 转录本预测，≥2.6.1；见本仓库 `isolasso` 模块）
* **cufflinks**（可选表达量计算）、**samtools**（BAM）、**hisat2**（比对，需 `--no-softclip`）
* 另需 UCSC `gtfToGenePred` / `genePredToBed`（IsoLasso 流程可选）

## 环境安装（无官方镜像/conda；官方源码安装优先，自建容器兜底）

官方 **无 bioconda 包、无 quay/depot 镜像、无预编译二进制**（2026-09 核实全无）→ 只能**官方源码安装**或**自建容器**。

### 1. 官方源码安装（首选）

官方发布站 SourceForge 仅提供源码包；安装方式为 `python setup.py build && python setup.py install`：

PyML 是一个 Python 机器学习库，SpliceGrapher 使用它进行分类器训练。

```bash
# 依赖（python2.7）
# https://sourceforge.net/projects/pyml/
python2 -m pip install --user setuptools PyML matplotlib pysam -i https://mirrors.aliyun.com/pypi/simple/

# 下载并安装
wget https://sourceforge.net/projects/splicegrapher/files/SpliceGrapher-0.2.7.tgz -P ~/software/
tar zxf ~/software/SpliceGrapher-0.2.7.tgz -C ~/software/
cd ~/software/SpliceGrapher-0.2.7
python2 setup.py build
python2 setup.py install --prefix=$HOME/software/splicegrapher-0.2.7
export PATH=$HOME/software/splicegrapher-0.2.7/bin:$PATH
python2 -c 'import SpliceGrapher; print(SpliceGrapher.__version__)'   # 断言 0.2.7
```

> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时建 `python=2.7` 环境并源码安装；否则用系统
> python2 源码安装到 `~/software/splicegrapher-<ver>`；版本默认 0.2.7，内嵌官方源码包 sha256 校验）。
> 用法：`bash native/install.sh --help`。

### 2. Conda（备选；**官方无 bioconda 包**）

官方无 conda 包，下述为第三方/自建环境（使用 conda-forge 的 python 2.7 承载官方源码包）：

```bash
mamba create -n splicegrapher -c conda-forge python=2.7 pip samtools hisat2 numpy
conda activate splicegrapher
pip install setuptools PyML matplotlib pysam
# 再按上方「官方源码安装」在本环境内 python2 setup.py build && install
```

> Homebrew：homebrew-core 与 brewsci/bio 均无 splicegrapher 公式（2026-09 核实），故不提供 brew 安装块。

### 3. Docker（自建镜像）

官方无镜像，本模块提供自建配方（`native/Dockerfile`；debian:bullseye-slim + python2.7 + 官方源码 install）：

```bash
# 构建（context 必须是 modules/ 层）
docker build -t bioskills/splicegrapher:0.2.7 -f modules/splicegrapher/native/Dockerfile modules/
# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    -e SG_FASTA_REF=/data/genome.fasta -e SG_GENE_MODEL=/data/genome.gff3 \
    bioskills/splicegrapher:0.2.7 predict_graphs /data/filtered.sam -v
```

### 4. Apptainer / Singularity（自建 sif）

```bash
cd modules && apptainer build splicegrapher-0.2.7.sif splicegrapher/native/Apptainer.def
apptainer run -B $PWD:/data -H /data splicegrapher-0.2.7.sif predict_graphs /data/filtered.sam -v
```

## 测试

```bash
bash test/run_test.sh   # 四个子命令为 argv 构造验证；脚本已安装时额外做可执行探测
```

## 版本

* splicegrapher 0.2.7（SourceForge 官方源码包 SpliceGrapher-0.2.7.tgz）
* 构建路线：**自建容器/源码安装**（官方渠道 bioconda→quay.io/biocontainers→depot.galaxyproject.org 2026-09
  核实全无：bioconda API 404、quay API 401、depot 无）
* Python 2.7 时代代码（依赖 PyML）；自建镜像基础镜像取 debian:bullseye-slim

## 官方实现登记（不建目录）

* **nf-core**：`modules/nf-core/splicegrapher` 不存在（2026-09 核实 `meta.yml` 404）。
* **snakemake-wrappers**：`bio/splicegrapher` 不存在（2026-09 核实 `environment.yaml` / `wrapper.py` 均 404）。

## 容器与 Conda 链接

* **官方站点**：<http://splicegrapher.sourceforge.net/>
* **源码包**：<https://sourceforge.net/projects/splicegrapher/files/SpliceGrapher-0.2.7.tgz>
* **Bioconda**：（无——api.anaconda.org/package/bioconda/splicegrapher 404，2026-09 核实）
* **Docker/Singularity**：（官方无）本仓库自建：`native/Dockerfile` + `native/Apptainer.def`
* **Homebrew**：（无——homebrew-core 与 brewsci/bio 均 404）
* 安装方式（本地）：`bash native/install.sh`（官方源码安装，见上）
