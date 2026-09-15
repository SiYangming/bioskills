# wgcna 软件模块

> 汇总说明：WGCNA 是 R 包（CRAN，无独立命令行二进制），本模块以 Rscript 驱动
> `goodSamplesGenes()` / `pickSoftThreshold()` / `adjacency()` / `TOMsimilarity()` /
> `cutreeDynamic()` / `mergeCloseModules()` 完成加权基因共表达网络分析；安装方式见「环境安装」，
> 容器与 conda 链接见文末。conda 规范包名为 **r-wgcna**（docs/09.md 所述 **bioconductor-wgcna**
> 经核实未找到，详见 software_versions）。对应 `docs/09.md`「6. WGCNA 共表达网络分析」。

***

## native 实现

`source_type: custom`、`type: native`。软件本体为 CRAN R 包，无 CLI，因此 `native/main.py`
以 `Rscript -e "<R 表达式>"` 方式调用 WGCNA 分析函数。

## 功能

WGCNA（Weighted Gene Co-expression Network Analysis）是一种基于基因共表达模式的系统生物学分析方法，可以将基因分为不同的模块，并与表型数据关联。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `run` | `goodSamplesGenes` → `pickSoftThreshold` → `adjacency`/`TOMsimilarity` → `cutreeDynamic` → `mergeCloseModules` | WGCNA 全流程：模块识别、相似模块合并、模块-性状关联，导出基因-模块归属与模块特征基因 |
| `check` | `goodSamplesGenes` | 数据质量检查：统计合格基因/样品数（低表达/缺失过滤建议） |

## 用法

```bash
# 全流程（自动估计软阈值；无性状数据）
python main.py run expression_matrix.txt --outdir wgcna_out

# 全流程 + 性状关联（模块-性状相关性热图 PDF）
python main.py run expression_matrix.txt --outdir wgcna_out \
    --trait trait_data.txt --power 6 --min-module-size 30 --merge-cut-height 0.25 \
    --threads 8

# 数据质量检查（可选输出报告表）
python main.py check expression_matrix.txt -o wgcna_qc.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 映射 `allowWGCNAThreads(nThreads=N)`
（WGCNA 多线程选项；优先级 `--threads` > `optimization.per_subcommand_threads` > `default_cpus`）。

## 实战示例

**等价能力由 `native/main.py` 的
`run` 子命令提供**（见上「用法」）——CLI 侧把这段 R 代码封装为参数化调用。

```r
library(WGCNA)
library(flashClust)

# 读取表达矩阵（行：样品，列：基因）
exprData <- read.table("expression_matrix.txt",
                       header = TRUE, row.names = 1, sep = "\t")
exprData <- t(exprData)  # 转置：行样品，列基因

# 读取表型数据（可选）
traitData <- read.table("trait_data.txt", header = TRUE, row.names = 1, sep = "\t")

# ============================================
# 步骤1：数据预处理和样品聚类
# ============================================
gsg <- goodSamplesGenes(exprData, verbose = 3)
exprData <- exprData[, gsg$goodGenes]

# 样品聚类
sampleTree <- hclust(dist(exprData), method = "average")
pdf("sample_clustering.pdf", width = 12, height = 6)
plot(sampleTree, main = "Sample clustering to detect outliers",
     sub = "", xlab = "", cex.lab = 1.5, cex.axis = 1.5, cex.main = 2)
dev.off()

# ============================================
# 步骤2：选择软阈值功率
# ============================================
powers <- c(c(1:10), seq(from = 12, to = 20, by = 2))
sft <- pickSoftThreshold(exprData, powerVector = powers, verbose = 5)
softPower <- sft$powerEstimate   # 选择 R^2 > 0.9 的最小功率

# ============================================
# 步骤3：构建共表达网络
# ============================================
adjacency <- adjacency(exprData, power = softPower)
TOM <- TOMsimilarity(adjacency)
dissTOM <- 1 - TOM
geneTree <- hclust(as.dist(dissTOM), method = "average")

# ============================================
# 步骤4：模块识别
# ============================================
dynamicMods <- cutreeDynamic(dendro = geneTree, distM = dissTOM,
                             deepSplit = 2, pamRespectsDendro = FALSE,
                             minClusterSize = 30)
dynamicColors <- labels2colors(dynamicMods)
MEList <- moduleEigengenes(exprData, colors = dynamicColors)
MEs <- MEList$eigengenes
MEDiss <- 1 - cor(MEs)
METree <- hclust(as.dist(MEDiss), method = "average")

# 合并相似模块（通常取 0.25，即相关性 > 0.75 的模块合并）
MEDissThres <- 0.25
merged <- mergeCloseModules(exprData, dynamicColors, cutHeight = MEDissThres, verbose = 3)
mergedColors <- merged$colors
mergedMEs <- merged$newMEs
moduleColors <- mergedColors
MEs <- mergedMEs

# ============================================
# 步骤5：模块-性状关联（如果有表型数据）
# ============================================
moduleTraitCor <- cor(MEs, traitData, use = "p")
moduleTraitPvalue <- corPvalueStudent(moduleTraitCor, nrow(exprData))

pdf("module_trait_correlation.pdf", width = 10, height = 8)
labeledHeatmap(Matrix = moduleTraitCor,
               xLabels = names(traitData),
               yLabels = names(MEs),
               ySymbols = names(MEs),
               colorLabels = FALSE,
               colors = blueWhiteRed(50),
               textMatrix = paste(signif(moduleTraitCor, 2), "\n(",
                                  signif(moduleTraitPvalue, 1), ")", sep = ""),
               setStdMargins = FALSE,
               cex.text = 0.5,
               zlim = c(-1, 1),
               main = paste("Module-trait relationships"))
dev.off()

# ============================================
# 步骤6：导出结果
# ============================================
gene_module <- data.frame(gene = colnames(exprData), module = moduleColors)
write.table(gene_module, "gene_module_assignment.txt",
            sep = "\t", quote = FALSE, row.names = FALSE)
write.table(MEs, "module_eigengenes.txt",
            sep = "\t", quote = FALSE, row.names = TRUE)
```

> `native/main.py run --outdir <目录>` 产出同名的 `gene_module_assignment.txt` /
> `module_eigengenes.txt`（`--trait` 时另出 `module_trait_correlation.txt` + PDF）。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已维护** r-wgcna 镜像 →
直接拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑（conda/mamba 装工具）；**本地不维护
Dockerfile / Apptainer.def**。

### 1. Conda / brew（包管理器安装）

```bash
# 推荐：conda/mamba 建独立环境（版本与 meta software_versions 对齐）
mamba create -n wgcna -c conda-forge -c bioconda r-wgcna=1.74
mamba run -n wgcna Rscript -e 'cat(as.character(packageVersion("WGCNA")))'   # 断言

# 一键安装也可直接运行本模块脚本（auto：有 conda 走 conda，否则 R BiocManager）
bash native/install.sh --help
```

> Homebrew **无** WGCNA 公式（`formulae.brew.sh/api/formula/wgcna.json` 404，已核实）；
> R 包统一走 conda/CRAN，故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/r-wgcna:1.74--r45h0df16ae_1
# 注意：必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/r-wgcna:1.74--r45h0df16ae_1 \
    Rscript -e 'library(WGCNA); cat(as.character(packageVersion("WGCNA")), "\n")'
```

### 3. Apptainer / Singularity（depot 预构建 sif 直拉）

```bash
apptainer pull wgcna.sif docker://depot.galaxyproject.org/singularity/r-wgcna:1.74--r45h0df16ae_1
apptainer run -B $PWD:/data -H /data wgcna.sif Rscript -e 'library(WGCNA); sessionInfo()'
```

## 测试

```bash
bash test/run_test.sh   # argv（Rscript -e 表达式）构造 + schema 自省为常驻断言，不真实执行 R
```

## 容器与 Conda 链接

**文献**：Langfelder P & Horvath S (2008) BMC Bioinformatics

* **官网**：<https://horvath.genetics.ucla.edu/html/CoexpressionNetwork/Rpackages/WGCNA/>（CRAN WGCNA 1.74）
* **bioconda**：<https://anaconda.org/bioconda/r-wgcna>（最新 1.74）
* **quay.io/biocontainers**：`quay.io/biocontainers/r-wgcna:1.74--r45h0df16ae_1`
* **depot.galaxyproject.org**：<https://depot.galaxyproject.org/singularity/r-wgcna%3A1.74--r45h0df16ae_1>
* ⚠️ **包名核实**：docs/09.md 所述 `bioconductor-wgcna` 在 bioconda / conda-forge 均**未找到**
  （anaconda API 核实，2026-09-11）；实际可用包名为 **r-wgcna**（bioconda）。
* nf-core modules（`modules/nf-core/wgcna`）、snakemake-wrappers（`bio/wgcna`）**均无官方子模块**
  （2026-09-11 在线核实 404）
* 安装方式（本地）：`mamba create -n wgcna -c conda-forge -c bioconda r-wgcna=1.74`

## 版本

* wgcna 1.74（bioconda r-wgcna 1.74，与 CRAN WGCNA 1.74 一致；docs/09.md 未标注版本）
* 构建路线：官方 biocontainer 已维护（quay / depot r-wgcna:1.74）→ 不维护本地配方；宿主机用 conda/mamba
* nf-core / snakemake-wrappers 均无 wgcna 官方子模块（2026-09-11 在线核实 404）
