# repeatmodeler 软件模块（de novo 重复序列家族建模）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# repeatmodeler / native — 从头重复序列家族建模驱动

RepeatModeler（上游 [Dfam-consortium/RepeatModeler](https://github.com/Dfam-consortium/RepeatModeler)，官网 <https://www.repeatmasker.org/RepeatModeler/>）是基因组**从头（de novo）重复序列家族识别与建模**的行业标准工具：对目标物种基因组自动运行 RECON / RepeatScout / LTR_retriever 等多条挖掘管线并经 RMBlast 聚类，输出该物种特异的**共有重复序列库**（`RM_*.families` / `consensi.fa(.classified)`），直接供 **RepeatMasker -lib** 做全基因组屏蔽。bioconda 的 `repeatmodeler` 包会把 RECON / RepeatScout / RMBlast / TRF / RepeatMasker / cd-hit / LTR_retriever 等依赖一并装入，**本模块不单独管理这些依赖**。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/repeatmodeler / bioconda repeatmodeler）提供；两个子命令分别包装官方两个可执行：

## 能力

| 子命令      | 包装命令                                                     | 作用                                        | 线程               |
| -------- | -------------------------------------------------------- | ----------------------------------------- | ---------------- |
| `build_db` | `BuildDatabase -name <name> [-engine ncbi] <genome.fasta>` | 基因组 FASTA → BLAST 库（`<name>-index/` + `.translation`） | 接受 `--threads`，原生无并行参数不注入 |
| `model`    | `RepeatModeler -database <name> [-engine ncbi] [-pa N] [--LTRStruct]` | 从头跑重复家族识别/聚类，产出共有序列供 RepeatMasker `-lib` | ✅ 默认 8（注入 `-pa`） |

## 用法

```bash
# CLI 直跑（教学典型链路；在包含数据库的工作目录下执行）
python main.py build_db ../genome.fasta -name species --engine ncbi --threads 4
python main.py model -database species --engine ncbi --threads 8
python main.py model -database species --engine ncbi --threads 8 --LTRStruct   # 追加 LTR 结构发现

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。`build_db` 的 `--threads` 仅作为运行期选项被接受（BuildDatabase 原生无并行参数）。

> ⚠️ **工作目录约定**：`BuildDatabase -name species` 与 `RepeatModeler -database species` 都以**当前工作目录**为数据库位置与输出目录（`RM_*/`），请先 `cd` 到目标项目目录再调用（容器运行同理，见「环境安装 §2」）。

## 实战示例：物种特异性从头重复库（BuildDatabase → RepeatModeler → RepeatMasker）

RepeatModeler 用于**无参考重复库**的物种（非模式生物 / 新组装基因组）：先为基因组建库，再从头识别重复家族得到 `consensi.fa`，最后交给 RepeatMasker 屏蔽/注释。以下为原生 CLI 典型用法（教学典型命令即 `BuildDatabase -name species -engine ncbi` + `RepeatModeler -engine ncbi -pa 4 -database species`）；**等价能力由 `native/main.py` 的 `build_db` / `model` 子命令提供**（见上「用法」）。

### 1. 为基因组建立 RepeatModeler 数据库

```bash
mkdir -p repeatmodeler_db && cd repeatmodeler_db

# genome.fasta 为去接头/去载体后的基因组（教学小基因组即可；真核大基因组耗时见文末注意）
BuildDatabase -name species -engine ncbi ../genome.fasta
# 产物：species-index/（BLAST 库）+ species.translation（六框翻译库）
```

### 2. 从头建模（识别重复家族并聚类）

```bash
# -pa 并行线程数（默认引擎 ncbi）；输出 RM_<日期>_<时间>/ 目录
RepeatModeler -engine ncbi -pa 4 -database species
# 若想追加 LTR 结构发现（更慢）：RepeatModeler -engine ncbi -pa 4 -database species -LTRStruct
```

核心产物在 `RM_*/` 目录内：

```bash
ls RM_*/ | grep -E 'consensi|families'
# consensi.fa  / consensi.fa.classified   <- 未分类 / 分类后的共有重复序列（供 RepeatMasker）
# RM_*.families                            <- RepeatMasker families 格式库
```

### 3. 桥接 RepeatMasker：用建好的库屏蔽/注释基因组

```bash
# -lib 指向 RepeatModeler 输出的共有序列；-dir 指定输出目录；产物 *.masked / *.out / *.gff
RepeatMasker -pa 8 -lib RM_*/consensi.fa -dir masked ../genome.fasta
```

> 后续可用 `consensi.fa.classified`（含重复家族注释）提升 RepeatMasker 输出注释的可读性；教学演示若嫌慢，可对单条染色体运行。

### 4. 参数说明

| 参数               | 说明                                             |
| ---------------- | ---------------------------------------------- |
| `-name <name>`    | BuildDatabase 输出数据库名（`RepeatModeler -database` 指向它） |
| `-database <name>` | RepeatModeler 要建模的数据库（必须已用 BuildDatabase 建好）      |
| `-engine <engine>` | 搜索引擎，默认 `ncbi`（bioconda 包内为 RMBlast 兼容的 NCBI 引擎）    |
| `-pa <int>`       | RepeatModeler 并行任务/线程数（本驱动由 `--threads` 注入，默认 8）    |
| `-LTRStruct`      | 追加 LTR 结构发现（LTR_retriever；更慢，真核大基因组按需）           |
| `-dir <dir>`      | （示例 3 为 RepeatMasker 参数）输出目录                   |

> 💡 **计算资源注意**：RepeatModeler 真核全基因组建库通常需**数十 GB 内存/磁盘与数十小时级计算**（>1Gb 基因组官方建议 16 核 + 96h 量级），教学环境请使用小基因组/单条染色体演示，或直接复用公开物种的 RepeatMasker 库。

## 依赖模块（安装见对应模块文档）

RepeatModeler 依赖较多（bioconda 包会一并装入，无需手工逐个安装）；如需单独安装或核查版本，见对应模块文档：

| 依赖                     | 作用                | 安装文档                                              |
| ---------------------- | ----------------- | ------------------------------------------------- |
| RepeatMasker           | 重复屏蔽与分类（含 RMBlast/TRF） | [modules/repeatmasker](../repeatmasker/README.md) |
| RMBlast                | BLAST 引擎          | [modules/rmblast](../rmblast/README.md)           |
| TRF                    | 串联重复检测            | [modules/trf](../trf/README.md)                   |
| RECON                  | 重复家族从头识别          | [modules/recon](../recon/README.md)               |
| RepeatScout            | 从头重复发现            | [modules/repeatscout](../repeatscout/README.md)   |
| GenomeTools (LtrHarvest) | LTR 结构预测（`-LTRStruct`） | [modules/genometools](../genometools/README.md)   |
| LTR_retriever          | LTR 反转录转座子注释       | [modules/ltr_retriever](../ltr_retriever/README.md) |
| MAFFT                  | 多序列比对             | [modules/mafft](../mafft/README.md)               |
| CD-HIT                 | 序列去冗余聚类           | [modules/cd-hit](../cd-hit/README.md)             |
| NINJA                  | 重复聚类              | [modules/ninja](../ninja/README.md)               |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 RepeatModeler / BuildDatabase 及全部依赖）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n repeatmodeler-native -c conda-forge -c bioconda repeatmodeler=2.0.9
conda activate repeatmodeler-native
RepeatModeler -help      # 断言（同包装入 BuildDatabase/RECON/RepeatScout/RMBlast/TRF 等）
```

> Homebrew：homebrew-core 与 brewsci/bio 均无 `repeatmodeler` 公式（2026-09-09 核实 formulae.brew.sh 与 `Formula/repeatmodeler.rb` 均 404）→ 无公式，不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/repeatmodeler:2.0.9--pl5321hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/repeatmodeler:2.0.9--pl5321hdfd78af_0 \
    BuildDatabase -name species -engine ncbi /data/genome.fasta
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/repeatmodeler:2.0.9--pl5321hdfd78af_0 \
    RepeatModeler -engine ncbi -pa 4 -database species
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull repeatmodeler.sif docker://depot.galaxyproject.org/singularity/repeatmodeler:2.0.9--pl5321hdfd78af_0
apptainer run -B $PWD:/data -H /data repeatmodeler.sif BuildDatabase \
    -name species -engine ncbi /data/genome.fasta
apptainer run -B $PWD:/data -H /data repeatmodeler.sif RepeatModeler \
    -engine ncbi -pa 4 -database species
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

RepeatModeler 为 **Perl 源码程序（自带 `configure`）**，官方**无预编译二进制资产**（GitHub release 2.0.9 仅源码归档），且需自行安装 RMBlast / RepeatMasker / RECON / TRF 等依赖——因此一般**优先 conda / 官方容器路线**；确需源码安装时：

**官网下载页**：<https://www.repeatmasker.org/RepeatModeler/>

**GitHub release**：<https://github.com/Dfam-consortium/RepeatModeler/releases>（tag `2.0.9`，与 `software_versions` 对齐）

```bash
# 源码 tag 归档（解压到用户目录后 configure，无需 root）
wget https://github.com/Dfam-consortium/RepeatModeler/archive/refs/tags/2.0.9.tar.gz -P ~/software/
tar zxf ~/software/2.0.9.tar.gz -C ~/software/     # -> ~/software/RepeatModeler-2.0.9/
cd ~/software/RepeatModeler-2.0.9/
perl ./configure && make                                 # 依赖：RMBlast/RepeatMasker/RECON/TRF 需先就绪
echo 'export PATH=$PATH:~/software/RepeatModeler-2.0.9/bin' >> ~/.bashrc && source ~/.bashrc
RepeatModeler -help                                 # 断言
```

## 测试

```bash
bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约必跑；
# PATH 含 BuildDatabase/RepeatModeler 时追加 build_db→model 最小真跑链路（RepeatModeler 在合成
# 小基因组上失败仅告警不阻断，因完整建库需数十 GB 级计算，见脚本头注）。
```

## 版本

* repeatmodeler **2.0.9**（bioconda::repeatmodeler=2.0.9，noarch build `pl5321hdfd78af_0`，2026-07-25 发布）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/repeatmodeler / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方子模块当前 pin repeatmodeler=**2.0.5**（低于 native 的 2.0.9，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/repeatmodeler/` **存在**（2026-09 在线核实，与「官方无」预判不符，按在线目录登记；以官方在线目录为准）：

| 子模块           | environment.yml 关键 pin             | 作用（据 nf-core meta）                      |
| ------------- | --------------------------------- | -------------------------------------- |
| `builddatabase` | bioconda::repeatmodeler=2.0.5       | BuildDatabase：genome FASTA → RepeatModeler 数据库 |
| `repeatmodeler`  | bioconda::repeatmodeler=2.0.5       | 建库建模，输出 `*.fa`（consensi 共有序列）/ `*.stk` / `*.log` |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core repeatmodeler builddatabase repeatmodeler`（安装到项目自身 `modules/nf-core/`，
> 不要直接引用本仓库示例），随后：
>
> ```nextflow
> include { REPEATMODELER_BUILDDATABASE } from '../modules/nf-core/repeatmodeler/builddatabase/main'
> include { REPEATMODELER_REPEATMODELER } from '../modules/nf-core/repeatmodeler/repeatmodeler/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/repeatmodeler | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/repeatmodeler`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/repeatmodeler` 返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `repeatmodeler_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | repeatmodeler 版本 | 来源                                                                                                  |
| ------------------ | --------------- | --------------------------------------------------------------------------------------------------- |
| native（官方容器/conda）  | **2.0.9**        | official biocontainer：quay.io/biocontainers/repeatmodeler:2.0.9--pl5321hdfd78af\_0 / bioconda repeatmodeler=2.0.9 |
| nf-core master     | 2.0.5            | bioconda::repeatmodeler=2.0.5（modules/nf-core/repeatmodeler/{builddatabase,repeatmodeler}/environment.yml）   |
| snakemake-wrappers | 官方无 wrapper       | bio/repeatmodeler 404（2026-09）                                                                      |

> nf-core 子模块 pin 2.0.5 低于 bioconda 现行 2.0.9：两者可共存（不同环境），用 Nextflow 时以 nf-core 子模块 pin 为准、待 nf-core bump 后同步刷新；用 native（Agent/CLI）时以 2.0.9 为准。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# repeatmodeler native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 repeatmodeler-native.yml 后 mamba env create -f repeatmodeler-native.yml；
# 在线推荐上方 mamba create 直装命令。repeatmodeler=2.0.9 会把 RECON/RepeatScout/RMBlast/TRF/
# RepeatMasker/cd-hit/LTR_retriever 等依赖一并装入（本模块不单独管理）。
name: repeatmodeler-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - repeatmodeler=2.0.9
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/repeatmodeler>

* **Docker**：`docker pull quay.io/biocontainers/repeatmodeler:2.0.9--pl5321hdfd78af_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/repeatmodeler%3A2.0.9--pl5321hdfd78af_0>

* 安装方式（本地）：`mamba create -n repeatmodeler-native -c conda-forge -c bioconda repeatmodeler=2.0.9`

* 上游 GitHub：<https://github.com/Dfam-consortium/RepeatModeler>（release tag 2.0.9，源码归档）· 官网：<https://www.repeatmasker.org/RepeatModeler/>
