# ltr_retriever 软件模块（LTR 反转录转座子识别与注释）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# ltr_retriever / native — LTR-RT 识别与注释驱动

LTR_retriever（上游 [oushujun/LTR_retriever](https://github.com/oushujun/LTR_retriever)）是 **LTR 反转录转座子（LTR-RT）的敏感识别与注释**工具：读取基因组 FASTA 与 **LTRharvest**（见 `modules/genometools`）产出的候选文件，经结构筛选、去冗余（CD-HIT，见 `modules/cd-hit`）、蛋白/DNA TE 污染剔除与 TEsorter 分类，输出**非冗余 LTR-RT 库**（`*.LTRlib.fa`，供 RepeatMasker `-lib` 注释基因组）、**全基因组注释**（`*.out.gff3`）与 **LTR Assembly Index**（`*.out.LAI`）。

它是 **RepeatModeler `-LTRStruct`**（见 `modules/repeatmodeler`）与 LTR 注释流程的核心组件。上游依赖（BLAST+/CD-HIT/HMMER/RepeatMasker/TEsorter 等）由 **bioconda `ltr_retriever` 包一并装入**，本模块不单独管理这些依赖；`-inharvest` 候选由 `gt ltrharvest` 产出（见 `modules/genometools`）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/ltr_retriever / bioconda ltr_retriever）提供：

## 能力

| 子命令  | 包装命令                                                              | 作用                                                                                     | 线程                     |
| ---- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------- |
| `run` | `LTR_retriever -genome <fasta> -inharvest <candidates> [-threads N]` | 读取基因组 FASTA 与 LTRharvest 候选 → 非冗余 LTR-RT 库（`LTRlib.fa`）/ GFF3 注释 / LAI | ✅ 默认 8（注入 `-threads`） |

## 用法

```bash
# CLI 直跑（教学典型链路；在包含基因组的工作目录下执行）
python main.py run -genome genome.fasta -inharvest ltrharvest.out --threads 8

# 关闭全基因组注释（只建库，更快）
python main.py run -genome genome.fasta -inharvest ltrharvest.out --threads 8 --extra-args "-noanno"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 注入官方 `-threads`，`--tmpdir` 同时注入 `TMPDIR` 环境变量）。

> ⚠️ **工作目录约定**：官方 LTR_retriever **无 `-output_dir` 选项**，产物以「**基因组文件名**」为前缀（如 `genome.fasta.LTRlib.fa` / `genome.fasta.out.gff3` / `genome.fasta.pass.list`）写入**当前工作目录**，中间文件归入 `LTRretriever-pre<日期>/`。请先 `cd` 到目标项目目录再调用（容器运行同理，见「环境安装 §2」）。

## 实战示例：基因组 LTR-RT 挖掘（gt suffixerator → gt ltrharvest → LTR_retriever）

LTR_retriever 的标准输入是 **LTRharvest 候选**，因此典型链路为「GenomeTools 建索引 → LTRharvest 预测候选 → LTR_retriever 识别注释」。以下为原生 CLI 的两步前置 + 一步注释（教学课件 LTR_retriever 一节即 `gt suffixerator ... -tis -suf -lcp -des -ssp -sds -dna` → `gt ltrharvest ... -out ... -outinner ... -gff3 ...` → `LTR_retriever -genome ... -inharvest ...`）；**前置两步的等价能力由 `modules/genometools` 的 `suffixerator` / `ltrharvest` 子命令提供，注释步骤由本模块 `native/main.py` 的 `run` 子命令提供**（见上「用法」）。

### 1. 为基因组建立 ESA 索引（`gt suffixerator`，见 `modules/genometools`）

```bash
mkdir -p ltr_out && cd ltr_out

# -indexname genome：输出 genome.{esq,ssp,des,sds,suf,lcp,md5}
gt suffixerator -db ../genome.fasta -indexname genome \
    -tis -suf -lcp -des -ssp -sds -dna
```

### 2. 预测 LTR 候选（`gt ltrharvest`，见 `modules/genometools`）

```bash
# -index 指向第 1 步索引前缀；-out 为 LTR_retriever -inharvest 的输入候选
gt ltrharvest -index genome \
    -out ltrharvest.out -outinner ltrharvest.inner -gff3 ltrharvest.gff3
```

### 3. 识别、去冗余与注释（`LTR_retriever`，本模块）

```bash
# 在当前目录运行；产物前缀为基因组文件名（genome.fasta.*）
LTR_retriever -genome ../genome.fasta -inharvest ltrharvest.out -threads 8

# 或经本模块驱动（等价）
python ../../ltr_retriever/native/main.py run -genome ../genome.fasta \
    -inharvest ltrharvest.out --threads 8
```

核心产物：

```bash
ls -1 ../genome.fasta.*
# ../genome.fasta.LTRlib.fa            <- 非冗余 LTR-RT 库（供 RepeatMasker -lib）
# ../genome.fasta.LTRlib.redundant.fa  <- 含冗余的全部 LTR-RT
# ../genome.fasta.pass.list            <- 通过结构筛选的完整 LTR-RT 列表
# ../genome.fasta.out.gff3             <- 全基因组 LTR-RT 注释（-noanno 时无）
# ../genome.fasta.out.LAI              <- LTR Assembly Index
```

### 4. 桥接 RepeatMasker：用建好的库屏蔽/注释基因组

```bash
RepeatMasker -pa 8 -lib ../genome.fasta.LTRlib.fa -dir masked ../genome.fasta
```

### 5. 参数说明

| 参数                          | 说明                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `-genome <fasta>`           | 基因组序列 FASTA（驱动 `--genome`；建议使用短而简单的序列名）                                                |
| `-inharvest <file>`         | LTRharvest 候选文件（驱动 `--inharvest`；由 `gt ltrharvest` 产出，见 `modules/genometools`）         |
| `-threads <N>`              | 并行线程数（官方默认 4；本驱动由 `--threads` 注入，默认 8）                                                 |
| `-noanno`                   | 关闭全基因组注释（只建库，更快；经 `--extra-args` 透传）                                                   |
| `-minlen` / `-maxlenltr`    | LTR 区域最小/最大长度等结构筛选阈值（经 `--extra-args` 透传）                                              |
| `-max_ratio`                | 内部区域/LTR 区域最大长度比（默认 50，经 `--extra-args` 透传）                                             |
| `-step` / `-stop`           | 从指定步骤重启 / 在指定步骤停止（断点续跑，经 `--extra-args` 透传）                                            |
| `-cdhit_path` / `-hmmer` 等 | 依赖程序路径（默认从 ENV 查找；conda/容器已配好 PATH，通常无需指定）                                            |

> 💡 **与 RepeatModeler 的关系**：RepeatModeler 的 `-LTRStruct` 内部会调用 GenomeTools LTRharvest 并配合 LTR_retriever；用本模块（+ `modules/genometools`）可单独、可控地跑这条 LTR 注释链路。依赖方文档只需指向本模块安装文档，依赖管理不在本模块内。

## 依赖模块（安装见对应模块文档）

LTR_retriever 依赖的重复注释工具链由 conda 包自动装入；如需单独安装或核查版本，见对应模块文档：

| 依赖                     | 作用                     | 安装文档                                              |
| ---------------------- | ---------------------- | ------------------------------------------------- |
| GenomeTools (LTRharvest) | LTR 候选预测（`-inharvest` 输入来源） | [modules/genometools](../genometools/README.md)   |
| RepeatMasker           | 重复屏蔽（流程内部调用）           | [modules/repeatmasker](../repeatmasker/README.md) |
| RMBlast                | BLAST 引擎               | [modules/rmblast](../rmblast/README.md)           |
| CD-HIT                 | 序列去冗余                  | [modules/cd-hit](../cd-hit/README.md)             |
| MAFFT                  | 多序列比对（部分比对步骤；见上游文档）    | [modules/mafft](../mafft/README.md)               |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 `LTR_retriever` 二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n ltr_retriever-native -c conda-forge -c bioconda ltr_retriever=3.0.5
conda activate ltr_retriever-native
LTR_retriever -h 2>&1 | grep -i usage   # 断言（同包装入 cd-hit/repeatmasker/rmblast/tesorter 等依赖）
```

> 上游 README 提示：ltr_retriever 依赖较多，conda solver 可能耗时较长，且官方称新版 mamba 解算偶有问题；若 `mamba` 解算失败可改用 `conda`，或按上游 `conda env create -f LTR_retriever.yml`。

> Homebrew：homebrew-core 与 brewsci/bio 均无 `ltr_retriever` 公式（2026-09 核实 formulae.brew.sh API 与 `Formula/ltr_retriever.rb` 均 404）→ 无公式，不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ltr_retriever:3.0.5--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ltr_retriever:3.0.5--hdfd78af_0 \
    LTR_retriever -genome /data/genome.fasta -inharvest /data/ltrharvest.out -threads 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull ltr_retriever.sif docker://depot.galaxyproject.org/singularity/ltr_retriever:3.0.5--hdfd78af_0
apptainer run -B $PWD:/data -H /data ltr_retriever.sif \
    LTR_retriever -genome /data/genome.fasta -inharvest /data/ltrharvest.out -threads 8
```

### 4. 二进制包安装（官方源码归档，免安装但需自备依赖）

LTR_retriever 为 **installation-free 的 Perl 源码程序**（主脚本可直接 `perl` 运行），官方**无预编译二进制资产**，且运行需自备 **BLAST+ / CD-HIT / HMMER / RepeatMasker / TEsorter** 等依赖——因此一般**优先 conda / 官方容器路线**；确需源码安装时解压到用户前缀（无需 root）：

**GitHub release**：<https://github.com/oushujun/LTR_retriever/releases>（tag `v3.0.5`，与 `software_versions` 对齐）

```bash
wget https://github.com/oushujun/LTR_retriever/archive/refs/tags/v3.0.5.tar.gz -P ~/software/
tar zxf ~/software/v3.0.5.tar.gz -C ~/software/     # -> ~/software/LTR_retriever-3.0.5/
echo 'export PATH=$PATH:~/software/LTR_retriever-3.0.5' >> ~/.bashrc && source ~/.bashrc
LTR_retriever -h 2>&1 | grep -i usage               # 断言（依赖需另行就绪）
```

## 测试

```bash
bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/--help 参数契约）必跑；
# PATH 含 LTR_retriever 时追加 usage/版本探测与最小真跑链路（合成 genome.fa + ltrharvest.out → LTR_retriever
#   -genome/-inharvest；官方完整链路需 BLAST+/CD-HIT/HMMER/RepeatMasker/TEsorter 等依赖，真跑失败仅 [WARN]
#   提示不阻断，见脚本头注）。
```

## 版本

* ltr_retriever **3.0.5**（bioconda::ltr_retriever=3.0.5，`noarch: generic`，GPL-3.0-or-later；2026-09 核实）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/ltr_retriever / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方**无** ltr_retriever 子模块；snakemake-wrappers 亦**无** `bio/ltr_retriever`（均见下「官方实现登记」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow）

nf-core 官方 `modules/nf-core/ltr_retriever/` **不存在**（2026-09 在线核实：`https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/ltr_retriever` 返回 404，登记「官方无」）。本模块未建 `nextflow/` 目录：Nextflow DSL2 流程需要 LTR_retriever 时暂无官方模块可安装，以 `ltr_retriever_native` 为兜底（或在项目内自行封装 `LTR_retriever` 进程）。

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/ltr_retriever`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/ltr_retriever` 返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `ltr_retriever_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | ltr_retriever 版本 | 来源                                                                                                                    |
| ------------------ | --------------- | --------------------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **3.0.5**       | official biocontainer：quay.io/biocontainers/ltr_retriever:3.0.5--hdfd78af\_0 / bioconda ltr_retriever=3.0.5                  |
| nf-core master     | 官方无模块           | modules/nf-core/ltr_retriever 404（2026-09）                                                                            |
| snakemake-wrappers | 官方无 wrapper      | bio/ltr_retriever 404（2026-09）                                                                                         |

> 仅 native 一条可用路径（3.0.5）；nf-core / snakemake-wrappers 官方均无，Nextflow/Snakemake 场景需以 native 兜底或项目内自建。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# ltr_retriever native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 ltr_retriever-native.yml 后 mamba env create -f ltr_retriever-native.yml；
# 在线推荐上方 mamba create 直装命令。ltr_retriever=3.0.5 会把 cd-hit/repeatmasker/rmblast/tesorter
# 等依赖一并装入（本模块不单独管理）。
name: ltr_retriever-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - ltr_retriever=3.0.5
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/ltr_retriever>

* **Docker**：`docker pull quay.io/biocontainers/ltr_retriever:3.0.5--hdfd78af_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/ltr_retriever%3A3.0.5--hdfd78af_0>

* 安装方式（本地）：`mamba create -n ltr_retriever-native -c conda-forge -c bioconda ltr_retriever=3.0.5`

* 上游 GitHub：<https://github.com/oushujun/LTR_retriever>（release 为源码 tag 归档，无预编译 assets）· 相关模块：`modules/genometools`（LTRharvest 候选）、`modules/cd-hit`、`modules/mafft`、`modules/repeatmodeler`
