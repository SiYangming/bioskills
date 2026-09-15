# pathview 软件模块

> 汇总说明：pathview 是 Bioconductor 的 KEGG 通路富集可视化 R 包（无独立命令行二进制），
> 本模块以 `Rscript` 驱动 `pathview::pathview()` 完成通路着色；安装方式见「环境安装」，
> 容器与 conda 链接见文末。conda / 容器规范包名为 **bioconductor-pathview**。
>
> 官方渠道已维护（2026-09 核实）：bioconda `bioconductor-pathview=1.50.0`、
> `quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0`；
> 唯 depot.galaxyproject.org 未收录（404），Apptainer 走 quay docker:// 直拉。

***

## native 实现

# pathview / native — Rscript 驱动的 KEGG 通路可视化

pathview 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（GPL-3.0-or-later，v1.50.0），无 CLI，因此 `native/main.py` 以
`Rscript -e <内嵌 R 驱动> <params.tsv>` 方式调用 `pathview::pathview()`。

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `plot` | `Rscript -e <driver> params.tsv`（内部 `pathview::pathview`） | 把基因/化合物数值（如差异表达 log2FC）映射到 KEGG 通路图，按数值着色输出 PNG/XML；支持多通路 id、物种与 id 类型选择 |

## 用法

```bash
# CLI 直跑：单通路基因着色（study.ko.txt 首列 gene id、次列数值）
python main.py plot --kegg-ids ko00010 --gene-data study.ko.txt \
    --species ko --out-dir kegg_out --out-suffix study1 --threads 4

# 多通路 + 基因/化合物双数据
python main.py plot --kegg-ids ko00010,ko00020 --gene-data study.ko.txt \
    --cpd-data cpd.txt --out-dir kegg_out --out-suffix both

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 透传 R 底层 BLAS 的
OMP/OPENBLAS 线程（`OMP_NUM_THREADS`）。

> 也可跳过 main.py 直接调 R（独立 CLI 模式）：
>
> ```r
> library(pathview)
> pathview(gene.data = ge, pathway.id = "ko00010", species = "ko",
>          out.suffix = "study1", kegg.dir = ".")
> ```

## 实战示例：KEGG 通路富集结果可视化

文档「十二、KEGG通路富集分析（pathview）」给出 `pathview.pl query.ko study.1.txt study.2.txt 8`
的通路着色用法；等价能力由 `native/main.py` 的 `plot` 子命令提供（见上「用法」）——其中
`query.ko` 的通路 id 走 `--kegg-ids`，`study.N.txt`（首列 gene id、次列数值）走 `--gene-data`。

### 1. 准备差异基因数值表

```bash
# 由差异分析结果取「基因 id + log2FC」两列（示例：edgeR/DESeq2 输出）
perl -e '<>; while (<>) {@_ = split /\t/; print "$_[0]\t$_[5]\n";}' rawCount.matrix.UP.subset > study.1.txt
```

### 2. 运行 pathview（逐样本着色）

```bash
# 单样本
python main.py plot --kegg-ids ko00010 --gene-data study.1.txt \
    --species ko --out-dir kegg_out --out-suffix study.1
# 多样本批量
for f in study.1.txt study.2.txt; do
    python main.py plot --kegg-ids ko00010 --gene-data "$f" \
        --species ko --out-dir kegg_out --out-suffix "$(basename "$f" .txt)"
done
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--kegg-ids` | KEGG 通路 id，逗号分隔（如 `ko00010`、`ko00010,hsa04110`） |
| `--gene-data` | 基因数据表（首列 gene id，次列数值）；与 `--cpd-data` 至少一个 |
| `--cpd-data` | 化合物数据表（代谢组用） |
| `--species` | 物种/通路前缀（`ko`=KEGG Orthology；`hsa`/`mmu` 等三字母代码） |
| `--out-dir` | 输出目录（生成 `<kegg_id>.<suffix>.png` 与 `.xml`） |
| `--out-suffix` | 输出后缀（区分多次运行） |
| `--gene-idtype` | gene.data 的 id 类型（KEGG/ENTREZ/ORF/UniProt…，默认 KEGG） |
| `--discrete` | 离散型数据着色 |

> ⚠️ pathview 出图时会联网获取 KEGG kgml（首次）；离线环境请用 `--kegg-dir` 预置 kgml 缓存。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers），直接拉取官方镜像运行；`main.py` 驱动在宿主机跑。
（depot.galaxyproject.org 未收录该包，2026-09 核实 404，故 Apptainer 改用 quay docker:// 直拉。）

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n pathview -c conda-forge -c bioconda bioconductor-pathview=1.50.0
conda activate pathview
Rscript -e 'cat(as.character(packageVersion("pathview")))'   # 断言
```

> Homebrew 无 pathview 公式（homebrew-core `formulae.brew.sh/api/formula/pathview.json` 404；
> brewsci/bio 亦无），R 包统一走 Bioconductor，故不登记 brew 块。

> 💡 已装 R 时也可直接装（BiocManager 自动取当前 Bioconductor release 版）：
>
> ```bash
> Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager"); BiocManager::install("pathview")'
> ```
>
> 一键安装也可直接运行 `bash native/install.sh`（auto 路线：有 Rscript → BiocManager 直装；
> 无 Rscript → 建 conda env（bioconductor-pathview）。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0 \
    Rscript -e 'library(pathview); pathview(gene.data=read.delim("study.ko.txt",header=FALSE,row.names=1)[[1]], pathway.id="ko00010", species="ko", out.dir="kegg_out")'
```

### 3. Apptainer / Singularity

depot.galaxyproject.org **未收录** pathview（2026-09 核实 404），故直接从 quay docker 镜像拉取
（`docker://quay.io/biocontainers/...`，无需本地转换）：

```bash
apptainer pull bioconductor-pathview.sif docker://quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
apptainer run -B $PWD:/data -H /data bioconductor-pathview.sif \
    Rscript -e 'cat(as.character(packageVersion("pathview")), "\n")'
```

### 4. 官方源码归档安装（Bioconductor，无网络 R 环境亦可）

```bash
# Bioconductor release 源码归档（1.50.0；galaxyproject 亦镜像 src_all：https://depot.galaxyproject.org/software/bioconductor-pathview/）
wget https://bioconductor.org/packages/release/bioc/src/contrib/pathview_1.50.0.tar.gz -P ~/software/
R CMD INSTALL ~/software/pathview_1.50.0.tar.gz
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules**：无 `modules/nf-core/pathview`（2026-09 核实 404）；Nextflow 场景以本模块 `native/` 兜底。
* **snakemake-wrappers**：无 `bio/pathview`（2026-09 核实 404）；Snakemake 场景以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；Rscript+pathview 可用时 library 冒烟
```

## 版本

* bioconductor-pathview 1.50.0（Bioconductor release；GPL-3.0-or-later）
* 构建路线：官方镜像（quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0）+ bioconda；
  宿主机 BiocManager 直装
* nf-core / snakemake-wrappers 均无 pathview 官方子模块（2026-09 在线核实 404）

## 容器与 Conda 链接

* **Bioconductor**：<https://bioconductor.org/packages/release/bioc/html/pathview.html>
* **Bioconda 页面**：<https://anaconda.org/bioconda/bioconductor-pathview>
* **Docker**：`docker pull quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0`
* **depot.galaxyproject.org**：未收录（404，2026-09 核实）→ Apptainer 用 quay docker:// 直拉
* 安装方式（本地）：`mamba create -n pathview -c conda-forge -c bioconda bioconductor-pathview=1.50.0`
  或 `Rscript -e 'BiocManager::install("pathview")'`
