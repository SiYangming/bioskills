# lima 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# lima / native — 自包含驱动

PacBio **条形码拆分与引物去除**的本地自包含实现（`source_type: custom`、`type: native`）。
二进制名与 conda 包名均为 **`lima`**。

## 功能

- `lima <reads> <primers> <out>`：去引物 / 按条形码拆分（reads 支持 bam/fasta/fasta.gz/fastq/fastq.gz）
- 输出扩展名按输入格式自动推断（bam→bam、fastq.gz→fastq.gz …）
- Iso-Seq 模式：`--isoseq` / `--peek-guess`
- 质量阈值：`--min-score`
- 报告产物：`.counts` / `.report` / `.summary` / `.json` / `.xml` / `.clips`（与输出同前缀）
- 自动注入线程（`-j`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py lima reads.bam primers.fasta out/demux.bam --isoseq --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `lima` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：Iso-Seq 流程中的引物去除与 barcode 拆分

lima 是 PacBio 的条形码拆分与引物去除工具（Iso-Seq 流程的第二步，ccs → lima → isoseq3 refine），用于去除测序引物序列和 barcode 信息：承接 ccs 产物，按引物 FASTA 去除测序引物与 barcode、并按引物对拆分 reads（等价能力见上「用法」的 `lima` 子命令）。

### 1. 准备引物 FASTA（同时含 5' 引物与 3' 引物）

引物文件需同时给出 5' 端引物与 3' 端引物（3' 引物按反向互补序列记录，lima 据此识别 reads 两端并成对拆分）。NEB / Clontech SMART 建库试剂盒的典型序列：

```bash
echo '>NEB_5p
GCAATGAAGTCGCAGGGTTGGG
>Clontech_5p
AAGCAGTGGTATCAACGCAGAGTACATGGGG
>NEB_Clontech_3p
GTACTCTGCGTTGATACCACTGCTT' > barcoded_primers.fasta
```

### 2. 去引物 + 拆分 barcode（Iso-Seq 模式）

```bash
lima sample.ccs.bam barcoded_primers.fasta sample.lima.bam --isoseq --no-pbi --peek-guess
```

`--isoseq` / `--peek-guess` 说明见上「功能」；`--no-pbi` 表示不生成 `.pbi` 索引（后续不需要按坐标回看 BAM 时更省时省空间）。产物 `sample.lima.bam` 及按引物对拆分的各片段 BAM，即为 isoseq3 refine 的输入。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda（宿主机直跑 main.py / HPC 无 root）

```bash
mamba create -n lima-native -c conda-forge -c bioconda lima=2.9.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate lima-native
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/lima:2.9.0--h9ee0642_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/lima:2.9.0--h9ee0642_0 lima --isoseq \
    /data/reads.bam /data/primers.fasta /data/demux.bam
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull lima.sif docker://depot.galaxyproject.org/singularity/lima:2.9.0--h9ee0642_0
apptainer run -B $PWD:/data -H /data lima.sif lima --isoseq \
    /data/reads.bam /data/primers.fasta /data/demux.bam
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

lima 是 PacBio 官方工具（The PacBio Barcode Demultiplexer and Primer Remover），官方以 **conda（bioconda）为主要分发**，GitHub release 亦提供预编译二进制（lima.tar.gz）：

* **官方文档**：<https://lima.how/>

* **官方 GitHub**：<https://github.com/PacificBiosciences/barcoding>（release 附预编译二进制）

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/lima/overview>

```bash
# conda 安装（官方推荐分发）
mamba create -n lima -c conda-forge -c bioconda lima=2.9.0
conda activate lima
lima --version   # 验证安装
```

> 官方镜像/conda 包内为原生 lima 入口（仅工具，无 main.py）；需要 Schema/自省/参数注入时在**宿主机**（conda env，见上）运行 `python main.py lima ...`（见「用法」）。

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；lima 未安装时退化为 argv 构造验证
```

## 版本

- lima 2.9.0（bioconda::lima=2.9.0，由官方镜像/conda 提供：quay.io/biocontainers/lima、bioconda lima=2.9.0）
- 构建路线：official biocontainer（quay.io/biocontainers/lima / depot.galaxyproject.org）；本地不再自建容器

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为 `main.py`**。

- `lima_analysis.py`


---

## snakemake 实现

# lima / snakemake / local — 自维护 Snakemake 规则（td2 式）

官方 `snakemake-wrappers` 无 `bio/lima`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`），td2 式布局：
**每 rule 一个 config 驱动 `.smk`**（lima 仅一个子命令 → 单规则文件）。

### 本地规则（td2 式：config 驱动、可独立运行）

| 文件 | 规则 | 作用 | 执行指令 |
|------|------|------|----------|
| `snakemake/lima.smk` | `lima` | reads BAM + 引物 FASTA → 去引物/拆分 BAM（含 `.pbi` / `.lima.report` / `.lima.summary` / `.lima.counts`） | `script:`（lima.py） |

- 配套文件（平铺 `snakemake/`，`.smk` 同目录相对引用）：`lima.yaml`（conda env：`bioconda::lima=2.9.0`）、`lima.py`（wrapper）。
  lima 为单条命令、无搬运/条件分支逻辑，docker/native/conda 三模式统一走同目录 wrapper `lima.py`
  （分派经共享 `modules/docker_wrapper.py` 的 `docker_wrapper_binary(config, "lima", "lima_bin", "lima")`，
  参考 `modules/samtools/snakemake/samtools_sort.py`）。
- 规则 **config 驱动、不依赖流程 `SAMPLES` / `{sample}` / `chunk` 目录层级**，config 契约见 `.smk` 头注（
  `lima_input_reads` / `lima_input_primers` 必填；`lima_output` 默认 `<输入去扩展名>.demux.bam`；
  `exec_mode` 默认 conda，docker/native 需在 config.yaml 预设 `lima.docker_image` / `lima.lima_bin`；
  `lima.extra_params` 透传，Iso-Seq 建议 `--isoseq --peek-guess`；`threads` 默认 8）。独立运行示例：

```bash
snakemake -s modules/lima/snakemake/lima.smk \
    --config lima_input_reads=sample.reads.bam lima_input_primers=primers.fasta \
    lima_output=demux/sample.demux.bam 'lima.extra_params=--isoseq --peek-guess' \
    --cores 8 --use-conda
```

- 流程内使用：`include: "modules/lima/snakemake/lima.smk"` 后在 `rule all` 引用 `config["lima_output"]`；
  与 `pbccs.smk` 串接时令 `lima_input_reads` == ccs 产物即自动建立依赖。
- 产物命名（BAM 主路径）：`<out>`（拆分 reads）与同目录 `<out>.pbi`、`<stem>.lima.{report,summary,counts}`
  （官方 prefix = 输出去扩展名）；`.lima.clips` / `.removed.bam` 等 side-product 按参数产生、非规则 output。
- 规则为 config 驱动单文件（无 `ccs/{sample}/{sample}.chunk{n}.bam` 模板依赖）；`conda:` 用同目录
  相对名 `"lima.yaml"`，无 `envs/` / `scripts/` 幽灵引用。

### 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 `bio/lima` 有目录），可切换回官方 `wrapper:` 句柄登记层
  （软件级 meta.yaml 的 `lima_snakemake_wrappers` 条目；官方说明层不建本地目录）
- 非 Snakemake 场景（独立 CLI / Agent Function Calling / FASTA·FASTQ 输入）请走 `../../native/`
  （`python main.py lima ...`，输出扩展名随输入推断）


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# lima native Conda 环境配方
# 离线兜底：可另存为 lima-native.yml 后 mamba env create -f lima-native.yml；在线推荐上方 mamba create 直装命令
# 说明：lima 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：官方镜像优先（quay.io/biocontainers/lima），不再维护 Dockerfile/Apptainer.def。
name: lima-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - lima=2.9.0
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/lima/overview
- **Docker**：`docker pull quay.io/biocontainers/lima:2.9.0--h9ee0642_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/lima%3A2.9.0--h9ee0642_0
- 安装方式（本地）：`mamba create -n lima -c conda-forge -c bioconda lima=2.9.0`
