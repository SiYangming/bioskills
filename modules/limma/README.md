# limma 软件模块

> 汇总说明：limma 是 R/Bioconductor 包（无独立命令行二进制），本模块以 Rscript 驱动
> `voom()` / `lmFit()` / `eBayes()` / `topTable()` 完成 limma-voom 差异表达分析；安装方式见
> 「环境安装」，容器与 conda 链接见文末。conda 包名 **bioconductor-limma**。

***

## native 实现

# limma / native — Rscript 驱动的 limma-voom 差异表达分析

limma 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（GPL-2.0-or-later；文档未标注版本，2026-09-11 核实 bioconda 最新为 3.66.0），无 CLI，
因此 `native/main.py` 以 `Rscript <生成的 R 脚本>` 方式调用 limma 函数。

## 功能

limma 最初是为微阵列数据设计的，现在也广泛用于 RNA-seq 数据的差异表达分析。它基于线性模型，适合复杂实验设计。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `analyze` | `DGEList`→`calcNormFactors`→`model.matrix`→`voom`→`lmFit`→`eBayes`→`topTable` | limma-voom 差异表达分析，输出 logFC/AveExpr/t/P.Value/adj.P.Val/B |
| `voom` | 同上至 `voom` | 导出 voom log2-CPM 归一化表达矩阵（`v$E`），用于可视化/下游建模 |
| `check` | `library(limma)` | 校验包可加载并打印 `packageVersion` |

## 用法

```bash
# limma-voom 差异表达分析（raw count 矩阵 + 分组表；结果写 limma_voom_results.txt）
python main.py analyze gene.rawCount.matrix coldata.txt -o limma_voom_results.txt \
    --design '~condition' --coef 2 --cpm-cutoff 1 --min-samples 3 --threads 8

# 导出 voom log2-CPM 归一化矩阵
python main.py voom gene.rawCount.matrix coldata.txt -o limma_voom_matrix.txt

# 包可用性校验
python main.py check
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。线程优先级：
`--threads` > `optimization.per_subcommand_threads` > `optimization.default_cpus`。
limma 为线性模型计算，`--threads` 映射为 **BLAS 线程环境变量**
（`OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS`）。

## 实战示例：limma-voom 差异表达分析

典型 R 代码（等价能力由 `native/main.py` 的 `analyze` /
`voom` 子命令提供）：

```r
library(limma)
library(edgeR)

countData <- read.table("gene.rawCount.matrix", header = TRUE, row.names = 1, sep = "\t")
group <- factor(c("control", "control", "control",
                  "treatment", "treatment", "treatment"))

y <- DGEList(counts = countData)
keep <- rowSums(cpm(y) > 1) >= 3
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y)

design <- model.matrix(~ group)
colnames(design) <- levels(group)

v <- voom(y, design, plot = TRUE)     # voom 转换
fit <- lmFit(v, design)               # 线性模型拟合
fit <- eBayes(fit)                    # 贝叶斯检验
res <- topTable(fit, coef = 2, number = Inf, adjust.method = "BH")
write.table(res, "limma_voom_results.txt", sep = "\t", quote = FALSE, row.names = TRUE)

# 差异基因筛选（adj.P.Val < 0.05 且 |logFC| > 1）
de_genes <- subset(res, adj.P.Val < 0.05 & abs(logFC) > 1)
```

桥接：上述 DGEList → `calcNormFactors` → `voom` → `lmFit` → `eBayes` → `topTable`
等价于 `python main.py analyze gene.rawCount.matrix coldata.txt -o limma_voom_results.txt`；
`v <- voom(y, design)` 单独导出等价于
`python main.py voom gene.rawCount.matrix coldata.txt -o limma_voom_matrix.txt`。

**结果列说明：**

| 列名      | 说明                 |
| --------- | -------------------- |
| logFC     | log2 倍变化          |
| AveExpr   | 平均表达量           |
| t         | t 统计量             |
| P.Value   | p 值                 |
| adj.P.Val | 校正后的 p 值        |
| B         | B 统计量（对数赔率） |

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--design` | 设计公式（默认 `~condition`，经 `model.matrix(design, data=coldata)` 展开） |
| `--coef` | `topTable` 提取的系数列（默认 2，对应处理组 vs 对照组） |
| `--cpm-cutoff` / `--min-samples` | 低表达过滤（默认至少在 3 个样品中 CPM > 1） |
| `--adjust` | 多重检验校正方法（默认 BH） |
| `--threads` | BLAS 线程数（优先级 `--threads` > 子命令默认 > 全局默认） |

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已覆盖** limma
（`bioconductor-limma`）→ 本地不维护 Dockerfile/Apptainer.def；宿主机直跑 `main.py`
用 conda/mamba 安装，或直接 `docker run` 官方镜像。

### 1. 包管理器安装（Bioconductor / Conda）

Bioconductor 原生安装（R 路线；limma-voom 还需 edgeR）：

```bash
Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install(c("limma","edgeR"), ask=FALSE, update=FALSE)'
Rscript -e 'cat(as.character(packageVersion("limma")))'   # 断言
```

Conda 安装（推荐，可固定版本）：

```bash
mamba create -n limma -c conda-forge -c bioconda bioconductor-limma=3.66.0 bioconductor-edger
mamba run -n limma Rscript -e 'cat(as.character(packageVersion("limma")))'   # 断言
```

> 一键安装直接 `bash native/install.sh`（auto：有 conda 走 bioconda，否则 BiocManager）。
> Homebrew 无 limma 公式（`formulae.brew.sh/api/formula/limma.json` 404），故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker pull quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0 \
    Rscript -e 'library(limma); cat(as.character(packageVersion("limma")), "\n")'
```

### 3. Apptainer / Singularity

```bash
# galaxyproject 已预构建 sif，直接拉取（无需本地从 quay docker 转换）
apptainer pull limma.sif docker://depot.galaxyproject.org/singularity/bioconductor-limma:3.62.1--r44h15a9599_1
apptainer exec limma.sif Rscript -e 'library(limma); cat(as.character(packageVersion("limma")), "\n")'
```

## 官方实现登记（不建目录）

* **nf-core**：官方有 `modules/nf-core/limma/differential`（2026-09-11 核实存在）；
  `environment.yml` pin `bioconductor-limma=3.58.1` + `bioconductor-edger=4.0.16`。
  执行请用 `nf-core modules install limma/differential`，勿直接引用本仓库示例；缺失时以 native 兜底。
* **snakemake-wrappers**：无 `bio/limma` wrapper（2026-09-11 核实 404）；Snakemake 场景以
  native 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + R 脚本内容断言 + schema 自省（无需本机 R）
```

## 版本

* limma 3.66.0（文档未标注版本；2026-09-11 核实 bioconda 最新为 3.66.0）
* nf-core limma/differential pin 3.58.1（较旧）；snakemake-wrappers 无 limma 官方 wrapper（404）
* 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）已覆盖，本地不自建配方

## 容器与 Conda 链接

**文献**：Ritchie ME, et al. (2015) Nucleic Acids Research

* **bioconda**：<https://anaconda.org/bioconda/bioconductor-limma>
* **Docker（官方镜像）**：`quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0`
* **Singularity（官方镜像）**：<https://depot.galaxyproject.org/singularity/bioconductor-limma%3A3.62.1--r44h15a9599_1>
* **nf-core 官方模块**：`modules/nf-core/limma/differential`
* 安装方式（本地）：`bash native/install.sh`（conda `bioconductor-limma=3.66.0` 优先，无 conda 走 BiocManager）
