# flair 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# flair / native — 自包含 isoform 分析驱动

FLAIR（Full-Length Alternative Isoform analysis of RNA）的本地自包含实现
（`source_type: custom`、`type: native`；Nanopore direct RNA-seq 模式）。

## 功能

三个子命令对应 nanoseq 的 FLAIR\_CONSENSUS 三段链路：

| 子命令         | 可执行                     | 作用                                      |
| ----------- | ----------------------- | --------------------------------------- |
| `bam2bed12` | `bam2Bed12`             | sorted BAM → BED12（剪接结构）                |
| `annotate`  | `identify_gene_isoform` | BED12 + GTF → 带基因注释 BED                 |
| `collapse`  | `flair`                 | 带注释 BED + genome + reads → 一致性转录本 FASTA |

`collapse` 完整迁移了 nanoseq 的 direct RNA-seq 优化参数：
`-q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold --stringent --check_splice --mm2_args="-I8g,--MD" --quiet`。

## 用法

```bash
# CLI 直跑
python main.py bam2bed12 -i sample.sorted.bam -o sample.bed12
python main.py annotate sample.bed12 gencode.v49.annotation.gtf sample.annotated.bed
python main.py collapse -q sample.annotated.bed -g hg38.fa -r sample.fastq.gz \
    -o out/sample -f gencode.v49.annotation.gtf -s 3 -w 100 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba create -n flair-native -c conda-forge -c bioconda flair=3.0.0b1 minimap2=2.30   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate flair-native
```

### 2. Docker（官方镜像直拉，不维护本地 Dockerfile）

```bash
docker pull quay.io/biocontainers/flair:<tag>        # tag 见 quay 页面（或文末「容器与 Conda 链接」）
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data quay.io/biocontainers/flair:<tag> \
    flair collapse -q /data/sample.annotated.bed -g /data/hg38.fa -r /data/sample.fastq.gz \
    -o /data/out/sample -f /data/gencode.v49.annotation.gtf
```

### 3. Apptainer / Singularity（官方镜像直拉，不维护本地 Apptainer.def）

```bash
apptainer pull flair.sif docker://quay.io/biocontainers/flair:<tag>
# 或直链 depot.galaxyproject.org/singularity/flair%3A<tag>（与 quay 同 build tag）
apptainer run -B $PWD:/data -H /data flair.sif flair collapse \
    -q /data/sample.annotated.bed -g /data/hg38.fa -r /data/sample.fastq.gz -o /data/out/sample
```

> 官方镜像内为原生 flair 入口（仅工具，无 main.py）；需要 Schema/自省/参数注入时在**宿主机**（已装 flair 或 conda env）运行 `python main.py collapse ...`。

## 测试

```bash
bash test/run_test.sh   # 无需真实 long-read 数据；flair 未安装时退化为 argv 构造验证
```

## 版本

* flair 3.0.0b1（bioconda::flair=3.0.0b1，包内可执行 flair / bam2Bed12 / identify\_gene\_isoform；由官方镜像/conda 提供：quay.io/biocontainers/flair、bioconda flair=3.0.0b1）

* 依赖 minimap2=2.30（flair collapse 内部比对；宿主机用 conda/mamba 装环境时一并安装）

* 构建路线：official biocontainer（quay.io/biocontainers/flair / depot.galaxyproject.org）；本地不再自建容器

## 历史留存

多步组合脚本（bam2Bed12 → identify\_gene\_isoform → collapse）的流程版见 `workflow/nanoseq/native/02_run_flair_consensus.sh`（Stage 02 · FLAIR；硬编码项目路径，仅供追溯对照 / 一键运行）；正式能力请走 `main.py` 的 bam2bed12 / annotate / collapse 原子子命令。

***

## snakemake 实现

# flair / snakemake / local — 自维护 Snakemake 规则（td2 式）

官方 `snakemake-wrappers` 无 `bio/flair`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。
布局对齐 td2 式集成层规范（AGENT「snakemake 集成层规范」）：wrapper（`*.py`）、conda
环境（`flair.yaml`）与 helper **平铺**在本目录根，`.smk` 内 `conda:` / `script:` 一律用
**同目录相对名**（无 `envs/` / `scripts/` / `../envs` / `../scripts` 幽灵引用）；规则
**config 驱动**（顶部 `config.setdefault` 给默认，顶层键由 `--config` 提供、头注含独立
运行示例），不依赖 workflow 的 `SAMPLES` / `{sample}` / `output_dir` 层级。

## 规则文件（每 rule 一 .smk，对应 nanoseq FLAIR\_CONSENSUS 三段链路）

| .smk | rule | 执行指令 | 内容 |
| ---- | ---- | ---- | ---- |
| `flair_bam2bed12.smk` | `flair_bam2bed12` | `script:` + `flair_bam2bed12.py` | sorted BAM → BED12：`bedtools bamtobed -bed12` + helper 尾逗号修复（多步/helper → wrapper） |
| `flair_annotate.smk` | `flair_annotate` | `script:` + `flair_annotate.py` | `identify_gene_isoform <bed12> <gtf> <annotated_bed>`（单条命令 → wrapper，docker/native/conda 三模式） |
| `flair_collapse.smk` | `flair_collapse` | `script:` + `flair_collapse.py` | `flair collapse -q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold --stringent --check_splice --mm2_args=... --quiet`（多布尔开关 + 三模式 + 产物搬运 → wrapper） |

conda 环境统一用同目录 `flair.yaml`（三个 .smk 共用）；wrapper 经两级 `sys.path` 注入
`modules/`，用共享 `docker_wrapper.docker_wrapper_binary(config, "flair", ...)` 分派
conda/docker/native 三种模式（bam2bed12 走 `bedtools_bin`、collapse 走 `flair_bin`、
annotate 走 `identify_gene_isoform_bin`）。

## helper 归属

* `bed12_add_trailing_commas.py` — 归属 `flair_bam2bed12` 规则：`bedtools bamtobed -bed12`
  输出的 blockSizes/blockStarts 缺尾逗号，helper 补逗号以满足 BED12 规范（输出与 FLAIR
  官方 `bam2Bed12` 等价）；由 wrapper `flair_bam2bed12.py` 以 `Path(__file__).parent`
  同目录定位调用，未在 shell 内联。该资产同时登记于 nanoseq.md「单步辅助脚本/规则配套」表。

## 用法

独立运行（三段各自可跑；链式衔接：令下游输入键 == 上游输出键即自动建立依赖）：

```bash
# bam2bed12：sorted BAM → BED12
snakemake -s modules/flair/snakemake/flair_bam2bed12.smk \
    --config flair_bam2bed12_input=aln.sorted.bam flair_bam2bed12_output=out/aln.bed12 \
    --cores 4 --use-conda

# annotate：BED12 + GTF → 带基因注释 BED
snakemake -s modules/flair/snakemake/flair_annotate.smk \
    --config flair_annotate_input_bed12=out/aln.bed12 \
            flair_annotate_gtf=gencode.v49.annotation.gtf \
            flair_annotate_output=out/aln.annotated.bed \
    --cores 4 --use-conda

# collapse：带注释 BED + genome + reads → 一致性转录本 FASTA
snakemake -s modules/flair/snakemake/flair_collapse.smk \
    --config flair_collapse_annotated_bed=out/aln.annotated.bed \
            flair_collapse_genome=hg38.fa flair_collapse_reads=reads.fastq.gz \
            flair_collapse_gtf=gencode.v49.annotation.gtf \
            flair_collapse_output=out/aln.flair.collapse.fasta \
    --cores 8 --use-conda
```

流程内使用（config 契约细节见各 .smk 头注与软件级 meta.yaml `snakemake_include_hint`）：

```python
# Snakefile 中
include: "modules/flair/snakemake/flair_bam2bed12.smk"
include: "modules/flair/snakemake/flair_annotate.smk"
include: "modules/flair/snakemake/flair_collapse.smk"

rule all:
    input: config["flair_collapse_output"]
```

`exec_mode` 默认 conda（`--use-conda` 解析同目录 `flair.yaml`）；`docker` / `native` 需在
Snakefile 的 config/config.yaml 预设 `flair.docker_image` / `flair.bedtools_bin` /
`flair.flair_bin` / `flair.identify_gene_isoform_bin`（三个 wrapper 规则
bam2bed12/annotate/collapse 均支持三模式分派）。

## 依赖环境

规则内 `conda: "flair.yaml"`（同目录，已随规则交付，无需自备）：

```yaml
# flair.yaml
channels: [conda-forge, bioconda]
dependencies:
  - bioconda::flair==3.0.0b1      # 提供 bam2Bed12 / identify_gene_isoform / flair
  - bioconda::minimap2==2.30      # flair collapse 内部依赖（--mm2_args 比对）
  - bioconda::bedtools>=2.31.1    # flair_bam2bed12 规则（bedtools bamtobed -bed12）
```

## 与其它实现的关系

* 官方 wrapper 若未来出现（重新抓取 bio/flair 有目录），可切换回官方 `wrapper:` 句柄
  （snakemake-wrappers 信息登记于软件级 meta.yaml `software_versions`，仓库不建目录）

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# flair native Conda 环境配方
# 离线兜底：可另存为 flair-native.yml 后 mamba env create -f flair-native.yml；在线推荐上方 mamba create 直装命令
# 说明：flair 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：官方镜像优先（quay.io/biocontainers/flair），不再维护 Dockerfile/Apptainer.def。
name: flair-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - flair=3.0.0b1      # 提供 flair / bam2Bed12 / identify_gene_isoform
  - minimap2=2.30      # flair collapse 内部依赖（--mm2_args 比对）
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/flair/overview>

* **Docker**：`docker pull quay.io/biocontainers/flair:3.0.1--pyhdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/flair%3A3.0.1--pyhdfd78af_0>

* 安装方式（本地）：`mamba create -n flair -c conda-forge -c bioconda flair=3.0.1`

