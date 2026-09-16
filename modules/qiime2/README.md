# qiime2 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> QIIME 2 官方只以 **Conda 发行版**（amplicon conda.yml）分发，另有项目官方 Quay 发行版镜像；bioconda / quay.io/biocontainers / depot.galaxyproject.org 三渠道均无 qiime2 包与镜像。

***

## native 实现

# qiime2 / native — 自包含「插件-动作」两段式驱动

QIIME 2（2026.1 amplicon 发行版）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

QIIME 2（Quantitative Insights Into Microbial Ecology 2）是 QIIME 1.x 的下一代版本，采用全新的 Artifact 系统（QZA/QZV 文件格式），支持 DADA2 和 Deblur 去噪算法，提供更好的可重复性和分析流程管理。

QIIME 2 的 CLI 是「插件-动作」两段式 `qiime <plugin> <action> [options]`；本驱动把子命令写成**点分两段式键**（如 `tools.import`、`feature-table.summarize`），由 `build_command` 还原为 `qiime <plugin> <action> ...` 的 argv，动作参数**原样透传**。覆盖文档用到的 29 个动作：

| 插件 | 动作 |
| ---- | ---- |
| `tools` | `import` · `export` · `peek` · `view` |
| `demux` | `emp-single` · `summarize` |
| `dada2` | `denoise-single` · `denoise-paired` |
| `deblur` | `denoise-16S` |
| `feature-table` | `summarize` · `tabulate-seqs` · `filter-samples` |
| `alignment` | `mafft` · `mask` |
| `phylogeny` | `fasttree` · `midpoint-root` |
| `diversity` | `core-metrics-phylogenetic` · `alpha-group-significance` · `beta-group-significance` |
| `emperor` | `plot` |
| `feature-classifier` | `extract-reads` · `fit-classifier-naive-bayes` · `classify-sklearn` |
| `taxa` | `barplot` · `collapse` |
| `composition` | `add-pseudocount` · `ancom` |
| `metadata` | `tabulate` |
| （顶层命令） | `info` |

**线程自动注入**：对支持并行的动作注入线程参数——`dada2.*` / `alignment.mafft` / `phylogeny.fasttree` 用 `--p-n-threads`，`feature-classifier.*` / `diversity.core-metrics-phylogenetic` 用 `--p-n-jobs`；用户已自带该参数则不覆盖。

## 用法

```bash
# CLI 直跑（动作参数原样透传，按官方「插件-动作」语义书写）
python main.py tools.import --type EMPSingleEndSequences \
    --input-path 01.emp-single-end-sequences \
    --output-path 03.qimme2_prepare_data/emp-single-end-sequences.qza

python main.py dada2.denoise-single \
    --i-demultiplexed-seqs demux.qza --p-trim-left 0 --p-trunc-len 120 \
    --o-representative-sequences rep-seqs.qza --o-table table.qza --threads 8

python main.py feature-classifier.classify-sklearn \
    --i-classifier gg-13-8-99-515-806-nb-classifier.qza \
    --i-reads rep-seqs.qza --o-classification taxonomy.qza --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（放在子命令之后）。

## 实战示例：EMP 单端扩增子全流程

QIIME 2 以 Artifact（QZA/QZV）贯穿全流程，DADA2 去噪 + 系统发育 + 多样性 + 物种分类是标准扩增子链路。以下为典型端到端用法；等价能力由 `native/main.py` 的对应「插件-动作」子命令提供（见上「用法」）。

### 1. 导入 EMP 数据 + 拆样 + 导出

```bash
qiime tools import --type EMPSingleEndSequences \
    --input-path 01.emp-single-end-sequences \
    --output-path 03.qimme2_prepare_data/emp-single-end-sequences.qza

qiime demux emp-single \
    --i-seqs 03.qimme2_prepare_data/emp-single-end-sequences.qza \
    --m-barcodes-file 03.qimme2_prepare_data/sample-metadata.tsv \
    --m-barcodes-category BarcodeSequence \
    --o-per-sample-sequences 03.qimme2_prepare_data/demux.qza

qiime demux summarize --i-data demux.qza --o-visualization demux.qzv
qiime tools export --output-dir 02.Illumina_fastq_data demux.qza
```

### 2. DADA2 去噪建特征表（`--p-n-threads 0` = 全部 CPU）

```bash
qiime dada2 denoise-single \
    --i-demultiplexed-seqs demux.qza \
    --p-trim-left 0 --p-trunc-len 120 \
    --o-representative-sequences rep-seqs.qza --o-table table.qza \
    --p-n-threads 0
qiime feature-table summarize --i-table table.qza --o-visualization table.qzv \
    --m-sample-metadata-file sample-metadata.tsv
```

### 3. 系统发育树（MAFFT → mask → FastTree → midpoint-root）

```bash
qiime alignment mafft --i-sequences rep-seqs.qza --p-n-threads -1 --o-alignment aligned-rep-seqs.qza
qiime alignment mask --i-alignment aligned-rep-seqs.qza --o-masked-alignment masked-aligned-rep-seqs.qza
qiime phylogeny fasttree --i-alignment masked-aligned-rep-seqs.qza --p-n-threads -1 --o-tree unrooted-tree.qza
qiime phylogeny midpoint-root --i-tree unrooted-tree.qza --o-rooted-tree rooted-tree.qza
```

### 4. 多样性 + PCoA + 物种分类 + ANCOM

```bash
qiime diversity core-metrics-phylogenetic --i-phylogeny rooted-tree.qza --i-table table.qza \
    --p-sampling-depth 1109 --m-metadata-file sample-metadata.tsv --output-dir core-metrics-results
qiime emperor plot --i-pcoa core-metrics-results/unweighted_unifrac_pcoa_results.qza \
    --m-metadata-file sample-metadata.tsv --o-visualization core-metrics-results/unweighted-unifrac-emperor.qzv

qiime feature-classifier classify-sklearn \
    --i-classifier gg-13-8-99-515-806-nb-classifier.qza \
    --i-reads rep-seqs.qza --o-classification taxonomy.qza
qiime taxa barplot --i-table table.qza --i-taxonomy taxonomy.qza \
    --m-metadata-file sample-metadata.tsv --o-visualization taxa-bar-plots.qzv

qiime feature-table filter-samples --i-table table.qza --m-metadata-file sample-metadata.tsv \
    --p-where "BodySite='gut'" --o-filtered-table gut-table.qza
qiime composition add-pseudocount --i-table gut-table.qza --o-composition-table comp-gut-table.qza
qiime composition ancom --i-table comp-gut-table.qza --m-metadata-file sample-metadata.tsv \
    --m-metadata-category Subject --o-visualization ancom-Subject.qzv
```

## 环境安装（官方 Conda 发行版 / 官方 Quay 镜像优先；本地配方兜底）

> 官方现状（2026-09 核实）：QIIME 2 官方只以 **Conda 发行版**（`qiime2-amplicon-*-conda.yml`）分发，另有项目官方 **Quay 发行版镜像**；bioconda（qiime2 → 404）/ quay.io/biocontainers（无 qiime2）/ depot.galaxyproject.org（无 qiime2）三渠道均无，故本模块提供自建 `Dockerfile`/`Apptainer.def` 兜底（micromamba 建官方环境）。

### 1. Conda（官方发行版，首选）

```bash
# 方式一：联网安装（以 2026.1 为例；环境文件为官方分发，随 dev 分支更新）
conda env create --name qiime2-amplicon-2026.1 \
    --file https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/2026.1/amplicon/released/qiime2-amplicon-ubuntu-latest-conda.yml
conda activate qiime2-amplicon-2026.1
qiime info   # 断言：打印 QIIME 2 release 2026.1

# 方式二：官方预打包的 miniconda 环境（解压即用）
tar zxf ~/software/miniconda3_for_QIIME2.tar.gz -C ~/software
```

> 一键安装直接 `bash native/install.sh`（自动下载官方 2026.1 amplicon 环境文件并建 `qiime2-amplicon-2026.1` 环境，安装后 `qiime --version` 断言）。
>
> Homebrew：homebrew-core（`formulae.brew.sh/api/formula/qiime2.json`）与 brewsci/bio（`Formula/qiime2.rb`）均 404（2026-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker

官方 Quay 发行版镜像（QIIME 2 项目官方维护，推荐直接拉取；tag 含 2026.1）：

```bash
docker pull quay.io/qiime2/amplicon:2026.1
# 必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/qiime2/amplicon:2026.1 tools.peek /data/demux.qza
```

本地自建兜底配方（三渠道无官方镜像；micromamba 建官方 2026.1 amplicon 环境）：

```bash
docker build -t bioskills/qiime2:2026.1 native/
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/qiime2:2026.1 dada2 denoise-single --i-demultiplexed-seqs /data/demux.qza \
    --p-trunc-len 120 --o-table /data/table.qza --o-representative-sequences /data/rep-seqs.qza
```

### 3. Apptainer / Singularity

depot.galaxyproject.org **无** qiime2 预构建 sif（2026-09 核实 404），故二选一：

```bash
# A) 从官方 Quay 镜像转换（推荐）
apptainer pull qiime2.sif docker://quay.io/qiime2/amplicon:2026.1

# B) 本地构建自建配方（micromamba 建官方环境）
apptainer build qiime2-2026.1.sif native/Apptainer.def
apptainer run -B $PWD:/data -H /data qiime2-2026.1.sif tools.peek /data/demux.qza
```

## 测试

```bash
bash test/run_test.sh   # 命令构造/线程注入/parser/CLI stub 自省为常驻断言（不下载/不建 conda env）
```

## 容器与 Conda 链接

* **官网**：<https://qiime2.org/> ｜ **文档**：<https://docs.qiime2.org/> ｜ **Quickstart**：<https://library.qiime2.org/quickstart/amplicon>
* **官方发行版 conda.yml**：<https://github.com/qiime2/distributions>（2026.1 → `2026.1/amplicon/released/qiime2-amplicon-ubuntu-latest-conda.yml`）
* https://packages.qiime2.org/qiime2/2026.7/qiime2/released/
* **官方 Quay 镜像（推荐）**：`docker pull quay.io/qiime2/qiime2:2026.7`（tag 含 2026.1 / latest / 2025.10 …）
* **本地自建配方**：`native/Dockerfile` + `native/Apptainer.def`（三渠道无官方镜像时兜底）
* **bioconda**：qiime2 无包（`api.anaconda.org/package/bioconda/qiime2` 404）｜ **depot sif**：无（404）
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）

## 版本

* QIIME 2 **2026.1**（amplicon 发行版；官方 conda.yml 与 Quay 镜像 `quay.io/qiime2/amplicon:2026.1` 对齐）
* License：**BSD-3-Clause**（QIIME 2 development team）
* nf-core / snakemake-wrappers：无官方模块（2026-09 核实 `modules/nf-core/qiime2`、`bio/qiime2` 均 404）→ 不登记官方说明层
