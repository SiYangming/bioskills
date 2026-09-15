# deseq2 软件模块

> 汇总说明：DESeq2 是 R/Bioconductor 包（无独立命令行二进制），本模块以 Rscript 驱动
> `DESeq()` / `results()` / `vst()` 完成差异表达分析；安装方式见「环境安装」，容器与
> conda 链接见文末。conda 包名 **bioconductor-deseq2**。

***

## native 实现

# deseq2 / native — Rscript 驱动的差异表达分析

DESeq2 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（LGPL-3；文档未标注版本，2026-09-11 核实 bioconda 最新为 1.50.2），无 CLI，因此
`native/main.py` 以 `Rscript <生成的 R 脚本>` 方式调用 DESeq2 函数。

## 功能

DESeq2 是基于负二项分布的差异表达分析 R 包，采用 shrinkage 方法估计离散度。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `analyze` | `DESeqDataSetFromMatrix` → `DESeq` → `results` | 差异表达分析，输出 baseMean/log2FoldChange/pvalue/padj（按 padj 排序） |
| `vst` | `DESeq` → `vst` / `rlog` | 方差稳定转换（VST/rlog），导出归一化表达矩阵用于热图/聚类 |
| `check` | `library(DESeq2)` | 校验包可加载并打印 `packageVersion` |

## 用法

```bash
# 差异表达分析（raw count 矩阵 + 分组表；结果写 DESeq2_results.txt）
python main.py analyze gene.rawCount.matrix coldata.txt -o DESeq2_results.txt \
    --design '~condition' --contrast condition,treatment,control --threads 8

# VST 转换（导出 vst_normalized_matrix.txt；用于热图/聚类）
python main.py vst gene.rawCount.matrix coldata.txt -o vst_normalized_matrix.txt

# 包可用性校验
python main.py check
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。线程优先级：
`--threads` > `optimization.per_subcommand_threads` > `optimization.default_cpus`。
`--threads` 映射到 DESeq2 的并行后端 **BiocParallel**（R 脚本内
`register(MulticoreParam(n))`），多核离散度估计即走该后端。

## 实战示例：RNA-seq 差异表达分析

典型 R 代码（等价能力由 `native/main.py` 的 `analyze` /
`vst` 子命令提供；CLI 参数即对这些步骤的结构化封装）：

```r
library(DESeq2)

# 读取表达量矩阵
countData <- read.table("gene.rawCount.matrix", header = TRUE, row.names = 1, sep = "\t")

# 创建设计矩阵（样品分组信息）：control 与 treatment 各 3 个重复
coldata <- data.frame(
    condition = factor(c("control", "control", "control",
                         "treatment", "treatment", "treatment")),
    row.names = colnames(countData)
)

dds <- DESeqDataSetFromMatrix(countData = countData, colData = coldata, design = ~ condition)
dds <- dds[rowSums(counts(dds) >= 10) >= 3, ]   # 过滤低表达基因
dds <- DESeq(dds)                               # 运行差异表达分析
res <- results(dds, contrast = c("condition", "treatment", "control"))
res <- res[order(res$padj), ]
write.table(as.data.frame(res), "DESeq2_results.txt", sep = "\t", quote = FALSE, row.names = TRUE)

# 差异基因筛选（padj < 0.05 且 |log2FC| > 1）
de_genes <- subset(res, padj < 0.05 & abs(log2FoldChange) > 1)

# VST / rlog 转换（用于可视化）
vsd <- vst(dds, blind = FALSE)
write.table(assay(vsd), "vst_normalized_matrix.txt", sep = "\t", quote = FALSE, row.names = TRUE)
```

桥接：上述读取 → 过滤 → `DESeq` → `results` 等价于
`python main.py analyze gene.rawCount.matrix coldata.txt -o DESeq2_results.txt`；
`vst(dds, blind = FALSE)` 等价于
`python main.py vst gene.rawCount.matrix coldata.txt -o vst_normalized_matrix.txt`。

**DESeq2结果列说明：**

| 列名           | 说明                 |
| -------------- | -------------------- |
| baseMean       | 所有样品的平均表达量 |
| log2FoldChange | log2 倍变化          |
| lfcSE          | log2FC 的标准误      |
| stat           | 统计量               |
| pvalue         | p 值                 |
| padj           | 校正后的 p 值（FDR） |

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--design` | DESeq2 设计公式（默认 `~condition`） |
| `--contrast` | 对比三元组 `factor,treatment,control`（默认 `condition,treatment,control`） |
| `--min-count` / `--min-samples` | 低表达过滤（默认至少在 3 个样品中 count ≥ 10） |
| `--transform` | `vst`（默认）/ `rlog` |
| `--blind` | VST blind 转换（默认 FALSE） |
| `--threads` | 线程数（映射 BiocParallel；优先级 `--threads` > 子命令默认 > 全局默认） |

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已覆盖** DESeq2
（`bioconductor-deseq2`）→ 本地不维护 Dockerfile/Apptainer.def；宿主机直跑 `main.py`
用 conda/mamba 安装，或直接 `docker run` 官方镜像。

### 1. 包管理器安装（Bioconductor / Conda）

Bioconductor 原生安装（R 路线）：

```bash
Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("DESeq2", ask=FALSE, update=FALSE)'
Rscript -e 'cat(as.character(packageVersion("DESeq2")))'   # 断言
```

Conda 安装（推荐，可固定版本）：

```bash
mamba create -n deseq2 -c conda-forge -c bioconda bioconductor-deseq2=1.50.2
mamba run -n deseq2 Rscript -e 'cat(as.character(packageVersion("DESeq2")))'   # 断言
```

> 一键安装直接 `bash native/install.sh`（auto：有 conda 走 bioconda，否则 BiocManager）。
> Homebrew 无 deseq2 公式（`formulae.brew.sh/api/formula/deseq2.json` 404），故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker pull quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0 \
    Rscript -e 'library(DESeq2); cat(as.character(packageVersion("DESeq2")), "\n")'
```

### 3. Apptainer / Singularity

```bash
# galaxyproject 已预构建 sif，直接拉取（无需本地从 quay docker 转换）
apptainer pull deseq2.sif docker://depot.galaxyproject.org/singularity/bioconductor-deseq2:1.46.0--r44he5774e6_1
apptainer exec deseq2.sif Rscript -e 'library(DESeq2); cat(as.character(packageVersion("DESeq2")), "\n")'
```

## 官方实现登记（不建目录）

* **nf-core**：官方有 `modules/nf-core/deseq2/differential`（2026-09-11 核实存在）；
  `environment.yml` pin `bioconductor-deseq2=1.34.0` + `bioconductor-limma=3.50.0`。
  执行请用 `nf-core modules install deseq2/differential`，勿直接引用本仓库示例；缺失时以 native 兜底。
* **snakemake-wrappers**：官方有 `bio/deseq2`（子模块 `wald`、`deseqdataset`，2026-09-11 核实存在），
  `environment.yaml` pin `bioconductor-deseq2=1.50.2`。运行靠 Snakemake 解析 `wrapper:` 句柄：

```python
rule deseq2_wald:
    input:
        dds="dds.RDS",
    output:
        wald_rds="wald_apeglm.RDS",
        wald_tsv="dge_apeglm.tsv",
        deseq2_result_dir=directory("deseq_results_apeglm"),
        normalized_counts_table="counts_apeglm.tsv",
        normalized_counts_rds="counts_apeglm.RDS",
    params:
        deseq_extra="",
        shrink_extra="type='apeglm'",   # lfcShrink 额外参数（含收缩类型）
        results_extra="",
        contrast=["condition", "treatment", "control"],
    threads: 1
    log:
        "logs/deseq2_apeglm.log",
    wrapper:
        "v9.17.1/bio/deseq2/wald"
```

> 该 rule 契约取自官方 `bio/deseq2/wald/test/Snakefile`（2026-09-11 核实）。

> `wrapper:` 由 Snakemake 在运行时解析，不要把本地示例当作 wrapper 路径。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + R 脚本内容断言 + schema 自省（无需本机 R）
```

## 版本

* DESeq2 1.50.2（文档未标注版本；2026-09-11 核实 bioconda 最新为 1.50.2）
* nf-core deseq2/differential pin 1.34.0（较旧）；snakemake-wrappers bio/deseq2 pin 1.50.2
* 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）已覆盖，本地不自建配方

## 容器与 Conda 链接

**文献**：Love MI, et al. (2014) Genome Biology

* **Bioconductor**：<https://bioconductor.org/packages/DESeq2/>
* **bioconda**：<https://anaconda.org/bioconda/bioconductor-deseq2>
* **Docker（官方镜像）**：`quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0`
* **Singularity（官方镜像）**：<https://depot.galaxyproject.org/singularity/bioconductor-deseq2%3A1.46.0--r44he5774e6_1>
* **nf-core 官方模块**：`modules/nf-core/deseq2/differential`
* **snakemake-wrappers 官方 wrapper**：`v9.17.1/bio/deseq2/{wald,deseqdataset}`
* 安装方式（本地）：`bash native/install.sh`（conda `bioconductor-deseq2=1.50.2` 优先，无 conda 走 BiocManager）
