# repeatmasker 软件模块（基因组重复序列屏蔽与注释）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# repeatmasker / native — 屏蔽已知重复序列驱动

RepeatMasker（上游 [Dfam-consortium/RepeatMasker](https://github.com/Dfam-consortium/RepeatMasker)，官网 <https://www.repeatmasker.org/>）是**屏蔽并注释基因组中已知重复序列**的行业标准工具：基于 **RepBase / Dfam** 重复库、以 **RMBlast（rmblastn）** 为默认搜索引擎，输出被 **N 屏蔽**的序列（`*.masked`）与逐位点重复注释（`*.out` / `*.tbl`，`-gff` 可另出 GFF3）。除物种库外还支持 `-lib` 传入 **RepeatModeler**（本仓库 `modules/repeatmodeler`）等工具自建的自定义重复库做物种特异屏蔽/注释——两模块构成「建库 → 屏蔽」教学链路。bioconda 的 `repeatmasker` 包会把 rmblast / hmmer / trf / famdb 等运行依赖一并装入，**本模块不单独管理这些依赖**。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/repeatmasker / bioconda repeatmasker）提供；两个子命令分别包装官方两个入口：

## 能力

| 子命令                 | 包装命令                                                                         | 作用                                             | 线程               |
| ------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------- | ---------------- |
| `mask`                | `RepeatMasker -pa N -e ncbi [-species X | -lib lib.fa] [-dir out] [-gff] genome.fasta` | 屏蔽/注释已知重复：产物 `*.masked` / `*.out`（+ `*.out.gff`） | ✅ 默认 4（注入 `-pa`） |
| `query_species_tree` | `RepeatMasker/util/queryRepeatDatabase.pl -tree`                                | 列出重复库内可用 `-species` 物种树（stdout），供挑选物种名          | 接受 `--threads`，不注入  |

## 用法

```bash
# CLI 直跑（教学典型链路；先在项目目录准备好 genome.fasta 与重复库）
python main.py query_species_tree                              # 查库内可用 -species 物种名（输出物种树）
python main.py mask genome.fasta -species fungi -dir rm_fungi --threads 4   # 走 RepBase/Dfam 物种库
python main.py mask genome.fasta -lib consensi.fa -dir rm_ab   # 走 RepeatModeler 自建库（-gff 出 GFF3）
python main.py mask genome.fasta -species fungi -dir rm_fungi -gff --extra-args "-xsmall -cutoff 3.7"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。`query_species_tree` 的 `--threads` 仅作为运行期选项被接受（脚本为单线程查询，不注入命令行）。

> ⚠️ **重复库说明**：RepeatMasker 4.2.x 发行**不自带重复库**——`-species` 需要先安装 Dfam（FamDB 组件）或 RepBase RepeatMasker Edition；`-lib` 自定义库（如 RepeatModeler 的 `consensi.fa`）则**无需任何数据库配置**，教学演示最稳。真核全基因组屏蔽耗时较长（>1Gb 基因组建议 16 核 + 数小时级），教学请用合成小基因组/单条染色体。

## 实战示例：基因组重复序列屏蔽与注释（教学典型链路）

RepeatMasker 教学典型命令为 `RepeatMasker -pa 4 -e ncbi -species fungi -dir repeatMasker/ -gff genome.fasta` 与 `RepeatMasker -pa 4 -e ncbi -lib consensi.fa -dir ./ -gff genome.fasta`（RepeatModeler 自建库注释）；以下为原生 CLI 的典型批量用法，**等价能力由 `native/main.py` 的 `mask` / `query_species_tree` 子命令提供**（见上「用法」）。

### 1. 查询可用的 -species 物种名

```bash
# 列出重复库（RepBase/Dfam 可查部分）中的物种分类树，挑出库内有效的 -species 名
RepeatMasker/util/queryRepeatDatabase.pl -tree > species.txt
head species.txt
# 确认后即可在步骤 2 用 -species <名字>（如 -species fungi / -species "ciona savignyi"）
```

### 2. 逐样本屏蔽（-species 物种库；每样本独立 -dir 输出目录）

```bash
mkdir -p repeatMasker_fungi
# 单样本（教学典型命令）：-pa 并行、-e ncbi（RMBlast 引擎）、-dir 输出目录、-gff 追加 GFF3
RepeatMasker -pa 4 -e ncbi -species fungi -dir repeatMasker_fungi/ -gff genome.fasta

# 多样本批量（每样本一个分目录，避免产物互相覆盖；产物名取输入文件名）
for fa in genomes/*.fasta; do
    sample=$(basename "$fa" .fasta)
    mkdir -p repeatMasker_${sample}
    RepeatMasker -pa 4 -e ncbi -species fungi -dir repeatMasker_${sample}/ -gff "$fa"
done
# 每个分目录内产物：<name>.masked（N 屏蔽序列）、<name>.out（表格注释）、<name>.tbl（按类汇总）、<name>.out.gff
```

### 3. 用 RepeatModeler 自建库注释（-lib，无物种库也可跑）

RepeatModeler 产出的共有序列（`consensi.fa` / `RM_*.families`，见本仓库 `modules/repeatmodeler`）可直接当自定义库传入：

```bash
mkdir -p repeatMasker_custom
RepeatMasker -pa 4 -e ncbi -lib RM_*/consensi.fa -dir repeatMasker_custom/ -gff genome.fasta
# 产物同上；无需安装 Dfam/RepBase（RepeatMasker >= 4.2 时代替 -species 的教学首选路线）
```

> 💡 若当前 RepeatMasker 为 4.2.x（FamDB/Dfam 路线），经典 `util/queryRepeatDatabase.pl` 不再随发行提供，查可用物种请改用 `famdb.py`（bioconda 随装）查询 Dfam 分类。

### 4. 参数说明

| 参数                   | 说明                                                       |
| -------------------- | -------------------------------------------------------- |
| `-pa <int>`          | 并行任务数（本驱动由 `--threads` 注入，默认 4）                        |
| `-e <engine>`        | 搜索引擎，默认 `ncbi`（ncbi 与 rmblast 均为 RMBlast/rmblastn 引擎别名；亦支持 crossmatch/hmmer 等） |
| `-species <name>`    | 库内物种/分类群名（先用 `query_species_tree` 查可用名）                 |
| `-lib <file>`        | 自定义重复库 FASTA（RepeatModeler `consensi.fa` 等；免数据库配置）         |
| `-dir <dir>`         | 输出目录（默认当前目录；多样本务必分目录）                                 |
| `-gff`               | 追加 GFF3 注释（`<name>.out.gff`）                           |
| `-xsmall` 等          | 其它常用项（`-cutoff` / `-no_is` / `-xm` …）经 `--extra-args` 透传    |

## 依赖模块（安装见对应模块文档）

RepeatMasker 运行需外部搜索/串联重复引擎（以及 `configure` 会询问的 HMMER 目录）；引擎与重复库的安装见对应模块文档：

| 依赖          | 作用                                              | 安装文档                                        |
| ----------- | ----------------------------------------------- | ------------------------------------------- |
| RMBlast     | 默认 BLAST 引擎（`-e ncbi` / rmblast）                 | [modules/rmblast](../rmblast/README.md)     |
| TRF         | 串联重复检测（RepeatMasker 集成调用）                        | [modules/trf](../trf/README.md)             |
| HMMER 3.x   | `configure` 的 `hmmer_dir`（`-e hmmer` 引擎 / HMM 库屏蔽时需要） | [modules/hmmer](../hmmer/README.md)（3.x 现行版章节，`native/` 实现） |

> 重复库（RepBase / Dfam）属**数据资产非软件模块**：RepBase RepeatMasker Edition 官方 GIRInst 直链**现已无需账号**（实测 HTTP 200，约 53.5 MiB；<https://www.girinst.org/server/RepBase/protected/repeatmaskerlibraries/RepBaseRepeatMaskerEdition-20181026.tar.gz>），**备用镜像同样无需账号**：SourceForge old-software-collection（<https://sourceforge.net/projects/old-software-collection/postdownload>）；Dfam 见 <https://dfam.org/>；RepeatMasker ≥ 4.2 走 FamDB（`famdb.py` 查询）。安装步骤见下「环境安装」§5。
>
> HMMER 的 3.x 与 2.x 属**同一软件**，现已合并为一个模块 `modules/hmmer`（3.x = `native/` 默认实现；2.x = `native2/` 遗留版实现，供 RNAmmer/旧版 antiSMASH 等使用）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 RepeatMasker 及 rmblast/hmmer/trf/famdb 等全部运行依赖）；main.py 驱动在宿主机跑。注意 4.2.x 发行不自带重复库：`-species` 需另配 Dfam/RepBase，`-lib` 自定义库免配置。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n repeatmasker-native -c conda-forge -c bioconda repeatmasker=4.2.4
conda activate repeatmasker-native
RepeatMasker           # 断言：无参数运行打印 "RepeatMasker - Mask repetitive DNA" 用法/版本
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio repeatmasker 4.1.6，与 meta 登记 4.2.4 略有差异（版本以 formula 为准）
brew tap brewsci/bio     # 首次使用需要
brew install repeatmasker
RepeatMasker             # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/repeatmasker:4.2.4--pl5321hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
# -lib 自定义库示例（免数据库配置；镜像内含 rmblast 引擎，configure 默认引擎即 rmblast）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/repeatmasker:4.2.4--pl5321hdfd78af_0 \
    RepeatMasker -pa 4 -e ncbi -lib /data/consensi.fa -dir /data/rm_custom /data/genome.fasta
# -species 走 Dfam 时需自行挂载 FamDB 组件数据（Dfam h5 目录），见 repeatmasker.org 说明
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull repeatmasker.sif docker://depot.galaxyproject.org/singularity/repeatmasker:4.2.4--pl5321hdfd78af_0
apptainer run -B $PWD:/data -H /data repeatmasker.sif RepeatMasker \
    -pa 4 -e ncbi -lib /data/consensi.fa -dir /data/rm_custom /data/genome.fasta
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

RepeatMasker 为 **Perl 源码程序（自带 `configure`）**，官方**无预编译二进制资产**，且需先自行装好搜索引擎（rmblast）与 TRF、hmmer、FamDB/Dfam 或 RepBase 库——因此一般**优先 conda / 官方容器路线**；确需源码安装时：

**官网下载页**：<https://www.repeatmasker.org/RepeatMasker/>

**GitHub**：<https://github.com/Dfam-consortium/RepeatMasker>（release 为源码 tag 归档，与 `software_versions` 对齐 4.2.4）

```bash
wget https://www.repeatmasker.org/RepeatMasker/RepeatMasker-4.2.4.tar.gz -P ~/software/
tar zxf ~/software/RepeatMasker-4.2.4.tar.gz -C ~/software/     # -> ~/software/RepeatMasker/
cd ~/software/RepeatMasker
perl ./configure    # 按提示指定 rmblast_dir / trf_prgm / hmmer_dir / famdb_dir（默认引擎选 rmblast）
echo 'export PATH=$PATH:~/software/RepeatMasker' >> ~/.bashrc && source ~/.bashrc
RepeatMasker        # 断言：打印版本与用法
# 库：4.2.x 不自带重复库——-species 需装 FamDB 并下载 Dfam 组件（或装 RepBase RepeatMasker Edition）；
#     只想先跑通流程则用 -lib 自定义库（免数据库配置）；RepBase 下载见 §5
```

### 5. 重复库安装（RepBase RepeatMasker Edition）

RepeatMasker 4.2.x 发行**不自带重复库**；若走 RepBase 路线（`-species` 或自定义库之外的已知重复注释），需下载 **RepBase RepeatMasker Edition**（自带 `Libraries/` 结构）。两条来源（**均已实测无需账号**，2026-09）：

```bash
# 方式 A（官方 GIRInst，直接下载；实测 HTTP 200、Content-Length 56076961 ≈ 53.5 MiB、gzip）
wget https://www.girinst.org/server/RepBase/protected/repeatmaskerlibraries/RepBaseRepeatMaskerEdition-20181026.tar.gz \
    -P ~/software/

# 方式 B（备用镜像：SourceForge old-software-collection，无需账号，同一文件）
#   项目页：https://sourceforge.net/projects/old-software-collection/postdownload
#   直链：https://sourceforge.net/projects/old-software-collection/files/RepBaseRepeatMaskerEdition-20181026.tar.gz/download
```

> 若日后官方站点恢复访问控制，可退回带凭据的写法：`wget --http-user=username --http-password=password <方式 A 的 URL> -P ~/software/`。

```bash
# 解压到 RepeatMasker 安装目录（自带 Libraries/ 结构；勿用 /opt/biosoft 等教学硬编码路径）
cd ~/software/RepeatMasker                                  # conda 安装对应 $CONDA_PREFIX/share/RepeatMasker
tar zxf ~/software/RepBaseRepeatMaskerEdition-20181026.tar.gz
perl ./configure                                            # 按提示确认库路径（RepBase Libraries / famdb_dir）
RepeatMasker -species human -dir rm_out genome.fasta        # 冒烟：走 RepBase/Dfam 库的物种注释
```

> Dfam 路线（RepeatMasker ≥ 4.2 默认 FamDB）见 <https://dfam.org/> 与 RepeatMasker 官方 `famdb.py` 说明；RepBase 版为 20181026（GIRInst 已停更该版本），如需更新版本以 GIRInst 页面为准。

## 测试

```bash
bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约必跑；
# PATH 含 RepeatMasker 时追加轻量自检（版本探测 + query_species_tree 可用性探测，失败仅提示不阻断）。
# mask 真实回归需要 Dfam/RepBase 重复库，普通机器不全跑（见脚本头注）。
```

## 版本

* repeatmasker **4.2.4**（bioconda::repeatmasker=4.2.4，noarch build `pl5321hdfd78af_0`；2026-06 起发布）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/repeatmasker / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方子模块当前 pin repeatmasker=**4.1.5**（低于 native 的 4.2.4，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/repeatmasker/` **存在**（2026-09 在线核实，按在线目录登记；以官方在线目录为准）：

| 子模块           | environment.yml 关键 pin  | 作用（据 nf-core meta）                        |
| ------------- | ---------------------- | ---------------------------------------- |
| `repeatmasker`  | bioconda::repeatmasker=4.1.5 | RepeatMasker 屏蔽：输入 fasta（+可选 lib）→ `*.masked` / `*.out` / `*.tbl`（可选 `*.gff`） |
| `rmouttogff3`  | bioconda::repeatmasker=4.1.5 | `.out` → GFF3 转换（输出 `*.gff`）               |

> ⚠️ 执行请用 `nf modules install nf-core repeatmasker repeatmasker rmouttogff3`（安装到项目自身 `modules/nf-core/`，不要直接引用本仓库示例），随后：
>
> ```nextflow
> include { REPEATMASKER_REPEATMASKER } from '../modules/nf-core/repeatmasker/repeatmasker/main'
> include { REPEATMASKER_RMOUTTOGFF3 } from '../modules/nf-core/repeatmasker/rmouttogff3/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/repeatmasker | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/repeatmasker`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/repeatmasker` 返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `repeatmasker_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | repeatmasker 版本 | 来源                                                                                               |
| ------------------ | --------------- | ------------------------------------------------------------------------------------------------ |
| native（官方容器/conda）  | **4.2.4**        | official biocontainer：quay.io/biocontainers/repeatmasker:4.2.4--pl5321hdfd78af\_0 / bioconda repeatmasker=4.2.4 |
| nf-core master     | 4.1.5            | bioconda::repeatmasker=4.1.5（modules/nf-core/repeatmasker/{repeatmasker,rmouttogff3}/environment.yml）     |
| snakemake-wrappers | 官方无 wrapper       | bio/repeatmasker 404（2026-09）                                                                   |

> nf-core 子模块 pin 4.1.5 低于 bioconda 现行 4.2.4：两者可共存（不同环境），用 Nextflow 时以 nf-core 子模块 pin 为准、待 nf-core bump 后同步刷新；用 native（Agent/CLI）时以 4.2.4 为准。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# repeatmasker native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 repeatmasker-native.yml 后 mamba env create -f repeatmasker-native.yml；
# 在线推荐上方 mamba create 直装命令。repeatmasker=4.2.4 会把 rmblast/hmmer/trf/famdb 等依赖一并装入。
name: repeatmasker-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - repeatmasker=4.2.4
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/repeatmasker>

* **Docker**：`docker pull quay.io/biocontainers/repeatmasker:4.2.4--pl5321hdfd78af_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/repeatmasker%3A4.2.4--pl5321hdfd78af_0>

* 安装方式（本地）：`mamba create -n repeatmasker-native -c conda-forge -c bioconda repeatmasker=4.2.4`

* 上游 GitHub：<https://github.com/Dfam-consortium/RepeatMasker>（release 源码归档）· 官网：<https://www.repeatmasker.org/> / 软件页 <https://www.repeatmasker.org/RepeatMasker/>
