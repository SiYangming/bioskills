# ballgown 软件模块

> 汇总说明：Ballgown 是 R/Bioconductor 包（无独立命令行二进制），本模块以 Rscript 驱动
> `ballgown()` / `stattest()` 读取 StringTie 输出目录完成转录本级差异表达分析；安装方式见
> 「环境安装」，容器与 conda 链接见文末。conda 包名 **bioconductor-ballgown**。

***

## native 实现

# ballgown / native — Rscript 驱动的转录本水平差异表达分析

Ballgown 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 Bioconductor
R 包（Artistic-2.0；文档未标注版本，2026-09-11 核实 bioconda 最新为 2.42.0），无 CLI，
因此 `native/main.py` 以 `Rscript <生成的 R 脚本>` 方式调用 Ballgown 函数。

## 功能

Ballgown 是用于转录本水平差异表达分析的 R 包，可以直接使用 StringTie 的输出结果。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `analyze` | `ballgown()` → `gexpr()` 过滤 → `stattest()` | 基因与转录本两水平的差异表达分析，输出 `<prefix>.gene.txt` 与 `<prefix>.transcript.txt` |
| `check` | `library(ballgown)` | 校验包可加载并打印 `packageVersion` |

## 用法

```bash
# 差异表达分析（StringTie 输出目录 + 分组表；写 ballgown_out.gene.txt / .transcript.txt）
python main.py analyze stringtie_out/ coldata.txt -o ballgown_out \
    --sample-pattern sample --covariate condition --min-expr 1 --threads 8

# 包可用性校验
python main.py check
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。线程优先级：
`--threads` > `optimization.per_subcommand_threads` > `optimization.default_cpus`。
Ballgown `stattest` 为单线程线性模型计算，`--threads` 映射为 **BLAS 线程环境变量**
（`OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS`），仅影响底层矩阵运算，无多线程加速路径。

## 实战示例：StringTie + Ballgown 转录本水平差异表达

文档「3.2 Ballgown」给出的典型 R 代码（等价能力由 `native/main.py` 的 `analyze` 子命令提供）：

```r
library(ballgown)
library(genefilter)
library(dplyr)

# 读取样品信息（control 与 treatment 各 3 个重复）
pheno_data <- data.frame(
    ids = c("sample1", "sample2", "sample3", "sample4", "sample5", "sample6"),
    condition = c("control", "control", "control", "treatment", "treatment", "treatment")
)

# 创建 ballgown 对象（StringTie 输出目录）
bg <- ballgown(dataDir = "stringtie_out/", samplePattern = "sample", pData = pheno_data)

# 过滤低表达转录本
bg_filt <- bg[gexpr(bg) %>% rowSums() > 1, ]

# 基因水平差异表达分析
results_genes <- stattest(bg_filt, feature = "gene", covariate = "condition",
                          adjustvars = NULL, getFC = TRUE)

# 转录本水平差异表达分析
results_transcripts <- stattest(bg_filt, feature = "transcript", covariate = "condition",
                                adjustvars = NULL, getFC = TRUE)

write.table(results_genes, "ballgown_gene_results.txt", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(results_transcripts, "ballgown_transcript_results.txt", sep = "\t", quote = FALSE, row.names = FALSE)
```

桥接：上述 `ballgown()` → `gexpr()` 过滤 → `stattest(feature="gene"/"transcript")` 等价于
`python main.py analyze stringtie_out/ coldata.txt -o ballgown_out`，产物为
`ballgown_out.gene.txt` 与 `ballgown_out.transcript.txt`（本模块用 base R `rowSums` 过滤，
与文档 `%>% rowSums()` 等价，避免额外 dplyr 依赖）。

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--sample-pattern` | `ballgown()` 样品文件名匹配模式（默认 `sample`） |
| `--covariate` | `stattest` 协变量列名（默认 `condition`） |
| `--min-expr` | 低表达过滤阈值 `rowSums(gexpr) > 阈值`（默认 1） |
| `--output-prefix` | 输出前缀（写 `<prefix>.gene.txt` 与 `<prefix>.transcript.txt`） |
| `--threads` | BLAS 线程数（优先级 `--threads` > 子命令默认 > 全局默认） |

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已覆盖** Ballgown
（`bioconductor-ballgown`）→ 本地不维护 Dockerfile/Apptainer.def；宿主机直跑 `main.py`
用 conda/mamba 安装，或直接 `docker run` 官方镜像。

### 1. 包管理器安装（Bioconductor / Conda）

Bioconductor 原生安装（R 路线）：

```bash
Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("ballgown", ask=FALSE, update=FALSE)'
Rscript -e 'cat(as.character(packageVersion("ballgown")))'   # 断言
```

Conda 安装（推荐，可固定版本）：

```bash
mamba create -n ballgown -c conda-forge -c bioconda bioconductor-ballgown=2.42.0
mamba run -n ballgown Rscript -e 'cat(as.character(packageVersion("ballgown")))'   # 断言
```

> 一键安装直接 `bash native/install.sh`（auto：有 conda 走 bioconda，否则 BiocManager）。
> Homebrew 无 ballgown 公式（`formulae.brew.sh/api/formula/ballgown.json` 404），故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker pull quay.io/biocontainers/bioconductor-ballgown:2.42.0--r45hdfd78af_0
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-ballgown:2.42.0--r45hdfd78af_0 \
    Rscript -e 'library(ballgown); cat(as.character(packageVersion("ballgown")), "\n")'
```

### 3. Apptainer / Singularity

```bash
# galaxyproject 已预构建 sif，直接拉取（无需本地从 quay docker 转换）
apptainer pull ballgown.sif docker://depot.galaxyproject.org/singularity/bioconductor-ballgown:2.38.0--r44hdfd78af_0
apptainer exec ballgown.sif Rscript -e 'library(ballgown); cat(as.character(packageVersion("ballgown")), "\n")'
```

## 官方实现登记（不建目录）

* **nf-core**：无 `modules/nf-core/ballgown` 子模块（2026-09-11 核实 404）；Nextflow 场景以
  native Rscript 驱动为兜底。
* **snakemake-wrappers**：无 `bio/ballgown` wrapper（2026-09-11 核实 404）；Snakemake 场景以
  native 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + R 脚本内容断言 + schema 自省（无需本机 R）
```

## 版本

* Ballgown 2.42.0（文档未标注版本；2026-09-11 核实 bioconda 最新为 2.42.0）
* nf-core / snakemake-wrappers 均无 Ballgown 官方子模块（2026-09-11 在线核实 404）
* 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）已覆盖，本地不自建配方

## 容器与 Conda 链接

**文献**：Frazee AE, et al. (2015) Nature Biotechnology

* **GitHub（上游）**：<https://github.com/alyssafrazee/ballgown>
* **Bioconductor**：<https://bioconductor.org/packages/ballgown/>
* **bioconda**：<https://anaconda.org/bioconda/bioconductor-ballgown>
* **Docker（官方镜像）**：`quay.io/biocontainers/bioconductor-ballgown:2.42.0--r45hdfd78af_0`
* **Singularity（官方镜像）**：<https://depot.galaxyproject.org/singularity/bioconductor-ballgown%3A2.38.0--r44hdfd78af_0>
* 安装方式（本地）：`bash native/install.sh`（conda `bioconductor-ballgown=2.42.0` 优先，无 conda 走 BiocManager）
