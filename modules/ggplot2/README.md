# ggplot2 软件模块

> 汇总说明：ggplot2 是 R 包（CRAN，无独立命令行二进制），本模块以 Rscript 驱动 ggplot2 绘制
> 差异表达火山图（log2FC vs -log10(padj)，阈值分组着色 + 阈值虚线）并用 `ggsave()` 输出；
> 安装方式见「环境安装」，容器与 conda 链接见文末。conda 规范包名为 **r-ggplot2**（conda-forge 4.0.3）。
> 对应 `docs/09.md`「5.2 ggplot2 火山图」。

***

## native 实现

`source_type: custom`、`type: native`。软件本体为 CRAN R 包，无 CLI，因此 `native/main.py`
以 `Rscript -e "<R 表达式>"` 方式调用 ggplot2。

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `volcano` | `ggplot()` + `geom_point()` + `geom_vline()`/`geom_hline()` + `ggsave()` | 差异表达火山图：Up/Down/Not significant 三色分组、log2FC 与 padj 阈值虚线，输出 PDF/PNG |

## 用法

```bash
# 基本火山图（DESeq2 结果表，默认阈值 padj<0.05 且 |log2FC|>1）
python main.py volcano DESeq2_results.txt -o volcano_plot.pdf \
    --lfc-cutoff 1 --padj-cutoff 0.05

# 自定义列名与阈值（如 FDR 列）
python main.py volcano DESeq2_results.txt -o volcano_plot.png \
    --padj-col FDR --lfc-cutoff 2 --padj-cutoff 0.01 --title "Volcano Plot"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 仅作接口统一（ggplot2 为单线程
绘图），会在加载包前设置 `OMP/OPENBLAS/MKL/VECLIB` 线程数环境变量。

## 实战示例

**等价能力由 `native/main.py` 的
`volcano` 子命令提供**（见上「用法」）——CLI 侧把这段 R 代码封装为参数化调用。

火山图是展示差异表达基因的常用可视化方法，x 轴为 log2FC，y 轴为 -log10(padj)。

```r
library(ggplot2)
library(ggrepel)

# 读取差异表达分析结果
res <- read.table("DESeq2_results.txt", header = TRUE, row.names = 1, sep = "\t")

# 添加分组信息
res$group <- "Not significant"
res$group[res$padj < 0.05 & res$log2FoldChange > 1] <- "Up-regulated"
res$group[res$padj < 0.05 & res$log2FoldChange < -1] <- "Down-regulated"

# 绘制火山图
p <- ggplot(res, aes(x = log2FoldChange, y = -log10(padj), color = group)) +
    geom_point(alpha = 0.5, size = 1) +
    scale_color_manual(values = c("Down-regulated" = "blue",
                                   "Not significant" = "gray",
                                   "Up-regulated" = "red")) +
    geom_vline(xintercept = c(-1, 1), linetype = "dashed", color = "black") +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "black") +
    theme_bw() +
    labs(x = "log2(Fold Change)",
         y = "-log10(Adjusted p-value)",
         title = "Volcano Plot of Differential Gene Expression") +
    theme(plot.title = element_text(hjust = 0.5))

# 添加部分基因标签（可选）
# top_genes <- head(rownames(res[order(res$padj), ]), 20)
# p + geom_text_repel(data = res[top_genes, ],
#                    aes(label = rownames(res[top_genes, ])),
#                    max.overlaps = 20)

# 保存图片
ggsave("volcano_plot.pdf", p, width = 8, height = 6)
```

> 文档中注释的 `geom_text_repel` 基因标签由独立的 **ggrepel 模块** `label` 子命令提供
> （见 `modules/ggrepel/README.md`）；本模块只输出无标签的火山图。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已维护** r-ggplot2 镜像 →
直接拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑（conda/mamba 装工具）；**本地不维护
Dockerfile / Apptainer.def**。

### 1. Conda / brew（包管理器安装）

```bash
# 推荐：conda/mamba 建独立环境（conda-forge 版本与 meta software_versions 对齐）
mamba create -n ggplot2 -c conda-forge -c bioconda r-ggplot2=4.0.3
mamba run -n ggplot2 Rscript -e 'cat(as.character(packageVersion("ggplot2")))'   # 断言

# 一键安装也可直接运行本模块脚本（auto：有 conda 走 conda，否则 R CRAN）
bash native/install.sh --help
```

> Homebrew **无** ggplot2 公式（`formulae.brew.sh/api/formula/ggplot2.json` 404，已核实）；
> R 包统一走 conda/CRAN，故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/r-ggplot2:2.2.1--r3.3.2_0
# 注意：必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/r-ggplot2:2.2.1--r3.3.2_0 \
    Rscript -e 'library(ggplot2); cat(as.character(packageVersion("ggplot2")), "\n")'
```

> ⚠️ 官方 r-ggplot2 镜像 tag 为 2.2.1（R 3.3，较老，bioconda 停更）；需要 4.x + 新 R 时
> 建议宿主机 conda（conda-forge）或容器内 `install.packages("ggplot2")`。

### 3. Apptainer / Singularity（depot 预构建 sif 直拉）

```bash
apptainer pull ggplot2.sif docker://depot.galaxyproject.org/singularity/r-ggplot2:2.2.1--r3.3.2_0
apptainer run -B $PWD:/data -H /data ggplot2.sif Rscript -e 'library(ggplot2); sessionInfo()'
```

## 测试

```bash
bash test/run_test.sh   # argv（Rscript -e 表达式）构造 + schema 自省为常驻断言，不真实执行 R
```

## 容器与 Conda 链接

* **官网**：<https://ggplot2.tidyverse.org/>（CRAN ggplot2 4.0.3）
* **conda-forge**：<https://anaconda.org/conda-forge/r-ggplot2>（最新 4.0.3）
* **bioconda**：<https://anaconda.org/bioconda/r-ggplot2>（仅 2.2.1）
* **quay.io/biocontainers**：`quay.io/biocontainers/r-ggplot2:2.2.1--r3.3.2_0`
* **depot.galaxyproject.org**：<https://depot.galaxyproject.org/singularity/r-ggplot2%3A2.2.1--r3.3.2_0>
* nf-core modules（`modules/nf-core/ggplot2`）、snakemake-wrappers（`bio/ggplot2`）**均无官方子模块**
  （2026-09-11 在线核实 404）
* 安装方式（本地）：`mamba create -n ggplot2 -c conda-forge -c bioconda r-ggplot2=4.0.3`

## 版本

* ggplot2 4.0.3（conda-forge，与 CRAN 一致；bioconda/官方镜像为 2.2.1；docs/09.md 未标注版本）
* 构建路线：官方 biocontainer 已维护（quay / depot r-ggplot2:2.2.1）→ 不维护本地配方；宿主机用 conda/mamba
* nf-core / snakemake-wrappers 均无 ggplot2 官方子模块（2026-09-11 在线核实 404）
