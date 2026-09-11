# ninja 软件模块（NINJA · 重复序列聚类 / 邻居合并）

> 汇总说明：NINJA（**N**early **I**nfinite **N**eighbor **J**oining **A**pplication，TravisWheelerLab）
> 是面向大规模序列的**邻居合并（neighbor-joining）与单链接聚类**工具，可只考察少量 taxon 对
> 即完成 NJ 搜索。其 **cluster_only** 版主命令为 **`Ninja`**，按成对进化距离做**单链接聚类**
> （`--out_type c`，默认）或输出**距离矩阵**（`--out_type d`）。NINJA 是 **RepeatModeler** 的
> 重复序列聚类依赖（**多数场景由 `modules/repeatmodeler` 调用**）。本模块仅 native 一路
> （`source_type: custom`）；官方 nf-core / snakemake-wrappers 均无（仅说明层，见文末）。
> 安装方式见「环境安装（官方镜像优先，不维护本地配方）」，容器/conda 信息记录于文末。
>
> ⚠️ **同名异义提醒（正向消歧）**：conda-forge / conda 的 **`ninja`** 是 **构建系统 ninja
> （build system）**，与本模块的 **NINJA（TravisWheelerLab，重复聚类）不是同一软件**；
> 本工具的官方 conda 包名为 **`ninja-nj`**（bioconda），安装时请勿与 conda-forge 的构建系统
> `ninja` 混淆。

***

## native 实现

# ninja / native — Ninja 驱动的序列聚类

本地自包含驱动（`source_type: custom`、`type: native`），`native/main.py` 的 `cluster` 子命令
包装宿主机/官方镜像内的 `Ninja` 命令，完成单链接聚类或距离矩阵输出：

```
比对 FASTA（--in_type a，默认）  ┐
                                ├─→ Ninja -i <in> -o <out> -T <threads>
Phylip 距离矩阵（--in_type d）   ┘
     → --out_type c（默认）单链接聚类：cluster_id<TAB>name 每序列一行（--cluster_cutoff 默认 0.03）
     → --out_type d 距离矩阵（Phylip 风格）
```

> `Ninja` 二进制由**官方容器/conda**（quay.io/biocontainers/ninja-nj / bioconda `ninja-nj`）或
> native/install.sh（conda / 源码编译双路线）提供。

## 能力

| 子命令      | 包装命令                                                                                              | 作用                                                     | 线程 |
| -------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | -- |
| `cluster` | `Ninja -i <in> -o <out> -T <n> [--in_type a\|d] [--out_type c\|d] [--corr_type n\|j\|k\|s\|m] [--cluster_cutoff <d>]` | 序列聚类（`--out_type c`，默认）或距离矩阵（`--out_type d`） | ✅（原生 `--threads`/`-T`） |

## 用法

```bash
# CLI 直跑（比对 FASTA → 单链接聚类；阈值 0.03）
python main.py cluster -i repeats.aln.fa -o clusters.tsv --cluster_cutoff 0.03 --threads 8

# 仅输出距离矩阵（Phylip 风格）
python main.py cluster -i repeats.aln.fa -o distances.phy --out_type d --threads 8

# 已有距离矩阵作为输入（--in_type d）→ 聚类
python main.py cluster -i distances.phy -o clusters.tsv --in_type d --cluster_cutoff 0.03

# 指定距离校正类型（n|j|k|s|m）
python main.py cluster -i repeats.aln.fa -o clusters.tsv --corr_type k --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖：`--threads` 注入 Ninja 原生
`--threads`（短选项 `-T`）；`--tmpdir` 注入 `TMPDIR` 环境变量（Ninja 中间/临时文件走该目录）。

> 也可跳过 main.py 直接调用 Ninja（原生 CLI，以 `Ninja -h` 为准）：
>
> ```bash
> Ninja --in repeats.aln.fa --out clusters.tsv --out_type c --cluster_cutoff 0.03 --threads 8
> Ninja -h          # 帮助；Ninja -v 打印版本（Version 1.00-cluster_only）
> ```

## 实战示例：重复序列聚类（RepeatModeler 依赖场景）

NINJA 的典型用法是作为 **RepeatModeler 的重复聚类后端**：把 RepeatModeler 产出的 consensi /
比对结果按进化距离做单链接聚类，合并同一重复家族。**等价能力由 `native/main.py` 的 `cluster`
子命令提供**（先 CLI 后 main.py，见上「用法」）。

### 1. 比对 FASTA → 单链接聚类

```bash
mkdir -p ninja_out
# 比对 FASTA（同一重复家族内序列已对齐）；输出 cluster_id<TAB>name
Ninja -i consensi.aln.fa -o ninja_out/clusters.tsv --out_type c --cluster_cutoff 0.03 --threads 8
head ninja_out/clusters.tsv
# 0<TAB>consensus_1
# 0<TAB>consensus_7
# 1<TAB>consensus_2
```

### 2. 仅需距离矩阵

```bash
Ninja -i consensi.aln.fa -o ninja_out/distances.phy --out_type d --threads 8
head ninja_out/distances.phy          # 首行为序列条数，随后每行 name d1 d2 ...
```

### 3. 复用已有距离矩阵

```bash
Ninja -i ninja_out/distances.phy -o ninja_out/clusters.tsv --in_type d --cluster_cutoff 0.03
```

### 4. 批量循环（逐簇文件）

```bash
for aln in aln/*.aln.fa; do
    sample="$(basename "$aln" .aln.fa)"
    Ninja -i "$aln" -o "ninja_out/${sample}.clusters.tsv" \
        --out_type c --cluster_cutoff 0.03 --threads 8 &
done
wait
```

### 5. 参数说明

| 参数                 | 说明                                                              |
| ------------------ | --------------------------------------------------------------- |
| `-i` / `--in`      | 输入文件（默认比对 FASTA；`--in_type d` 时为 Phylip 距离矩阵）                    |
| `-o` / `--out`     | 输出文件（`--out_type c` 聚类表；`--out_type d` 距离矩阵）                     |
| `--in_type`        | 输入类型：`a`（比对 FASTA，默认）/ `d`（距离矩阵）                                |
| `--out_type`       | 输出类型：`c`（单链接聚类，默认）/ `d`（距离矩阵）                                   |
| `--corr_type`      | 距离校正类型（可选）：`n` / `j` / `k` / `s` / `m`（缺省由 Ninja 依输入自动选择）    |
| `--cluster_cutoff` | 单链接聚类距离阈值（默认 `0.03`；仅 `--out_type c` 时生效）                        |
| `--threads` / `-T` | 线程数（本驱动自动注入，默认 4）                                              |
| `--tmpdir`         | 临时目录协议位（注入 `TMPDIR`）                                            |

> 桥接句：以上 CLI 用法等价于 `python main.py cluster -i <in> -o <out> [--in_type ...] [--out_type ...] [--cluster_cutoff ...] --threads <n>`。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（**bioconda → quay.io/biocontainers → depot.galaxyproject.org**）**均已维护**该软件
（conda/容器包名 **`ninja-nj`**，2026-09 在线核实：bioconda `ninja-nj=1.00`、quay.io/biocontainers/ninja-nj、
depot.galaxyproject.org/singularity/ninja-nj:1.00--h9948957\_1 均存在），因此直接拉取官方镜像/装 conda
包运行工具二进制，**本地不维护 Dockerfile / Apptainer.def**；`main.py` 驱动在宿主机跑。

> 💡 一键安装：`bash native/install.sh`（有 conda/mamba 时建 bioconda 环境 `ninja` 装 `ninja-nj=1.00`；
> 无 conda 时自动下载 cluster_only C++ 源码归档编译 `Ninja` 到 `~/software/NINJA-1.00` 并写 PATH。
> 用法：`bash native/install.sh --help`）。
>
> ⚠️ **同名异义**：官方包名是 **`ninja-nj`**；`conda install ninja` 装的是**构建系统 ninja**，与本软件无关。

### 1. Conda / brew（包管理器安装）

```bash
# 官方 bioconda 包名为 ninja-nj（可执行文件即 Ninja）
mamba create -n ninja -c conda-forge -c bioconda ninja-nj=1.00
conda activate ninja
Ninja -v                 # 断言：Version 1.00-cluster_only
```

```bash
# Homebrew：无本软件公式（brew core 的 ninja 是构建系统 ninja，非本软件；
# brewsci/bio tap 亦无 ninja / ninja-nj 公式，2026-09 核实 404）→ 不登记 brew 块
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ninja-nj:1.00--h9948957_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ninja-nj:1.00--h9948957_1 \
    Ninja -i /data/repeats.aln.fa -o /data/clusters.tsv --out_type c --cluster_cutoff 0.03 --threads 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换，tag 与 quay 互通）：

```bash
apptainer pull ninja.sif docker://depot.galaxyproject.org/singularity/ninja-nj:1.00--h9948957_1
apptainer run -B $PWD:/data -H /data ninja.sif \
    Ninja -i /data/repeats.aln.fa -o /data/clusters.tsv --out_type c --cluster_cutoff 0.03 --threads 8
```

### 4. 源码编译安装（cluster_only C++ 源码归档，无 conda / docker 依赖）

官方**无预编译二进制资产**（upstream 仅发布源码；bioconda 提供的是自动构建的 conda 包/镜像）。
如需无 conda 的源码路线，可编译 cluster_only C++ 源码归档：

```bash
# 源码归档（注意：C++ cluster_only 源码仓库为 TravisWheelerLab/ninja-old）：
#   https://github.com/TravisWheelerLab/ninja-old/archive/1.00-cluster_only.tar.gz
bash native/install.sh --method source                # 自动下载 + 编译 + 安装到 ~/software/NINJA-1.00
# 或手工：
mkdir -p ~/software && cd ~/software
curl -fsSL -O https://github.com/TravisWheelerLab/ninja-old/archive/1.00-cluster_only.tar.gz
tar zxf 1.00-cluster_only.tar.gz && cd ninja-old-1.00-cluster_only/NINJA
make all CXX=clang++ CXXFLAGS="-std=gnu++14 -Wall -O3"     # x86_64 追加 -mssse3
install -m 0755 Ninja ~/software/NINJA-1.00/bin/           # 用户级前缀，无需 root
```

> ⚠️ **上游仓库改版说明**：`https://github.com/TravisWheelerLab/NINJA` 于 2026 年改版为 **Rust 实现**
> （crate `ninja-phylo`，二进制 `ninja`，CLI 为 `ninja --in ... --out ... --out_type c --cluster_cutoff ...`），
> 旧的 C++ `*-cluster_only` 标签/归档已从该仓库移除，C++ 源码归档改由 **`TravisWheelerLab/ninja-old`**
> 提供（标签 `0.95-cluster_only` … `1.00-cluster_only`）。本模块面向 **RepeatModeler 依赖的 C++ 版
> `Ninja`（bioconda `ninja-nj`）**；Rust 版为不同二进制/CLI，请勿混用。

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块

官方 nf-core **无** `modules/nf-core/ninja`（2026-09 在线核实 404）。Nextflow 场景以本模块
`native/` 或在流程中直接 `docker run quay.io/biocontainers/ninja-nj:1.00--h9948957_1 Ninja ...` 为兜底。

> 核实命令：`curl -s -o /dev/null -w '%{http_code}\n' https://raw.githubusercontent.com/nf-core/modules/master/modules/nf-core/ninja/main.nf` → 404

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/ninja`（2026-09 在线核实 404）。Snakemake 场景暂无官方 wrapper
可登记；需要时以 `ninja_native` 为兜底（在规则中调用 `Ninja` 或 `python native/main.py cluster ...`）。

> 核实命令：`curl -s -o /dev/null -w '%{http_code}\n' https://raw.githubusercontent.com/snakemake/snakemake-wrappers/master/bio/ninja/environment.yaml` → 404

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | ninja 版本            | 来源                                                                                                            |
| ------------------ | ------------------- | ------------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.00**（`1.00-cluster_only`） | official biocontainer：quay.io/biocontainers/ninja-nj:1.00--h9948957\_1 / bioconda `ninja-nj=1.00`；对应源码 1.00-cluster_only |
| nf-core            | 官方无模块               | modules/nf-core/ninja 404（2026-09）                                                                            |
| snakemake-wrappers | 官方无 wrapper         | bio/ninja 404（2026-09）                                                                                        |

## 容器与 Conda 链接

* **Bioconda（官方包名 `ninja-nj`）**：<https://anaconda.org/bioconda/ninja-nj>
* **Docker / quay.io/biocontainers**：`docker pull quay.io/biocontainers/ninja-nj:1.00--h9948957_1`
* **Singularity（depot 预构建 sif）**：<https://depot.galaxyproject.org/singularity/ninja-nj%3A1.00--h9948957_1>
* **上游（Rust 改版后主仓库）**：<https://github.com/TravisWheelerLab/NINJA>
* **C++ cluster_only 源码归档（本模块对应实现）**：<https://github.com/TravisWheelerLab/ninja-old>
* **RepeatModeler（依赖方）**：<https://www.repeatmasker.org/RepeatModeler/>（本模块多数场景由其调用，见 `modules/repeatmodeler`）
* **nf-core modules**：无 `modules/nf-core/ninja`（2026-09 核实 404）
* **snakemake-wrappers**：无 `bio/ninja`（2026-09 核实 404）
* **Homebrew**：无本软件公式（brew core 的 `ninja` 为构建系统 ninja，非本软件；brewsci/bio 亦无）
* 安装方式（本地）：`mamba create -n ninja -c conda-forge -c bioconda ninja-nj=1.00`，或 `bash native/install.sh`

## 版本

* NINJA **1.00**（版本串 `1.00-cluster_only`，C++ cluster_only；bioconda 包名 `ninja-nj`）
* 可执行文件：**`Ninja`**（注意大写；`Ninja -v` 输出 `Version 1.00-cluster_only`）
* 官方渠道（bioconda / quay.io/biocontainers / depot.galaxyproject.org）均有官方维护；
  nf-core / snakemake-wrappers 均无（2026-09 在线核实）
* 上游仓库 `TravisWheelerLab/NINJA` 已于 2026 年改版为 Rust 实现（`ninja-phylo`，二进制 `ninja`），
  C++ cluster_only 源码归档改由 `TravisWheelerLab/ninja-old` 提供

## 测试

```bash
bash test/run_test.sh   # 自省 + 参数校验契约必跑；
                        # PATH 含 Ninja 时追加最小链路（比对聚类 / 距离矩阵 / 矩阵输入聚类）
```
