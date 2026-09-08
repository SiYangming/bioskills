# r_matrixeqtl 软件模块

> 汇总说明：Matrix eQTL 是 R 包（无独立命令行二进制），本模块以 Rscript 驱动
> `Matrix_eQTL_main()` 完成 eQTL 关联分析；安装方式见「环境安装」，容器与 conda 链接见文末。
> conda / 容器规范包名为 **r-matrixeqtl**（连字符），目录名沿用仓库历史形态 **r_matrixeqtl**。

***

## native 实现

# r_matrixeqtl / native — Rscript 驱动的 eQTL 关联分析

Matrix eQTL 的本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 CRAN R 包
（LGPL-3，v2.3；纯 R 实现，NeedsCompilation: no），无 CLI，因此 `native/main.py` 以
`Rscript native/run_matrixeqtl.R <params.tsv>` 方式调用 `Matrix_eQTL_main()`。

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `analyze` | `Rscript run_matrixeqtl.R`（内部 `Matrix_eQTL_main`） | SNP × 基因表达 eQTL 关联分析；支持 linear / anova / linear_cross 模型、协变量校正、可选 cis 分区（分别输出 trans 与 `.cis` 结果） |

## 用法

```bash
# CLI 直跑（trans 分析；结果写 eqtl_result.txt）
python main.py analyze snps.txt ge.txt -o eqtl_result.txt \
    --pv-threshold 1e-3 --covariates covariates.txt --threads 8

# cis + trans 分区（需 SNP / 基因位置表，--pv-threshold-cis > 0 即启用）
python main.py analyze snps.txt ge.txt -o eqtl_result.txt \
    --pv-threshold 1e-5 --pv-threshold-cis 1e-3 --cis-dist 1000000 \
    --snpspos snpspos.txt --genepos genepos.txt

# --output-prefix 双输出 + 别名参数（与上行等价；产物 eqtl_eQTL_trans.txt / eqtl_eQTL_cis.txt）
python main.py analyze snps.txt ge.txt --output-prefix eqtl \
    --trans-p 1e-5 --cis-p 1e-3 --cis-dist 1000000 \
    --snps-loc snpspos.txt --gene-loc genepos.txt
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 接受 `auto` 或正整数：
`auto`（默认）与缺省时不写 `threads` 参数，由 R 驱动按「物理核数-1」自动检测并设置
BLAS 线程（并设 OMP/OPENBLAS/VECLIB/MKL 环境变量）；正整数则显式 pin 该线程数
（若安装 RhpcBLASctl 会经 `blas_set_num_threads` 生效，未装时静默忽略）。

**`--threads` 在 R 驱动（`run_matrixeqtl.R`）中的具体生效机制**：
1. **解析**：`auto`/缺省 → 驱动内 `auto_cores()` 用 `parallel::detectCores(logical=FALSE)` 取
   物理核数并减 1（探测失败依次回退逻辑核数 / 4）；正整数 → `as.integer` 原样 pin；
2. **生效（先于 `library(MatrixEQTL)`）**：`Sys.setenv` 设置 `OMP_NUM_THREADS`、
   `OPENBLAS_NUM_THREADS`、`VECLIB_MAXIMUM_THREADS`、`MKL_NUM_THREADS`（OpenBLAS /
   Apple Accelerate / MKL 的多线程 BLAS 入口在首次矩阵运算前读取该值）；若已安装
   `RhpcBLASctl` 再调用 `blas_set_num_threads()` 直接改当前进程 BLAS 线程（未装静默跳过）；
3. **作用面**：`Matrix_eQTL_main` 为纯 R 大矩阵运算，加速来自 R 底层多线程 BLAS 而非 R 自身；
   macOS M 系列建议配 Apple Accelerate 或 ARM OpenBLAS（驱动启动时会打印当前 BLAS 提示）。

> 也可跳过 main.py 直接调 R 驱动（独立 CLI 模式，M1/服务器直跑；参数名大小写与 `-`/`_`
> 等价，如 `--SNP_file`=`--SNP-file`）。`--output-prefix` 时产出 `<prefix>_eQTL_trans.txt`、
> `<prefix>_eQTL_cis.txt`；`--output` 时 cis 文件为 `<output>.cis`：
>
> ```bash
> Rscript run_matrixeqtl.R --SNP-file snps.txt --exp-file ge.txt \
>     --covariates-file covariates.txt --snps-loc snpspos.txt --gene-loc genepos.txt \
>     --output-prefix eqtl --trans-p 1e-5 --cis-p 1e-3 --threads 8
> # 产物：eqtl_eQTL_trans.txt + eqtl_eQTL_cis.txt（依赖仅 R + MatrixEQTL）
> Rscript run_matrixeqtl.R --help
> ```

## 实战示例：全基因组 eQTL 分析

以下为典型批量 eQTL 流程；等价能力由 `native/main.py` 的 `analyze` 子命令提供（见上「用法」）。
Matrix eQTL 官方协议见 <https://www.bios.unc.edu/research/genomic_software/Matrix_eQTL/Rpackage.html>
与 CRAN 小抄（`browseVignettes("MatrixEQTL")`）。

### 1. 输入文件准备（Tab 分隔，样本列对齐）

* **基因型** `snps.txt`：首列 SNP id，首行样本 id，取值 0/1/2（或 NA），如 `rs1  0 1 2 …`
* **表达** `ge.txt`：首列 gene id，首行样本 id；样本列顺序必须与 `snps.txt` 一致
* **协变量**（可选）`covariates.txt`：首列协变量名，样本列顺序同上；不要含常数列
* **位置表**（仅 cis 分区需要）：`snpspos.txt`（snpid chr pos）、`genepos.txt`（geneid chr left right）

### 2. 运行分析

```bash
# 单样本组：全距离（trans）eQTL，阈值 1e-5
python main.py analyze snps.txt ge.txt -o eqtl_result.txt \
    --pv-threshold 1e-5 --threads 8

# 结果结构：SNP 基因名 / gene / statistic / p-value / FDR / beta；行按 p 值升序
head eqtl_result.txt
```

### 3. 大批量分层运行（按染色体拆分）

```bash
# 按 SNP 位置拆文件后逐条运行（此处用循环示范；实际建议用 xargs -P 或流程编排）
for chr in chr1 chr2 chr3; do
    python main.py analyze snps.${chr}.txt ge.txt \
        -o eqtl_result.${chr}.txt --pv-threshold 1e-5 &
done
wait
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--model` | `linear`（加性线性，默认）/ `anova`（加性+显性）/ `linear_cross`（线性×协变量，需协变量） |
| `--pv-threshold` | trans/全距离关联显著性阈值（默认 1e-5；输出全距离显著 eQTL） |
| `--pv-threshold-cis` | cis 阈值（默认 0=不分区；>0 时另写 `<output>.cis`） |
| `--cis-dist` | cis 窗口 bp（默认 1e6） |
| `--slice-size` | SlicedData 分片大小（默认 2000，内存受限可调小） |
| `--threads` | `auto`（默认，按物理核数-1 自动检测）或正整数（显式 pin） |
| `--covariates` | 协变量矩阵（校正群体分层 / 性别等） |

## 环境安装（容器与安装方式；官方老镜像 + 自建新版配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**有** r-matrixeqtl
老镜像（版本 2.1.1，R 3.3/3.4，2026 年前构建后未再更新），但**无现代 R 版本构建** → 本模块
在登记官方老镜像之外，保留 `native/Dockerfile` + `native/Apptainer.def`（rocker/r-ver:4.5.2 +
MatrixEQTL 2.3）作为新版替代的推荐容器路线；宿主机推荐 R>=4.2 + CRAN 直装。

### 1. 包管理器安装（R CRAN / Conda）

R 是 MatrixEQTL 的包管理器宿主；CRAN 直装最简（自动装到最新版，接口与 2.3 一致）：

```bash
Rscript -e 'install.packages("MatrixEQTL", repos = "https://cloud.r-project.org")'
Rscript -e 'cat(as.character(packageVersion("MatrixEQTL")))'   # 断言
```

> 一键安装也可直接运行 `bash native/install.sh`（auto 路线：有 Rscript → CRAN 直装；
> 无 Rscript → 建 conda env（r-base）再用其 Rscript 装包。用法：`bash native/install.sh --help`）。

conda 备选（仅提供 R 运行时，包仍从 CRAN 装）：

```bash
mamba create -n r-matrixeqtl -c conda-forge r-base
mamba run -n r-matrixeqtl Rscript -e 'install.packages("MatrixEQTL", repos="https://cloud.r-project.org")'
```

> Homebrew 无 MatrixEQTL 公式（`formulae.brew.sh/api/formula/r-matrixeqtl.json` 404；
> homebrew 的 `r` 公式只提供 R 本体，R 包统一走 CRAN），故不登记 brew 块。

### 2. Docker

```bash
# 推荐：自建新版镜像（R 4.5.2 + MatrixEQTL，含内置驱动 run_matrixeqtl.R）
docker build -t r-matrixeqtl:2.3 modules/r_matrixeqtl/native/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    r-matrixeqtl:2.3 Rscript /opt/skill/run_matrixeqtl.R /data/params.tsv

# 官方老镜像（版本 2.1.1，R 3.3；仅兼容老 R 环境时使用）
docker pull quay.io/biocontainers/r-matrixeqtl:2.1.1--r3.3.1_0
```

### 3. Apptainer / Singularity

```bash
# 官方老镜像：galaxyproject 已预构建 sif，直接拉取
apptainer pull r-matrixeqtl.sif docker://depot.galaxyproject.org/singularity/r-matrixeqtl:2.1.1--r3.4.1_0

# 新版替代：本地从 native/Apptainer.def 构建
apptainer build r-matrixeqtl-2.3.sif modules/r_matrixeqtl/native/Apptainer.def
apptainer run -B $PWD:/data -H /data r-matrixeqtl-2.3.sif Rscript /opt/skill/run_matrixeqtl.R /data/params.tsv
```

### 4. 源码归档安装（CRAN，无 R 网络亦可）

```bash
# 下载源码归档（2.3；当前 CRAN 最新可能已至 2.4）
wget https://cran.r-project.org/src/contrib/MatrixEQTL_2.3.tar.gz -P ~/software/
R CMD INSTALL ~/software/MatrixEQTL_2.3.tar.gz
```

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；Rscript+MatrixEQTL 可用时真实回归
```

## 版本

* r-matrixeqtl 2.3（CRAN MatrixEQTL 2.3；2026-09 CRAN 已发布 2.4，接口一致）
* 构建路线：官方 biocontainer 仅 2.1.1/R3.3（老）→ 推荐自建 `native/Dockerfile`
  （rocker/r-ver:4.5.2）+ 宿主机 CRAN 直装
* nf-core / snakemake-wrappers 均无 r-matrixeqtl 官方子模块（2026-09 在线核实 404）

## 历史留存

目录历史中的 `Dockerfile_r_4_5_2_matrixeqtl_2_3_openBlas_no_root` 与
`Dockerfile_r_4_5_2_matrixeqtl_openBlas` 两个草稿配方已整理合并为 `native/Dockerfile`
（rocker/r-ver:4.5.2 底座、去除固定 UID 用户——容器运行一律 `-u $(id -u):$(id -g)`）。

## 容器与 Conda 链接

* **CRAN**：<https://cran.r-project.org/package=MatrixEQTL>（上游；作者页
  <https://github.com/andreyshabalin/MatrixEQTL>）
* **conda r 频道**：<https://anaconda.org/channels/r/packages/r-matrixeqtl/overview>
* **Docker（官方老镜像）**：`docker pull quay.io/biocontainers/r-matrixeqtl:2.1.1--r3.3.1_0`
* **Singularity（官方老镜像）**：<https://depot.galaxyproject.org/singularity/r-matrixeqtl%3A2.1.1--r3.4.1_0>
* **自建新版配方**：`native/Dockerfile` + `native/Apptainer.def`（rocker/r-ver:4.5.2 + MatrixEQTL 2.3）
* **社区镜像（同自建配方，已发布）**：`docker pull quay.io/bioinfortools/r_matrixeqtl:2.3`（rocker/r-ver:4.5.2 + OpenBLAS + MatrixEQTL 2.3）
* 安装方式（本地）：`Rscript -e 'install.packages("MatrixEQTL", repos="https://cloud.r-project.org")'`
