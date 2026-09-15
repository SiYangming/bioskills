# goseq 软件模块

> 汇总说明：goseq 是 Bioconductor 的 GO 富集分析 R 包（无独立命令行二进制），本模块以
> `Rscript` 驱动 `goseq::nullp()` + `goseq::goseq()` 完成长度偏倚校正后的 GO 富集；
> 安装方式见「环境安装」，容器与 conda 链接见文末。conda / 容器规范包名为 **bioconductor-goseq**。
>
> 官方渠道已维护（2026-09 核实）：bioconda `bioconductor-goseq=1.62.0`、
> `quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0`；
> 唯 depot.galaxyproject.org 未收录（404），Apptainer 走 quay docker:// 直拉。

***

## native 实现

# goseq / native — Rscript 驱动的 GO 富集分析

goseq 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（LGPL-2.0-or-later，v1.62.0），无 CLI，因此 `native/main.py` 以
`Rscript -e <内嵌 R 驱动> <params.tsv>` 方式调用 `nullp()` + `goseq()`。它是 Trinity
`run_GOseq.pl` 的底层依赖。

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `go` | `Rscript -e <driver> params.tsv`（内部 `nullp` + `goseq`） | 差异基因 + 基因长度 → 长度偏倚 PWF → GO 类别过/欠代表检验，输出含 BH FDR 的富集结果表 |

## 用法

```bash
# CLI 直跑：差异基因 + 长度 + 基因→GO 映射 → 富集结果表
python main.py go --genes de_genes.txt --lengths gene_lengths.tsv \
    --gene2cat gene2go.tsv -o go_enrichment.tsv --method Wallenius --threads 4

# 用 gene2cat 全部类别（不限定三大 GO 本体）
python main.py go --genes de_genes.txt --lengths gene_lengths.tsv \
    --gene2cat gene2go.tsv -o go_enrichment.tsv --test-cats ""

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 透传 R 底层 BLAS 的
OMP/OPENBLAS 线程（`OMP_NUM_THREADS`）。

> 也可跳过 main.py 直接调 R（独立 CLI 模式）：
>
> ```r
> library(goseq)
> pwf <- nullp(gene.vector, bias.data = lengths)     # 长度偏倚 PWF
> res <- goseq(pwf, gene2cat = gene2cat, method = "Wallenius")
> ```

## 实战示例：RNA-seq 差异基因的 GO 富集

文档「十二」给出 goseq 的安装（`biocLite('goseq')`）与作为 Trinity `run_GOseq.pl` 依赖的
用法；等价能力由 `native/main.py` 的 `go` 子命令提供（见上「用法」）。

### 1. 准备输入

```bash
# 差异基因列表：每行一个 gene id
awk 'NR>1 && $6!=0 {print $1}' de_result.tsv > de_genes.txt
# 基因长度表：首列 gene id、次列长度（可由 GTF 外显子并集长度得到）
awk '$3=="exon"{split($9,a,"gene_id \""); g=a[2]; sub(/".*/,"",g); L[g]+=$5-$4+1} \
     END{for (g in L) print g"\t"L[g]}' genes.gtf > gene_lengths.tsv
# 基因→GO 映射表：首列 gene id、次列 GO id（多个用 ; 分隔）
#   可由 InterPro/eggNOG/KAAS 或 org.*.eg.db 导出
```

### 2. 运行富集

```bash
python main.py go --genes de_genes.txt --lengths gene_lengths.tsv \
    --gene2cat gene2go.tsv -o go_enrichment.tsv --method Wallenius
head go_enrichment.tsv   # category / over_represented_pvalue / ... / padj
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--genes` | 差异基因列表（每行一个 gene id；须为 `--lengths` 基因集的子集） |
| `--lengths` | 基因长度表（首列 gene id、次列长度，覆盖全部被检验基因） |
| `--gene2cat` | 基因→GO 类别映射表（次列多个类别用 `;` 分隔） |
| `-o/--output` | 富集结果输出表（含 `over_represented_pvalue`、`padj` 等列） |
| `--method` | 检验方法：`Wallenius`（默认，推荐）/ `Hypergeometric` / `Repulsive` |
| `--test-cats` | 类别空间（默认 `GO:CC,GO:BP,GO:MF`；留空用 gene2cat 全部类别） |
| `--no-use-genes-without-cat` | 不把无 GO 类别基因计入背景（默认计入） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers），直接拉取官方镜像运行；`main.py` 驱动在宿主机跑。
（depot.galaxyproject.org 未收录该包，2026-09 核实 404，故 Apptainer 改用 quay docker:// 直拉。）

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n goseq -c conda-forge -c bioconda bioconductor-goseq=1.62.0
conda activate goseq
Rscript -e 'cat(as.character(packageVersion("goseq")))'   # 断言
```

> Homebrew 无 goseq 公式（homebrew-core `formulae.brew.sh/api/formula/goseq.json` 404；
> brewsci/bio 亦无），R 包统一走 Bioconductor，故不登记 brew 块。

> 💡 已装 R 时也可直接装（BiocManager 自动取当前 Bioconductor release 版）：
>
> ```bash
> Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager"); BiocManager::install("goseq")'
> ```
>
> 一键安装也可直接运行 `bash native/install.sh`（auto 路线：有 Rscript → BiocManager 直装；
> 无 Rscript → 建 conda env（bioconductor-goseq）。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0 \
    Rscript -e 'cat(as.character(packageVersion("goseq")), "\n")'
```

### 3. Apptainer / Singularity

depot.galaxyproject.org **未收录** goseq（2026-09 核实 404），故直接从 quay docker 镜像拉取
（`docker://quay.io/biocontainers/...`，无需本地转换）：

```bash
apptainer pull bioconductor-goseq.sif docker://quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0
apptainer run -B $PWD:/data -H /data bioconductor-goseq.sif \
    Rscript -e 'cat(as.character(packageVersion("goseq")), "\n")'
```

### 4. 官方源码归档安装（Bioconductor，无网络 R 环境亦可）

```bash
# Bioconductor release 源码归档（1.62.0；galaxyproject 亦镜像 src_all：https://depot.galaxyproject.org/software/bioconductor-goseq/）
wget https://bioconductor.org/packages/release/bioc/src/contrib/goseq_1.62.0.tar.gz -P ~/software/
R CMD INSTALL ~/software/goseq_1.62.0.tar.gz
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules**：无 `modules/nf-core/goseq`（2026-09 核实 404）；Nextflow 场景以本模块 `native/` 兜底。
* **snakemake-wrappers**：无 `bio/goseq`（2026-09 核实 404）；Snakemake 场景以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；Rscript+goseq 可用时 library 冒烟
```

## 版本

* bioconductor-goseq 1.62.0（Bioconductor release；LGPL-2.0-or-later）
* 构建路线：官方镜像（quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0）+ bioconda；
  宿主机 BiocManager 直装
* nf-core / snakemake-wrappers 均无 goseq 官方子模块（2026-09 在线核实 404）

## 容器与 Conda 链接

* **Bioconductor**：<https://bioconductor.org/packages/release/bioc/html/goseq.html>
* **Bioconda 页面**：<https://anaconda.org/bioconda/bioconductor-goseq>
* **Docker**：`docker pull quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0`
* **depot.galaxyproject.org**：未收录（404，2026-09 核实）→ Apptainer 用 quay docker:// 直拉
* 安装方式（本地）：`mamba create -n goseq -c conda-forge -c bioconda bioconductor-goseq=1.62.0`
  或 `Rscript -e 'BiocManager::install("goseq")'`
