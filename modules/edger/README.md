# edger 软件模块

> 汇总说明：edgeR 是 R/Bioconductor 包（无独立命令行二进制），本模块以 Rscript 驱动
> `calcNormFactors()`（TMM）/ `estimateDisp()` / `exactTest()` / `topTags()` 完成差异表达
> 分析；安装方式见「环境安装」，容器与 conda 链接见文末。conda 包名 **bioconductor-edger**。

***

## native 实现

# edger / native — Rscript 驱动的差异表达分析

edgeR 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（GPL-2.0-or-later；文档未标注版本，2026-09-11 核实 bioconda 最新为 4.8.2），无 CLI，
因此 `native/main.py` 以 `Rscript <生成的 R 脚本>` 方式调用 edgeR 函数。

## 功能

edgeR 是基于负二项分布的差异表达分析 R 包，是 RNA-seq 差异分析的经典工具，特别适合处理生物学重复。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `analyze` | `DGEList` → `calcNormFactors`（TMM）→ `estimateDisp` → `exactTest` → `topTags` | 两组（多组）差异表达分析，输出 logFC/logCPM/PValue/FDR |
| `norm` | `DGEList` → `calcNormFactors` | TMM 归一化因子计算，输出样品归一化因子表 |
| `check` | `library(edgeR)` | 校验包可加载并打印 `packageVersion` |

## 用法

```bash
# 差异表达分析（raw count 矩阵 + 分组表；结果写 edgeR_results.txt）
python main.py analyze gene.rawCount.matrix coldata.txt -o edgeR_results.txt \
    --pair control,treatment --cpm-cutoff 1 --min-samples 3 --threads 8

# TMM 归一化因子（导出 edgeR_norm_factors.txt）
python main.py norm gene.rawCount.matrix -o edgeR_norm_factors.txt --method TMM

# 包可用性校验
python main.py check
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。线程优先级：
`--threads` > `optimization.per_subcommand_threads` > `optimization.default_cpus`。
edgeR 核心计算基本为单线程，`--threads` 映射为 **BLAS 线程环境变量**
（`OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS`），用于加速底层矩阵运算。

## 实战示例：edgeR 差异表达分析（来自文档 09.md 2.2 节）

文档「2.2 edgeR」给出的典型 R 代码（等价能力由 `native/main.py` 的 `analyze` /
`norm` 子命令提供）：

```r
library(edgeR)

countData <- read.table("gene.rawCount.matrix", header = TRUE, row.names = 1, sep = "\t")
group <- factor(c("control", "control", "control",
                  "treatment", "treatment", "treatment"))

y <- DGEList(counts = countData, group = group)
keep <- rowSums(cpm(y) > 1) >= 3           # 过滤低表达基因
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y)                    # TMM 归一化
y$samples$norm.factors
y <- estimateDisp(y)                       # 估计离散度
y$common.dispersion

et <- exactTest(y, pair = c("control", "treatment"))   # 精确检验（两组比较）
results <- topTags(et, n = Inf, adjust.method = "BH")
write.table(results$table, "edgeR_results.txt", sep = "\t", quote = FALSE, row.names = TRUE)

# 差异基因筛选（FDR < 0.05 且 |logFC| > 1）
de_genes <- subset(results$table, FDR < 0.05 & abs(logFC) > 1)
```

桥接：上述 DGEList → 过滤 → `calcNormFactors` → `estimateDisp` → `exactTest` →
`topTags` 等价于 `python main.py analyze gene.rawCount.matrix coldata.txt -o edgeR_results.txt`；
`y <- calcNormFactors(y)` 单独导出等价于 `python main.py norm gene.rawCount.matrix -o edgeR_norm_factors.txt`。

**结果列说明：**

| 列名   | 说明                        |
| ------ | --------------------------- |
| logFC  | log2 倍变化                 |
| logCPM | log2 每百万计数             |
| PValue | p 值                        |
| FDR    | 校正后的 p 值（错误发现率） |

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--pair` | 两组比较 `control,treatment`（默认 `control,treatment`，对应 `exactTest(pair=...)`） |
| `--cpm-cutoff` / `--min-samples` | 低表达过滤（默认至少在 3 个样品中 CPM > 1） |
| `--adjust` | 多重检验校正方法（默认 BH） |
| `--method` | `norm` 子命令归一化方法：`TMM`（默认）/`TMMwsp`/`RLE`/`upperquartile`/`none` |
| `--threads` | BLAS 线程数（优先级 `--threads` > 子命令默认 > 全局默认） |

### Trinity 辅助脚本（文档 2.2 节推荐，转录组项目可选）

```bash
# Trinity 组装转录组的现成 DE 脚本（等价能力由 native/main.py analyze 提供）
$TRINITY_HOME/Analysis/DifferentialExpression/run_DE_analysis.pl \
    --matrix gene.rawCount.matrix --method edgeR \
    --samples_file samples.txt --output edgeR_out
# samples.txt 格式：分组名<TAB>样品名（control sample1 ...）
```

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已覆盖** edgeR
（`bioconductor-edger`）→ 本地不维护 Dockerfile/Apptainer.def；宿主机直跑 `main.py`
用 conda/mamba 安装，或直接 `docker run` 官方镜像。

### 1. 包管理器安装（Bioconductor / Conda）

Bioconductor 原生安装（R 路线）：

```bash
Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("edgeR", ask=FALSE, update=FALSE)'
Rscript -e 'cat(as.character(packageVersion("edgeR")))'   # 断言
```

Conda 安装（推荐，可固定版本）：

```bash
mamba create -n edger -c conda-forge -c bioconda bioconductor-edger=4.8.2
mamba run -n edger Rscript -e 'cat(as.character(packageVersion("edgeR")))'   # 断言
```

> 一键安装直接 `bash native/install.sh`（auto：有 conda 走 bioconda，否则 BiocManager）。
> Homebrew 无 edger 公式（`formulae.brew.sh/api/formula/edger.json` 404），故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker pull quay.io/biocontainers/bioconductor-edger:4.8.2--r45h262fe30_1
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-edger:4.8.2--r45h262fe30_1 \
    Rscript -e 'library(edgeR); cat(as.character(packageVersion("edgeR")), "\n")'
```

### 3. Apptainer / Singularity

```bash
# galaxyproject 已预构建 sif，直接拉取（无需本地从 quay docker 转换）
apptainer pull edger.sif docker://depot.galaxyproject.org/singularity/bioconductor-edger:4.8.2--r45h262fe30_1
apptainer exec edger.sif Rscript -e 'library(edgeR); cat(as.character(packageVersion("edgeR")), "\n")'
```

## 官方实现登记（不建目录）

* **nf-core**：无 `modules/nf-core/edger` 子模块（2026-09-11 核实 404）；Nextflow 场景以
  native Rscript 驱动为兜底。
* **snakemake-wrappers**：无 `bio/edger` wrapper（2026-09-11 核实 404）；Snakemake 场景以
  native 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + R 脚本内容断言 + schema 自省（无需本机 R）
```

## 版本

* edgeR 4.8.2（文档未标注版本；2026-09-11 核实 bioconda 最新为 4.8.2）
* nf-core / snakemake-wrappers 均无 edgeR 官方子模块（2026-09-11 在线核实 404）
* 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）已覆盖，本地不自建配方

## 容器与 Conda 链接

**文献**：Robinson MD, et al. (2010) Bioinformatics

* **Bioconductor**：<https://bioconductor.org/packages/edgeR/>
* **bioconda**：<https://anaconda.org/bioconda/bioconductor-edger>
* **Docker（官方镜像）**：`quay.io/biocontainers/bioconductor-edger:4.8.2--r45h262fe30_1`
* **Singularity（官方镜像）**：<https://depot.galaxyproject.org/singularity/bioconductor-edger%3A4.8.2--r45h262fe30_1>
* 安装方式（本地）：`bash native/install.sh`（conda `bioconductor-edger=4.8.2` 优先，无 conda 走 BiocManager）
