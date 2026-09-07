# gstama 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# gstama / native

自包含的 gstama 驱动实现（`source_type: custom`），命令逻辑对齐同目录 `gs_tama.py` / `tama_polyacleanup.py`。

## 能力

| 子命令            | 说明                            | 依赖                              |
| -------------- | ----------------------------- | ------------------------------- |
| `polyacleanup` | TAMA FLNC polyA 清理并 gzip 输出   | `tama_flnc_polya_cleanup.py`    |
| `collapse`     | 转录本去冗余（collapse）              | `tama_collapse.py` + `samtools` |
| `filelist`     | 由 collapse bed 生成 merge 用 TSV | 无（纯 Python）                     |
| `merge`        | 合并多来源转录本集合                    | `tama_merge.py`                 |

Iso-Seq 链路：`bamtools convert` → `polyacleanup` → `minimap2 align` → `collapse` → `filelist` → `merge`。

## 快速开始

### 1. 安装环境

```bash
mamba create -n gstama-native -c conda-forge -c bioconda gs-tama=1.0.4 samtools=1.21
conda activate gstama-native
```

### 2. CLI 调用

```bash
# polyA 清理（bamtools convert 的 FASTA 输出）
python main.py polyacleanup --fasta flnc.fa --outdir gstama --prefix sample

# collapse（输入 minimap2 排序 BAM + 参考）
python main.py collapse --bam aln.bam --fasta ref.fa --outdir collapse --prefix sample

# filelist（纯 Python 生成 TSV）
python main.py filelist --bed-dir collapse/beds --outdir filelist --prefix fl

# merge
python main.py merge --filelist filelist/fl.tsv --outdir merge --prefix merged
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py collapse --bam x.bam --fasta r.fa --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gstama:1.0.4-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gstama:1.0.4-v1.0 \
  collapse --bam /data/aln.bam --fasta /data/ref.fa --outdir /data/collapse
```

Apptainer：

```bash
apptainer build gstama.sif Apptainer.def
apptainer run -B "$PWD":/data gstama.sif polyacleanup --fasta /data/flnc.fa --outdir /data
```

### 5. 测试

```bash
bash test/run_test.sh
```

`filelist` 子命令不依赖任何外部工具（纯 Python），无 gs-tama 环境也能端到端验证；
`polyacleanup/collapse/merge` 需 gs-tama 脚本（bioconda `gs-tama=1.0.4`），未安装时测试自动降级为命令构建自检。

## 版本说明

* **二进制来源**：bioconda `gs-tama=1.0.4`（apt 无此包），包提供
  `tama_flnc_polya_cleanup.py` / `tama_collapse.py` / `tama_merge.py` 到 env `bin/`。

* **容器路线**：Dockerfile / Apptainer.def 用 **micromamba** 引导 bioconda env（禁止 miniconda），
  驱动 main.py 由 env python 运行。

* `collapse` 依赖 `samtools`（tama\_collapse.py 内部调用），容器 env 已含 `samtools=1.21`。

## 性能优化约定

* TAMA 脚本为单线程；`--threads` 作为契约字段接收，供上层调度器参考。

* `--tmpdir` 覆盖 `$TMPDIR`；所有中间产物落在 `--outdir` 内。

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为** **`main.py`**。

* `gs_tama.py, tama_polyacleanup.py`

## 版本与来源（重要）

gs-tama（tama\_\* 脚本与 tama-py3 库）**必须使用 1.0.4 版本，其他版本无法运行**。

* 来源：<https://github.com/SiYangming/gs-tama>

* 安装（conda，YangmingSi 频道）：`mamba create -n gstama -c YangmingSi -c conda-forge -c bioconda gs-tama=1.0.4`

* Conda 页面：<https://anaconda.org/channels/YangmingSi/packages/gs-tama/overview>

* Docker（bioinfortools）：`docker pull quay.io/bioinfortools/gs-tama:1.0.4`

* 容器：quay.io/biocontainers/gs-tama:1.0.4

* **容器（bioinfortools 频道，1.0.4）**：`docker pull quay.io/bioinfortools/gs-tama:1.0.4`

* **Bioconda 官方容器**（仅到 1.0.3）：`docker pull quay.io/biocontainers/gs-tama:1.0.3--hdfd78af_0`

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/gs-tama/overview>

* **YangmingSi 频道页面**：<https://anaconda.org/channels/YangmingSi/packages/gs-tama/overview>

* 仓库内 tama-py3/ 参考库来自该仓库 1.0.4；被误删时可用 `git clone --branch 1.0.4 https://github.com/SiYangming/gs-tama` 重新获取。

***

## snakemake 实现

# gstama / snakemake / local — 自维护 Snakemake rule

自维护规则（自包含：不依赖 `workflow/lib/helpers.py` 与流程级 `docker_run` 配置）。

> 官方 `bio/gstama` 在 snakemake-wrappers 中不存在（404），本目录是 Snakemake 场景的**实际执行路径**。

## 文件

| 文件                        | 作用                                                 |
| ------------------------- | -------------------------------------------------- |
| `gstama_polyacleanup.smk` | polyA 清理 + gzip（tama\_flnc\_polya\_cleanup.py）     |
| `gstama_collapse.smk`     | 转录本去冗余（tama\_collapse.py）                          |
| `gstama_filelist.smk`     | 由 collapse bed 生成 merge TSV（`run:` 纯 Python，无外部依赖） |
| `gstama_merge.smk`        | 合并转录本（tama\_merge.py，空 filelist 自动跳过）              |

> 注：规则无 `conda:` / `script:` 引用，直接 `shell:` / `run:` 调 `tama_*.py`，执行前需保证
> PATH 上有 `gs-tama=1.0.4`（如 `mamba create -n gstama -c YangmingSi -c conda-forge -c bioconda gs-tama=1.0.4`
> 或 native 容器）；无 wrapper `.py`，无需 sys.path 注入。软件级 `meta.yaml` 的 `snakemake_rules` /
> `snakemake_include_hint` 已逐个登记这 4 个 `.smk`。

## 使用

在 Snakefile 中：

```python
include: "modules/gstama/snakemake/gstama_polyacleanup.smk"
include: "modules/gstama/snakemake/gstama_collapse.smk"
include: "modules/gstama/snakemake/gstama_filelist.smk"
include: "modules/gstama/snakemake/gstama_merge.smk"

rule all:
    input:
        "results/gstama_merge/merged.bed",
```

## 规则设计说明

* 无流程级 `docker_run` / `GSTAMA_DOCKER_IMAGE` 容器配置。

* collapse 默认输入为 minimap2 比对产物路径
  `results/minimap2/{aligner}/{sample}/{sample}.chunk{n}.bam`（ultra 场景需自行改 input）。

* merge 的 bed 列表在 `run:` 块内以 glob 遍历生成。

* 参数由 `config["gstama"]` 读取并内联默认值：

  * `collapse_args: "-x no_cap -a 100 -z 100 -sj sj_priority -sjt 20 -lde 5"`

  * `merge_args: "-a 100 -z 100 -m 20 -d merge_dup"`

  * `filelist_cap: "no_cap"`、`filelist_order: "1"`

* 各规则写 `versions.yml`（与 nf-core 模块风格一致）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# gstama native Conda 环境配方
# 离线兜底：可另存为 gstama-native.yml 后 mamba env create -f gstama-native.yml；在线推荐上方 mamba create 直装命令
# 说明：apt 无 gs-tama 包，本环境为唯一 Conda 兜底；Docker/Apptainer 用 micromamba 引导同款 env。
name: gstama-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - gs-tama=1.0.4
  - samtools=1.21   # tama_collapse.py 内部调用 samtools
  - pyyaml>=6.0
  - pip
```

