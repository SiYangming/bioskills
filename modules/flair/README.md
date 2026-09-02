# flair 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# flair / native — 自包含 isoform 分析驱动

FLAIR（Full-Length Alternative Isoform analysis of RNA）的本地自包含实现
（`source_type: custom`、`type: native`），命令逻辑迁移自
`snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh`（Nanopore direct RNA-seq 模式）。

## 功能

三个子命令对应 nanoseq 的 FLAIR_CONSENSUS 三段链路：

| 子命令 | 可执行 | 作用 |
|--------|--------|------|
| `bam2bed12` | `bam2Bed12` | sorted BAM → BED12（剪接结构） |
| `annotate` | `identify_gene_isoform` | BED12 + GTF → 带基因注释 BED |
| `collapse` | `flair` | 带注释 BED + genome + reads → 一致性转录本 FASTA |

`collapse` 完整迁移了 nanoseq 的 direct RNA-seq 优化参数：
`-q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold
--stringent --check_splice --mm2_args="-I8g,--MD" --quiet`。

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
mamba env create -f environment.yml   # name: flair-native（含 flair + minimap2）
conda activate flair-native
```

### 2. Docker

```bash
docker build -t bioskills/flair:3.0.0b1-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/flair:3.0.0b1-v1.0 collapse \
    -q sample.annotated.bed -g hg38.fa -r sample.fastq.gz -o out/sample -f gencode.v49.annotation.gtf
```

### 3. Apptainer / Singularity

```bash
apptainer build flair.sif Apptainer.def
apptainer run -B $PWD:/data -H /data flair.sif collapse \
    -q /data/sample.annotated.bed -g /data/hg38.fa -r /data/sample.fastq.gz -o /data/out/sample
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 long-read 数据；flair 未安装时退化为 argv 构造验证
```

## 版本

* flair 3.0.0b1（bioconda::flair=3.0.0b1，包内可执行 flair / bam2Bed12 / identify_gene_isoform）
* 依赖 minimap2=2.30（flair collapse 内部比对）
* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（flair 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自 nanoseq 流程 `nanoseq.sh/run_flair_consensus.sh` 的原始脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `run_flair_consensus.sh`


---

## snakemake 实现

# flair / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/flair`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `flair.smk` — 三个 rule，对应 nanoseq FLAIR_CONSENSUS 三段链路：
  - `flair_bam2bed12`：`bam2Bed12 -i <bam> > <bed12>`
  - `flair_annotate`：`identify_gene_isoform <bed12> <gtf> <annotated_bed>`
  - `flair_collapse`：`flair collapse -q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold --stringent --check_splice --mm2_args=... --quiet`

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh`，去除
nohup/PID/LOCK 后台运行封装与 `$HOME/miniconda3` 绝对路径依赖；`gtf_annotation` /
`genome_fasta` 走 `config.get(...)` 内联默认值。

## 用法

```python
# Snakefile 中
include: "modules/flair/snakemake/flair.smk"

# 运行
snakemake -j 8 consensus/sample1.flair.collapse.fasta
```

## 依赖环境

规则内 `conda: "envs/flair.yaml"`，需要自备：

```yaml
# envs/flair.yaml
channels: [conda-forge, bioconda]
dependencies:
  - flair=3.0.0b1
  - minimap2
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/flair 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# flair native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：flair 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
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

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/flair/overview
- **Docker**：`docker pull quay.io/biocontainers/flair:3.0.1--pyhdfd78af_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/flair%3A3.0.1--pyhdfd78af_0
- 安装方式（本地）：`mamba create -n flair -c conda-forge -c bioconda flair=3.0.1`
