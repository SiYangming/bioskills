# ggrepel 软件模块

> 汇总说明：ggrepel 是 R 包（CRAN，无独立命令行二进制），本模块以 Rscript 驱动
> `ggrepel::geom_text_repel()` 为差异表达火山图添加不重叠的基因标签；安装方式见「环境安装」，
> 容器与 conda 链接见文末。conda 规范包名为 **r-ggrepel**（conda-forge 0.9.8）。

***

## native 实现

`source_type: custom`、`type: native`。软件本体为 CRAN R 包，无 CLI，因此 `native/main.py`
以 `Rscript -e "<R 表达式>"` 方式调用 ggrepel（依赖 ggplot2）。

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `label` | `ggrepel::geom_text_repel()`（叠加在 ggplot2 火山图上） | 按 padj 取 top-N 基因，在火山图上不重叠标注基因名（`--max-overlaps` 控制重叠），输出 PDF/PNG |

## 用法

```bash
# 火山图 + top-20 基因标签
python main.py label DESeq2_results.txt -o volcano_labeled.pdf \
    --top 20 --max-overlaps 20 --padj-cutoff 0.05 --lfc-cutoff 1

# 只标注 top-10、允许更多重叠，输出 PNG
python main.py label DESeq2_results.txt -o volcano_labeled.png \
    --top 10 --max-overlaps 30

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 仅作接口统一（ggrepel/ggplot2 为
单线程绘图），会在加载包前设置 `OMP/OPENBLAS/MKL/VECLIB` 线程数环境变量。

## 实战示例（火山图基因标签）

以下为 `geom_text_repel` 基因标签代码；
**等价能力由 `native/main.py` 的 `label` 子命令提供**（见上「用法」）——CLI 侧把「火山图 + 标签」
封装为一次参数化调用（无标签火山图见 ggplot2 模块的 `volcano` 子命令）。

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
top_genes <- head(rownames(res[order(res$padj), ]), 20)
p + geom_text_repel(data = res[top_genes, ],
                   aes(label = rownames(res[top_genes, ])),
                   max.overlaps = 20)

# 保存图片
ggsave("volcano_plot.pdf", p, width = 8, height = 6)
```

> `native/main.py label --top N --max-overlaps M` 与上面 `geom_text_repel(..., max.overlaps = 20)`
> 等价（按 padj 取 top-N 基因标注），并直接 `ggsave` 输出带标签的火山图。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已维护** r-ggrepel 镜像 →
直接拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑（conda/mamba 装工具）；**本地不维护
Dockerfile / Apptainer.def**。

### 1. Conda / brew（包管理器安装）

```bash
# 推荐：conda/mamba 建独立环境（conda-forge 版本与 meta software_versions 对齐）
mamba create -n ggrepel -c conda-forge -c bioconda r-ggrepel=0.9.8
mamba run -n ggrepel Rscript -e 'cat(as.character(packageVersion("ggrepel")))'   # 断言

# 一键安装也可直接运行本模块脚本（auto：有 conda 走 conda，否则 R CRAN）
bash native/install.sh --help
```

> Homebrew **无** ggrepel 公式（`formulae.brew.sh/api/formula/ggrepel.json` 404，已核实）；
> R 包统一走 conda/CRAN，故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/r-ggrepel:0.6.5--r3.3.2_0
# 注意：必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/r-ggrepel:0.6.5--r3.3.2_0 \
    Rscript -e 'library(ggrepel); cat(as.character(packageVersion("ggrepel")), "\n")'
```

> ⚠️ 官方 r-ggrepel 镜像 tag 为 0.6.5（R 3.3，较老，bioconda 停更）；需要 0.9.x + 新 R 时
> 建议宿主机 conda（conda-forge）或容器内 `install.packages("ggrepel")`。

### 3. Apptainer / Singularity（depot 预构建 sif 直拉）

```bash
apptainer pull ggrepel.sif docker://depot.galaxyproject.org/singularity/r-ggrepel:0.6.5--r3.3.2_0
apptainer run -B $PWD:/data -H /data ggrepel.sif Rscript -e 'library(ggrepel); sessionInfo()'
```

## 测试

```bash
bash test/run_test.sh   # argv（Rscript -e 表达式）构造 + schema 自省为常驻断言，不真实执行 R
```

## 容器与 Conda 链接

* **CRAN**：<https://cran.r-project.org/package=ggrepel>（上游，当前 0.9.8）
* **conda-forge**：<https://anaconda.org/conda-forge/r-ggrepel>（最新 0.9.8）
* **bioconda**：<https://anaconda.org/bioconda/r-ggrepel>（仅 0.6.5）
* **quay.io/biocontainers**：`quay.io/biocontainers/r-ggrepel:0.6.5--r3.3.2_0`
* **depot.galaxyproject.org**：<https://depot.galaxyproject.org/singularity/r-ggrepel%3A0.6.5--r3.3.2_0>
* nf-core modules（`modules/nf-core/ggrepel`）、snakemake-wrappers（`bio/ggrepel`）**均无官方子模块**
  （2026-09-11 在线核实 404）
* 安装方式（本地）：`mamba create -n ggrepel -c conda-forge -c bioconda r-ggrepel=0.9.8`

## 版本

* ggrepel 0.9.8（conda-forge，与 CRAN 一致；bioconda/官方镜像为 0.6.5）
* 构建路线：官方 biocontainer 已维护（quay / depot r-ggrepel:0.6.5）→ 不维护本地配方；宿主机用 conda/mamba
* nf-core / snakemake-wrappers 均无 ggrepel 官方子模块（2026-09-11 在线核实 404）
