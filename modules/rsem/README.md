# rsem 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake）的用法；官方 snakemake-wrappers 与 nf-core 子模块信息记录于此（不建目录，仅说明层）。安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# rsem / native

自包含的 RSEM 驱动实现（`source_type: custom`）。官方镜像优先（bioconda → quay.io/biocontainers → depot.galaxyproject.org 已有 rsem 官方镜像，rsem=1.3.3 与 bioconda/nf-core 同上游版本），本地不再维护 Dockerfile/Apptainer.def。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `prepare-reference` | rsem-prepare-reference：参考 FASTA + GTF → RSEM 参考索引（.seq/.grp/.ti/.transcripts.fa） | ✅（默认 8） |
| `calculate-expression` | rsem-calculate-expression：转录组 BAM（`--alignments`，riboseq 主用法）或 reads 直算 → 基因/转录本定量 | ✅（默认 8） |

## 快速开始

### 1. 安装环境

```bash
# 途径 1：conda（宿主机直跑 main.py；HPC 无 root 场景；配方见文末「Conda 环境」节）
mamba create -n rsem-native -c conda-forge -c bioconda rsem=1.3.3 bowtie2=2.5.4   # native/ 不随仓库存放 environment.yml，按文末配方自建
conda activate rsem-native
# 途径 2：官方容器（bioconda 官方镜像，只含 rsem 工具；用法见第 4 节）
docker pull quay.io/biocontainers/rsem:<tag>     # tag 见 quay 页面（示例 1.3.3--pl5321h077b44d_12）
```

### 2. CLI 调用

```bash
# 建立 RSEM 参考（GTF + bowtie2 路线，与 riboseq 流程一致）
python main.py prepare-reference genome.fa rsem_idx --gtf genes.gtf --bowtie2 --threads 8

# 定量（riboseq 主用法：umi 去重后的转录组比对 BAM）
python main.py calculate-expression --alignments sample_dedup.bam \
    --index rsem_idx --prefix sample \
    --fragment-length-mean 300 --fragment-length-sd 100 --strandedness forward --threads 8

# reads 直算模式（rsem 内部调用 aligner）
python main.py calculate-expression --reads r1.fq.gz --reads2 r2.fq.gz \
    --index rsem_idx --prefix sample --bowtie2 \
    --fragment-length-mean 300 --fragment-length-sd 100 --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制：

```bash
# Docker：工具直跑（官方镜像内只含 rsem，main.py 驱动在宿主机运行）
docker pull quay.io/biocontainers/rsem:<tag>        # tag 见 quay 页面（示例 1.3.3--pl5321h077b44d_12）
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data quay.io/biocontainers/rsem:<tag> \
  calculate-expression --alignments /data/sample_dedup.bam \
  --index /data/rsem_idx --prefix /data/sample --threads 8

# Singularity/Apptainer
apptainer pull rsem.sif docker://quay.io/biocontainers/rsem:<tag>
# 或直链 depot.galaxyproject.org/singularity/rsem%3A<tag>（与 quay 同 build tag）
```

> 容器内为原生工具入口；需要 Schema/自省/参数注入时在**宿主机**（conda env 装 rsem）运行 `python main.py <subcommand> ...`。

### 5. 测试

```bash
bash test/run_test.sh    # 本机无 rsem 时自省链路通过即可；装 rsem+bowtie2 后自动补跑真实链路
```

## 性能优化约定

- **线程**：`prepare-reference` / `calculate-expression` 默认 8 线程（CPU 密集），用户显式 `--threads` 永远优先。
- **临时目录**：通过 `TMPDIR`（`meta.yaml.optimization.env_vars`，占位符 `{tmpdir}`）注入，避免污染工作目录。
- **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。


## 实战示例：Trinity de novo 组装后的 RSEM 定量

RSEM 除直接以 `rsem-prepare-reference` / `rsem-calculate-expression` 运行（见上「快速开始」）外，最常见的教学用法是作为 Trinity 组装流程的定量步骤被批量调用：Trinity 自带 `align_and_estimate_abundance.pl` 会在内部串起「RSEM 建索引 + 逐样本定量」，并对每个样本输出 `RSEM.isoforms.results` / `RSEM.genes.results`。以下示例为 **bowtie** 比对路线（与官方 bio/rsem wrapper 口径一致）；需要 bowtie2 路线时改用 `rsem-prepare-reference --bowtie2` 与 `rsem-calculate-expression --bowtie2`（见上「快速开始」）。`get_Trinity_gene_to_trans_map.pl` / `align_and_estimate_abundance.pl` 位于 Trinity 安装目录的 `util/` 下，请将该目录加入 `PATH` 或按实际安装位置用全路径调用。

### 1. 生成基因-转录本映射并构建 RSEM 参考索引

无参考注释的 de novo 场景需由 Trinity 组装结果（FASTA）先生成基因-转录本映射文件，供 RSEM 基因水平汇总使用：

```bash
mkdir -p exp_cal && cd exp_cal
ln -s ../Trinity.fasta ./

# 生成基因-转录本映射文件（gene_trans_map）
get_Trinity_gene_to_trans_map.pl Trinity.fasta > Trinity.fasta.gene_trans_map

# 构建 RSEM 参考索引（--prep_reference；内部调用 rsem-prepare-reference）
align_and_estimate_abundance.pl --transcripts Trinity.fasta --est_method RSEM \
    --output_dir . --aln_method bowtie --prep_reference \
    --gene_trans_map Trinity.fasta.gene_trans_map
```

### 2. 批量计算表达量（逐样本）

```bash
for i in `ls ../*.1.fastq`
do
    s=${i/*\//}
    s=${s/.1.fastq/}
    align_and_estimate_abundance.pl --transcripts Trinity.fasta --seqType fq \
        --left ../$s.1.fastq --right ../$s.2.fastq --SS_lib_type RF \
        --est_method RSEM --aln_method bowtie --thread_count 8 \
        --gene_trans_map Trinity.fasta.gene_trans_map --output_dir $s &> $s.log
done
```

### 3. 整理结果并合并表达量矩阵

每个样本的输出目录内含 `RSEM.isoforms.results`（转录本水平）与 `RSEM.genes.results`（基因水平）定量结果，可先提到同一层再汇总：

```bash
# 把各样本的 isoforms 结果复制到当前目录
for i in `ls */RSEM.isoforms.results`
do
    x=${i/\/RSEM/}
    cp $i $x
done

# 多样本汇总为 count/TPM 表达量矩阵（Trinity 工具，--out_prefix 可分别生成基因/转录本矩阵）
abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix genes ../exp_cal/*.genes.results
abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix isoforms ../exp_cal/*.isoforms.results
```

### 4. 参数说明

| 参数 | 说明 |
|------|------|
| `--est_method` | 表达量估计方法：RSEM 或 eXpress |
| `--aln_method` | 比对方法：bowtie 或 bowtie2 |
| `--SS_lib_type` | 链特异性文库类型：RF 表示 fr-firststrand |
| `--prep_reference` | 先构建参考序列索引 |
| `--gene_trans_map` | 基因-转录本映射文件（基因水平汇总必需） |
| `--thread_count` | 线程数 |

---

## snakemake 实现

# rsem / snakemake（本地规则 + 官方 wrappers 参考）

### 本地单规则文件（type: snakemake_local）

`snakemake/` 下两个子命令各自一个 **config 驱动 .smk**（td2 式：每 rule 一个文件，顶部 `config.setdefault` 给默认、头注写独立运行示例），不依赖 workflow 的 SAMPLES / `{sample}` 层级：

| 规则 / .smk | 作用 | config 契约要点 |
|------|------|------------------|
| `rsem_prepare_reference.smk` → `rsem_prepare_reference` | 参考 FASTA +（可选）GTF → RSEM 参考索引（rsem-prepare-reference） | `rsem_input_fasta`（必填）、`rsem_gtf`、`rsem_index_prefix`；exec 键 `rsem.prepare_reference_bin` / `rsem.prepare_reference_params` / `rsem.docker_image` |
| `rsem_calculate_expression.smk` → `rsem_calculate_expression` | umi 去重后 BAM（`rsem_input_bam`）或 FASTQ 直算（`rsem_input_fq_one`/`rsem_input_fq_two`）→ `.genes/.isoforms.results` 定量 | `rsem_index_prefix`、`rsem_out_prefix`；exec 键 `rsem.calculate_expression_bin` / `rsem.calculate_expression_params` / `rsem.fragment_length_mean` / `rsem.fragment_length_sd` / `rsem.strandedness` / `rsem.paired_end` |

- 配套文件（均平铺在 `snakemake/` 根，规则内 `conda`/`script` 用同目录相对名）：`snakemake/rsem.yaml`（bioconda rsem=1.3.3，与 riboseq 一致）、`snakemake/rsem_prepare_reference.py` / `rsem_calculate_expression.py`（docker/native/conda 三模式分派依赖共享 `modules/docker_wrapper.py`；wrapper 顶部 `sys.path` 注入两级到 `modules/`）。
- 两个 .smk 共用同一 `rsem_index_prefix` 即自动建立 prepare→calculate 依赖；`exec_mode`（conda 默认 / docker / native）与各键默认值见各 .smk 头注。

独立运行示例：

```bash
# 建索引
snakemake -s modules/rsem/snakemake/rsem_prepare_reference.smk \
    --config rsem_input_fasta=genome.fa rsem_gtf=genes.gtf rsem_index_prefix=rsem_idx \
    --cores 8 --use-conda
# BAM 定量（riboseq 主用法：umi 去重后转录组比对 BAM）
snakemake -s modules/rsem/snakemake/rsem_calculate_expression.smk \
    --config rsem_input_bam=sample_dedup.bam rsem_index_prefix=rsem_idx \
    rsem_out_prefix=quant/sample --cores 8 --use-conda
# FASTQ 直算（提供 rsem_input_fq_two 即自动 --paired-end）
snakemake -s modules/rsem/snakemake/rsem_calculate_expression.smk \
    --config rsem_input_fq_one=s1_R1.fq.gz rsem_input_fq_two=s1_R2.fq.gz \
    rsem_index_prefix=rsem_idx rsem_out_prefix=quant/s1 --cores 8 --use-conda
```

流程内 include：

```python
include: "modules/rsem/snakemake/rsem_prepare_reference.smk"
include: "modules/rsem/snakemake/rsem_calculate_expression.smk"
rule all:
    input: config["rsem_out_prefix"] + ".genes.results"
```

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> 本模块**不重写官方 wrapper 源码**。官方仓库 `bio/rsem/` 子模块如下（2026-09 抓取，以官方在线目录为准）：

| wrapper | wrapper 句柄 | 环境 pin（master） |
|---------|--------------|--------------------|
| calculate-expression | `vX.Y.Z/bio/rsem/calculate-expression` | rsem=1.3.3, bowtie=1.3.1 |
| prepare-reference | `vX.Y.Z/bio/rsem/prepare-reference` | rsem=1.3.3 |
| generate-data-matrix | `vX.Y.Z/bio/rsem/generate-data-matrix` | rsem=1.3.3 |

引用示例（Snakefile）：

```python
rule rsem_calculate_expression:
    input:
        bam="mapped.dedup.bam",
        index="rsem_index"
    output:
        genes="sample.genes.results",
        isoforms="sample.isoforms.results"
    log: "logs/rsem_calculate_expression.log"
    params:
        extra="--fragment-length-mean 300 --fragment-length-sd 100"
    threads: 8
    wrapper: "v3.13.0/bio/rsem/calculate-expression"
```

> ⚠️ 本模块未内置官方 wrapper 的 wrapper.py：Snakemake 运行时按 `wrapper:` 句柄解析（联网拉取中央 wrapper 缓存）；离线/私有环境缺失时请改用本模块 `snakemake/rsem_{prepare_reference,calculate_expression}.smk` 本地规则。
> 更新子模块清单的抓取命令：
> `curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/rsem | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### nf-core 官方参考（Nextflow，说明层）

本模块未建 `nextflow/` 目录；nf-core 官方 `modules/nf-core/rsem/` 子模块（2026-09 抓取，以官方在线目录为准）：

| 子模块 | environment.yml 关键 pin |
|--------|--------------------------|
| calculateexpression | bioconda::rsem=1.3.3, star=2.7.10a |
| preparereference | bioconda::rsem=1.3.3, star=2.7.10a |

组装 Nextflow DSL2 流程时执行 `nf modules install nf-core rsem calculateexpression preparereference`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），随后：

```nextflow
include { RSEM_CALCULATEEXPRESSION } from '../modules/nf-core/rsem/calculateexpression/main'
include { RSEM_PREPAREREFERENCE } from '../modules/nf-core/rsem/preparereference/main'
```

> ⚠️ nf-core rsem 默认走 **STAR** 比对路线（environment.yml pin star=2.7.10a），与 native/snakemake（bowtie2/bowtie）不同；把流程迁移到 Nextflow 时需同步准备 STAR 索引并核对比对口径。
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/rsem | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`


---

## 版本差异声明（native / snakemake-wrappers / nf-core）

| 实现 | rsem 版本 | 配套 aligner | 来源 |
|------|-----------|--------------|------|
| native（官方镜像/conda） | **1.3.3** | bowtie2 2.5.0（`--bowtie2`） | quay.io/biocontainers/rsem / bioconda（官方镜像优先，本地不再自建容器） |
| snakemake 本地规则 env | 1.3.3 | bowtie2（流程先比后 `--alignments`） | bioconda（`snakemake/rsem.yaml`，与 riboseq 一致） |
| snakemake-wrappers v3.13.0 / master | 1.3.3 | bowtie 1.3.1（calculate-expression） | bioconda（bio/rsem/*/environment.yaml） |
| nf-core master | 1.3.3 | STAR 2.7.10a | bioconda（modules/nf-core/rsem/*/environment.yml） |

> rsem 上游 1.3.3（2021-04 后无新 release），四路**主版本完全一致**；差异仅在配套 aligner（STAR vs bowtie2 vs bowtie）与构建来源，跨实现迁移时重点核对比对输入口径（`--alignments` BAM 是否同源）即可。


---

## Conda 环境（native 兜底配方；snakemake env 见 `snakemake/rsem.yaml`）

```yaml
# rsem native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 rsem-native.yml 后 mamba env create -f rsem-native.yml；在线推荐上方 mamba create 直装命令
name: rsem-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - rsem=1.3.3
  - bowtie2=2.5.4     # --bowtie2 路线（与 riboseq 流程一致）
  - pyyaml>=6.0
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/bioconda/rsem
- **Docker（quay biocontainers，riboseq 流程同款）**：`docker pull quay.io/biocontainers/rsem:1.3.3--pl5321h077b44d_12`
- **Singularity**：https://depot.galaxyproject.org/singularity/rsem%3A1.3.3--pl5321h077b44d_12
- 安装方式（本地）：`mamba create -n rsem -c conda-forge -c bioconda rsem=1.3.3 bowtie2`（官方镜像/conda 提供，见上「版本差异声明」）
- 上游 GitHub：https://github.com/deweylab/RSEM（官方文档：https://deweylab.github.io/RSEM/）
