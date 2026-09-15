# discovar 软件模块（DISCOVAR / DISCOVAR de novo — Broad Institute 组装器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **DISCOVAR / DISCOVAR de novo（版本 52488，Broad Institute；Weisenfeld et al. 2014）**
> 是面向 Illumina 短读的基因组组装/变异工具族：**DISCOVAR** 用参考基因组做区域组装与
> variant calling，**DISCOVAR de novo** 无参考从头组装大小基因组。程序族：
> `DiscovarDeNovo`（de novo）、`Discovar`（有参考）、`PrepareDiscovarGenome`（预生成
> 参考，生成 `<ref>.m100`，非常耗时）、`NhoodInfo`（组装邻域信息可视化）。
> 上游 **52488 之后停止维护**；官网
> <https://software.broadinstitute.org/software/discovar/blog/> 2026-09-11 探测
> **HTTP 200 但页面内容为 WordPress PHP 报错**（内容不可用）；`/software/discovar/download`
> 404；旧 Broad FTP `ftp://ftp.broadinstitute.org/pub/crd/…` 550（不可取）。
>
> **新项目请勿使用**——组装/变异已被 **GATK / SPAdes / wtdbg2 / Canu** 等替代。
> 本模块只做「录入」：方法/命令/链接准确登记、不产出自建容器配方
> （Dockerfile/Apptainer.def），仅供复现 2015 时代的 DISCOVAR 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方 `KEY=VALUE` 用法构造 DISCOVAR
命令行并打印，**不实际执行**（软件 deprecated、官方下载失效、无新用场景）。子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `discovardenovo` | `DiscovarDeNovo READS=<in.bam> OUT_DIR=<dir> NUM_THREADS=<N> [REFHEAD=<ref>]` | 无参考从头组装 |
| `discovar` | `Discovar READS=<in.bam> OUT_HEAD=<head> REGIONS=<chr:start-end> TMP=<tmp> [REFERENCE=<fa>]` | 有参考区域组装 / variant calling |
| `prepare` | `PrepareDiscovarGenome REF=<genome.fasta>` | 预生成参考（`<ref>.m100`，非常耗时） |
| `nhoodinfo` | `NhoodInfo OUT=<out> DIR_IN=<a.final/> SEEDS=<chr:pos> COUNT=True SHOW_INV=True` | 组装邻域信息可视化 |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 discovar，见「环境安装」）
python main.py discovardenovo --reads sample-reads.bam --out-dir asm --threads 4
python main.py discovardenovo --reads sample-reads.bam --out-dir asm-aligned \
    --refhead sample-genome --threads 4
python main.py discovar --reads sample-reads.bam --out-head asm/genome \
    --regions 10:30892106-30933760 --tmp asm/tmp
python main.py discovar --reads sample-reads.bam --reference sample-genome.fasta \
    --regions 10:30892106-30933760 --out-head variants/genome --tmp variants/tmp
python main.py prepare --ref sample-genome.fasta
python main.py nhoodinfo --out out --dir-in asm-aligned/a.final/ --seeds 10:30.5M

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`discovardenovo` 透传 `NUM_THREADS=`；其余不适用）与
`--tmpdir`（`discovar` 透传 `TMP=`）。构造命令通过 stderr 打印 deprecated 提示，
stdout 只输出命令本身。

***

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `READS=<in.bam>` | 输入 BAM 文件 |
| `OUT_DIR=<dir>` | `DiscovarDeNovo` 输出目录 |
| `NUM_THREADS=<N>` | 线程数 |
| `REFHEAD=<name>` | 有参考组装时的参考名（需 `<ref>.names` 等，如 `sample-genome`） |
| `OUT_HEAD=<head>` | `Discovar` 输出前缀（如 `discovar-assembly/genome`） |
| `REGIONS=<chr:start-end>` | 指定组装区域（如 `10:30892106-30933760`） |
| `TMP=<tmp>` | `Discovar` 临时目录 |
| `REFERENCE=<fa>` | `Discovar` variant calling 的参考 FASTA |
| `REF=<fa>` | `PrepareDiscovarGenome` 参考基因组（生成 `<ref>.m100`，非常耗时） |
| `OUT= / DIR_IN= / SEEDS=` | `NhoodInfo` 输出前缀 / 输入目录 / 种子区域 |
| `COUNT= / SHOW_INV=` | `NhoodInfo` 是否显示计数 / 倒位（`True`/`False`） |

> `NhoodInfo` 产物 `<out>.dot` 可用 `dot -Tsvg out.dot -o out.svg` + `convert out.svg
> out.png` 转图。结果行示例：`2850<2851>[1.04x](+10:30,434,920-51,125)C=3346(16K)`
> —— edge id 2850（反向互补 2851）、`1.04x` 双倍体出现率、`+` 正义链、比对区间、
> `C=` 覆盖度、`(16K)` edge 长度。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-11 在线核实，如实记录）：**上游停更**，Broad 官网页面功能性损坏、
> 旧 FTP 下载失效；bioconda 存在 **discovar=52488** 与 **discovardenovo=52488** 历史包
> （linux-64，均 MIT）→ quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建
> 镜像；但多年未随上游维护 → 判定「官方渠道存在但属历史遗留，不建议新项目依赖」；软件
> deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 discovar=52488 / discovardenovo=52488（linux-64，MIT）
mamba create -n discovar-native -c conda-forge -c bioconda discovar=52488 discovardenovo=52488
conda activate discovar-native
DiscovarDeNovo 2>&1 | head -2   # 断言：命令可达（52488 无统一 --version）
```

> Homebrew：formulae.brew.sh/api/formula/discovar.json 与 discovardenovo.json
> 均 404（2026-09-11 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 52488 老包自动构建）：

```bash
docker pull quay.io/biocontainers/discovar:52488--0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/discovar:52488--0 \
    DiscovarDeNovo READS=/data/sample-reads.bam OUT_DIR=/data/asm NUM_THREADS=4
# de novo 另用镜像 quay.io/biocontainers/discovardenovo:52488--0
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09-11 核实存在，与 quay tag 互通）：

```bash
apptainer pull discovar.sif docker://depot.galaxyproject.org/singularity/discovar:52488--0
apptainer run -B $PWD:/data -H /data discovar.sif \
    DiscovarDeNovo READS=/data/sample-reads.bam OUT_DIR=/data/asm NUM_THREADS=4
```

### 4. 二进制包安装（官方 release / 源码编译）

官方二进制渠道已失效（Broad 下载页 404、旧 FTP 550）；历史源码编译路线如下
（本文对照文档 04.md，安装前缀由 `/opt/biosoft/*` 改写为用户前缀 `~/software/*`，免 root）：

```bash
# 依赖：samtools 1.2、jemalloc 3.6.0（历史版本，见文档 04.md）
# DISCOVAR（有参考）
tar zxf ~/software/discovar.tar.gz
cd discovar-52488/
./configure --prefix=$HOME/software/discovar && make -j 4 && make install
export PATH="$HOME/software/discovar/bin:$PATH"

# DISCOVAR de novo（无参考）
tar zxf ~/software/discovardenovo.tar.gz
cd discovardenovo-52488/
./configure --prefix=$HOME/software/discovardenovo && make -j 4 all && make install
export PATH="$HOME/software/discovardenovo/bin:$PATH"
```

> ⚠️ 官方源码归档来源（Broad）**2026-09-11 已不可取**（下载页 404、FTP 550），
> 优先推荐 bioconda discovar=52488 / discovardenovo=52488 路线。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **GATK** | 变异检测事实标准（DISCOVAR variant calling 的现代替代） | <https://github.com/broadinstitute/gatk>（bioconda `gatk4`） |
| **SPAdes** | 短读/混合数据 de Bruijn 组装 | <https://github.com/ablab/spades>（bioconda `spades`） |
| **wtdbg2 / Canu** | 三代长读组装（现代 de novo 主流） | <https://github.com/ruanjue/wtdbg2> / <https://github.com/marbl/canu> |

## 版本

* **52488**（DISCOVAR 与 DISCOVAR de novo 同版本号；约 2014–2015 末版，
  2026-09-11 在线核实 Broad 官方页面损坏、下载失效）
* bioconda 版本号 **52488**（discovar + discovardenovo，linux-64，均 **MIT**；
  2026-09-11 api.anaconda.org 核实）
* License：bioconda 包元数据 **MIT**
* 引用：Weisenfeld NI, Yin S, Sharpe T, et al. Comprehensive variation discovery
  in single human genomes. *Nature Genetics* 2014;46(12):1350-5.
* nf-core / snakemake-wrappers：无官方子模块（2026-09-11 核实
  `modules/nf-core/discovar`、`bio/discovar` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装前缀为 **`/opt/biosoft/discovar`**、**`/opt/biosoft/discovardenovo`**
  （root 全局限定路径）；本 README 一律改写为**用户前缀** `~/software/*`（免 root）。
* 原始发布包名：`discovar.tar.gz`、`discovardenovo.tar.gz`（Broad 官网 `down/` 目录，
  现已不可取）。
* `NhoodInfo` 结果解读（摘自文档 04.md）：`2850<2851>[1.04x](+10:30,434,920-51,125)C=3346(16K)`
  —— edge id；反向互补 id；双倍体出现率（0.5 单倍型，>2x 重复）；链方向；参考区间；
  覆盖度；edge 长度。

## 容器与 Conda 链接

* **官网（页面损坏）**：<https://software.broadinstitute.org/software/discovar/blog/>
* **社区仓库**：https://github.com/SiYangming/discovar
* **conda**：bioconda `discovar=52488` → <https://anaconda.org/bioconda/discovar>；
  `discovardenovo=52488` → <https://anaconda.org/bioconda/discovardenovo>
* **Docker / Singularity**：`quay.io/biocontainers/discovar:52488--0` 与
  `quay.io/biocontainers/discovardenovo:52488--0`（历史镜像）/ depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 404 核实）
