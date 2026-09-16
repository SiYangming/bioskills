# clusterprofiler 软件模块

> 汇总说明：clusterProfiler 是 R 包（Bioconductor，无独立命令行二进制），本模块以 Rscript 驱动
> `enrichGO()` / `enrichKEGG()` / `gseGO()` 完成 GO/KEGG/GSEA 富集分析；安装方式见「环境安装」，
> 容器与 conda 链接见文末。conda / 容器规范包名为 **bioconductor-clusterprofiler**（目录名 canonical
> 取全小写 **clusterprofiler**）。覆盖 GO 富集 / KEGG 富集 / clusterProfiler 综合分析。

***

## native 实现

`source_type: custom`、`type: native`。软件本体为 Bioconductor R 包，无 CLI，因此 `native/main.py`
以 `Rscript -e "<R 表达式>"` 方式调用 clusterProfiler 的富集函数。

## 功能

clusterProfiler 是一个功能强大的富集分析 R 包，支持 GO、KEGG、GSEA 等多种富集分析方法。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `go` | `enrichGO()` | GO 富集（BP/CC/MF/ALL；单物种注释库 OrgDb + keyType） |
| `kegg` | `enrichKEGG()`（SYMBOL 先经 `bitr()` 转 ENTREZID） | KEGG 通路富集（物种代码 hsa/mmu/…） |
| `gsea` | `gseGO()` | GSEA（输入为全基因 log2FC 排序表，无需预筛差异基因） |

## 用法

```bash
# GO 富集（差异基因列表 → 结果表）
python main.py go DEG_list.txt -o GO_enrichment_results.txt \
    --orgdb org.Hs.eg.db --keytype SYMBOL --ont ALL --pvalue 0.05 --qvalue 0.05

# KEGG 富集（SYMBOL 自动转 ENTREZID；小鼠用 --organism mmu）
python main.py kegg DEG_list.txt -o KEGG_enrichment_results.txt \
    --orgdb org.Hs.eg.db --organism hsa

# GSEA（DESeq2 结果表按 log2FoldChange 排序）
python main.py gsea DESeq2_results.txt -o GSEA_results.txt \
    --rank-col log2FoldChange --ont BP --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 映射 BiocParallel：富集调用注入
`BPPARAM = BiocParallel::MulticoreParam(workers=N)`，并在加载包前设置 `OMP/OPENBLAS/MKL/VECLIB`
线程数环境变量（优先级 `--threads` > `optimization.per_subcommand_threads` > `default_cpus`）。

## 实战示例

**等价能力由 `native/main.py` 的
`go` / `kegg` / `gsea` 子命令提供**（见上「用法」）——CLI 侧把这段 R 代码封装为参数化调用。

### GO 富集（enrichGO）

Gene Ontology（GO）是基因功能分类的标准体系，包括分子功能（MF）、细胞组分（CC）和生物过程（BP）三个部分。

```r
library(clusterProfiler)
library(org.Hs.eg.db)  # 人类注释库，其他物种替换为对应库

# 读取差异基因列表（基因名向量）
de_genes <- read.table("DEG_list.txt", header = FALSE)$V1

# GO 富集分析
ego <- enrichGO(
    gene = de_genes,
    OrgDb = org.Hs.eg.db,
    keyType = "SYMBOL",  # 基因ID类型
    ont = "ALL",         # BP, CC, MF 或 ALL
    pAdjustMethod = "BH",
    pvalueCutoff = 0.05,
    qvalueCutoff = 0.05
)

# 查看结果
head(ego)

# 保存结果
write.table(as.data.frame(ego), "GO_enrichment_results.txt",
            sep = "\t", quote = FALSE, row.names = FALSE)
```

常用物种注释库：人类 `org.Hs.eg.db`、小鼠 `org.Mm.eg.db`、大鼠 `org.Rn.eg.db`、拟南芥
`org.At.tair.db`、水稻 `org.Osativa.eg.db`、果蝇 `org.Dm.eg.db`、线虫 `org.Ce.eg.db`、酵母 `org.Sc.sgd.db`。对于非模式生物，可以使用 eggNOG、InterProScan 等工具先进行功能注释，然后自定义注释文件进行富集分析。

### KEGG 富集（enrichKEGG）

KEGG（Kyoto Encyclopedia of Genes and Genomes）是系统分析基因功能、通路信息的数据库。

```r
library(clusterProfiler)

# 将基因名转换为 Entrez ID（KEGG 使用 Entrez ID）
library(org.Hs.eg.db)
de_genes <- read.table("DEG_list.txt", header = FALSE)$V1

# 转换基因ID
gene_entrez <- mapIds(org.Hs.eg.db, keys = de_genes,
                      column = "ENTREZID", keytype = "SYMBOL")
gene_entrez <- na.omit(gene_entrez)

# KEGG 富集分析
ekk <- enrichKEGG(
    gene = gene_entrez,
    organism = "hsa",  # 物种代码，人类 hsa，小鼠 mmu
    pvalueCutoff = 0.05,
    pAdjustMethod = "BH",
    qvalueCutoff = 0.05
)

head(ekk)
write.table(as.data.frame(ekk), "KEGG_enrichment_results.txt",
            sep = "\t", quote = FALSE, row.names = FALSE)
```

常用物种 KEGG 代码：人类 `hsa`、小鼠 `mmu`、大鼠 `rno`、拟南芥 `ath`、水稻 `osa`、果蝇 `dme`、线虫 `cel`、酵母 `sce`。

### GSEA（gseGO）

Gene Set Enrichment Analysis（GSEA）是一种基于基因集的富集分析方法，不需要预先筛选差异基因。

```r
library(clusterProfiler)
library(org.Hs.eg.db)

# 读取所有基因的 log2FC 值（命名向量）
res <- read.table("DESeq2_results.txt", header = TRUE, row.names = 1, sep = "\t")
geneList <- res$log2FoldChange
names(geneList) <- rownames(res)
geneList <- sort(geneList, decreasing = TRUE)
geneList <- na.omit(geneList)

# GSEA 分析
gse <- gseGO(
    geneList = geneList,
    OrgDb = org.Hs.eg.db,
    keyType = "SYMBOL",
    ont = "BP",
    pvalueCutoff = 0.05
)

head(gse)
```

> 富集结果的可视化（条形图 / 点图 / 网络图 / GSEA 曲线）属另一环节，
> 本模块聚焦 enrichGO/enrichKEGG/gseGO 的结果表产出。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已维护**
bioconductor-clusterprofiler 镜像 → 直接拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑
（conda/mamba 装工具）；**本地不维护 Dockerfile / Apptainer.def**。

### 1. Conda / brew（包管理器安装）

```bash
# 推荐：conda/mamba 建独立环境（版本与 meta software_versions 对齐）
mamba create -n clusterprofiler -c conda-forge -c bioconda bioconductor-clusterprofiler=4.18.4
mamba run -n clusterprofiler Rscript -e 'cat(as.character(packageVersion("clusterProfiler")))'   # 断言

# 一键安装也可直接运行本模块脚本（auto：有 conda 走 conda，否则 R BiocManager）
bash native/install.sh --help
```

> Homebrew **无** clusterProfiler 公式（`formulae.brew.sh/api/formula/clusterprofiler.json` 404，
> 已核实）；homebrew 的 `r` 公式只提供 R 本体，R 包统一走 Bioconductor/conda，故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
# 官方 biocontainer（tag 含版本 + build）
docker pull quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0 \
    Rscript -e 'library(clusterProfiler); cat(as.character(packageVersion("clusterProfiler")), "\n")'
```

### 3. Apptainer / Singularity（depot 预构建 sif 直拉）

```bash
# galaxyproject 已预构建 sif，直接拉取（tag 与 quay.io/biocontainers 互通），无需本地从 docker 转换
apptainer pull clusterprofiler.sif docker://depot.galaxyproject.org/singularity/bioconductor-clusterprofiler:4.14.0--r44hdfd78af_0
apptainer run -B $PWD:/data -H /data clusterprofiler.sif \
    Rscript -e 'library(clusterProfiler); sessionInfo()'
```

## 测试

```bash
bash test/run_test.sh   # argv（Rscript -e 表达式）构造 + schema 自省为常驻断言，不真实执行 R
```

## 容器与 Conda 链接

**文献**：Yu G, et al. (2012) OMICS

* **bioconda**：<https://anaconda.org/bioconda/bioconductor-clusterprofiler>（最新 4.18.4）
* **quay.io/biocontainers**：`quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0`
* **depot.galaxyproject.org**：<https://depot.galaxyproject.org/singularity/bioconductor-clusterprofiler%3A4.14.0--r44hdfd78af_0>
* nf-core modules（`modules/nf-core/clusterprofiler`）、snakemake-wrappers（`bio/clusterprofiler`）**均无官方子模块**
  （2026-09-11 在线核实 404）
* 安装方式（本地）：`mamba create -n clusterprofiler -c conda-forge -c bioconda bioconductor-clusterprofiler=4.18.4`

## 版本

* clusterprofiler 4.18.4（bioconda 最新；教学课件未标注版本）
* 构建路线：官方 biocontainer 已维护（quay 4.18.4 / depot 4.14.0）→ 不维护本地配方；宿主机用 conda/mamba
* nf-core / snakemake-wrappers 均无 clusterprofiler 官方子模块（2026-09-11 在线核实 404）
