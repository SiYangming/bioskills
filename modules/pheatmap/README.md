# pheatmap 软件模块

> 汇总说明：pheatmap 是 R 包（CRAN，无独立命令行二进制），本模块以 Rscript 驱动 `pheatmap()`
> 绘制差异基因表达热图（标准化/双向聚类/列注释/输出 PDF 或 PNG）；安装方式见「环境安装」，
> 容器与 conda 链接见文末。conda 规范包名为 **r-pheatmap**（conda-forge 1.0.13）。
> 对应 `docs/09.md`「5.1 pheatmap 热图」。

***

## native 实现

`source_type: custom`、`type: native`。软件本体为 CRAN R 包，无 CLI，因此 `native/main.py`
以 `Rscript -e "<R 表达式>"` 方式调用 pheatmap 的 `pheatmap()`。

## 功能

pheatmap 是一个常用的绘制热图的 R 包，可以进行双向聚类。

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `plot` | `pheatmap()` | 绘制表达热图：行/列标准化、双向层次聚类、行列注释、`log2(x+1)` 转换、直接输出 PDF/PNG |

## 用法

```bash
# 基本热图（按行标准化，隐藏基因名，输出 PDF）
python main.py plot DEG_expression_matrix.txt -o heatmap.pdf \
    --scale row --show-rownames false

# 带样品列注释（condition）
python main.py plot DEG_expression_matrix.txt -o heatmap.pdf \
    --scale row --annotation sample_annotation.txt --title "Differential Gene Expression Heatmap"

# 关闭 log2 转换 / 关闭列聚类 / 输出 PNG
python main.py plot DEG_expression_matrix.txt -o heatmap.png \
    --no-log2 --no-cluster-cols --scale none

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 仅作接口统一（pheatmap 为单线程
绘图），会在加载包前设置 `OMP/OPENBLAS/MKL/VECLIB` 线程数环境变量（对大矩阵距离计算/聚类有边际影响）。

## 实战示例

**等价能力由 `native/main.py` 的
`plot` 子命令提供**（见上「用法」）——CLI 侧把这段 R 代码封装为参数化调用。

```r
library(pheatmap)

# 读取差异表达基因的表达矩阵
de_matrix <- read.table("DEG_expression_matrix.txt",
                        header = TRUE, row.names = 1, sep = "\t")

# log2 转换（如果未转换）
de_matrix_log <- log2(de_matrix + 1)

# 绘制热图
pheatmap(de_matrix_log,
         scale = "row",           # 按行标准化
         show_rownames = FALSE,   # 不显示基因名（基因太多时）
         show_colnames = TRUE,    # 显示样品名
         treeheight_row = 20,     # 行聚类树高度
         treeheight_col = 20,     # 列聚类树高度
         color = colorRampPalette(c("navy", "white", "firebrick3"))(100),
         main = "Differential Gene Expression Heatmap",
         annotation_col = data.frame(
             condition = factor(c("control", "control", "control",
                                  "treatment", "treatment", "treatment")),
             row.names = colnames(de_matrix_log)
         ))

# 保存为 PDF
pdf("heatmap.pdf", width = 8, height = 10)
pheatmap(de_matrix_log, scale = "row", show_rownames = FALSE)
dev.off()
```

> `native/main.py plot` 以 `--annotation` 传入列注释表（行样品、列注释），并用 `filename=` 直接
> 输出 PDF/PNG（等价于上面 `pdf(...)` + `dev.off()` 的组合）。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**已维护** r-pheatmap 镜像 →
直接拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑（conda/mamba 装工具）；**本地不维护
Dockerfile / Apptainer.def**。

### 1. Conda / brew（包管理器安装）

```bash
# 推荐：conda/mamba 建独立环境（conda-forge 版本与 meta software_versions 对齐）
mamba create -n pheatmap -c conda-forge -c bioconda r-pheatmap=1.0.13
mamba run -n pheatmap Rscript -e 'cat(as.character(packageVersion("pheatmap")))'   # 断言

# 一键安装也可直接运行本模块脚本（auto：有 conda 走 conda，否则 R CRAN）
bash native/install.sh --help
```

> Homebrew **无** pheatmap 公式（`formulae.brew.sh/api/formula/pheatmap.json` 404，已核实）；
> R 包统一走 conda/CRAN，故不登记 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/r-pheatmap:1.0.8--r3.3.2_0
# 注意：必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/r-pheatmap:1.0.8--r3.3.2_0 \
    Rscript -e 'library(pheatmap); cat(as.character(packageVersion("pheatmap")), "\n")'
```

> ⚠️ 官方 r-pheatmap 镜像 tag 为 1.0.8（R 3.3，较老，bioconda 停更）；需要 1.0.13 + 新 R 时
> 建议宿主机 conda（conda-forge）或容器内 `install.packages("pheatmap")`。

### 3. Apptainer / Singularity（depot 预构建 sif 直拉）

```bash
apptainer pull pheatmap.sif docker://depot.galaxyproject.org/singularity/r-pheatmap:1.0.8--r3.3.2_0
apptainer run -B $PWD:/data -H /data pheatmap.sif Rscript -e 'library(pheatmap); sessionInfo()'
```

## 测试

```bash
bash test/run_test.sh   # argv（Rscript -e 表达式）构造 + schema 自省为常驻断言，不真实执行 R
```

## 容器与 Conda 链接

* **CRAN**：<https://cran.r-project.org/package=pheatmap>（上游，当前 1.0.13）
* **conda-forge**：<https://anaconda.org/conda-forge/r-pheatmap>（最新 1.0.13）
* **bioconda**：<https://anaconda.org/bioconda/r-pheatmap>（仅 1.0.8）
* **quay.io/biocontainers**：`quay.io/biocontainers/r-pheatmap:1.0.8--r3.3.2_0`
* **depot.galaxyproject.org**：<https://depot.galaxyproject.org/singularity/r-pheatmap%3A1.0.8--r3.3.2_0>
* nf-core modules（`modules/nf-core/pheatmap`）、snakemake-wrappers（`bio/pheatmap`）**均无官方子模块**
  （2026-09-11 在线核实 404）
* 安装方式（本地）：`mamba create -n pheatmap -c conda-forge -c bioconda r-pheatmap=1.0.13`

## 版本

* pheatmap 1.0.13（conda-forge，与 CRAN 一致；bioconda/官方镜像为 1.0.8；docs/09.md 未标注版本）
* 构建路线：官方 biocontainer 已维护（quay / depot r-pheatmap:1.0.8）→ 不维护本地配方；宿主机用 conda/mamba
* nf-core / snakemake-wrappers 均无 pheatmap 官方子模块（2026-09-11 在线核实 404）
