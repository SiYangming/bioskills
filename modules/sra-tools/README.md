# sra-tools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# sra-tools / native — 自包含 SRA 数据获取驱动

NCBI SRA Toolkit 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑迁移自
`snakemake.smk/nanoseq.smk/nanoseq.sh/batch_prefetch.sh`（prefetch 下载）与
`batch_sra_to_fastq.sh` / `batch_sra_to_fastq_parallel.sh`（fastq-dump 转 FASTQ），
并补充官方推荐的高速版 fasterq-dump。

## 功能

三个子命令对应 bioconda sra-tools 包内的三个可执行：

| 子命令 | 可执行 | 作用 |
|--------|--------|------|
| `prefetch` | `prefetch` | SRA accession → 本地 .sra（nanoseq 默认 `-f yes -t http`） |
| `fasterq-dump` | `fasterq-dump` | .sra → FASTQ（官方推荐高速版，`-e` 线程 / `-t` 临时目录） |
| `fastq-dump` | `fastq-dump` | .sra → FASTQ（兼容旧版，nanoseq 脚本原用法 `--split-3 --gzip`） |

## 用法

```bash
# CLI 直跑
python main.py prefetch SRR12345678 -O sra/ --threads 2
python main.py fasterq-dump sra/SRR12345678/SRR12345678.sra -O fastq/ --threads 8
python main.py fastq-dump sra/SRR12345678/SRR12345678.sra --split-3 --gzip -O fastq/

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: sra-tools-native（含 prefetch/fasterq-dump/fastq-dump）
conda activate sra-tools-native
```

### 2. Docker

```bash
docker build -t bioskills/sra-tools:3.4.1-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/sra-tools:3.4.1-v1.0 prefetch SRR12345678 -O sra/
```

### 3. Apptainer / Singularity

```bash
apptainer build sra-tools.sif Apptainer.def
apptainer run -B $PWD:/data -H /data sra-tools.sif fastq-dump \
    /data/sra/SRR12345678/SRR12345678.sra --split-3 --gzip -O /data/fastq/
```

## 测试

```bash
bash test/run_test.sh   # prefetch/dump 需要网络 + 真实 SRA，本脚本退化为 argv 构造验证
```

## 版本

* sra-tools latest（示例 pin 3.4.1，bioconda；包内可执行 prefetch / fasterq-dump / fastq-dump）
* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（sra-tools 不在 Debian apt）
* 版本锚点对照：nf-core 子模块 pin sra-tools=3.2.1；snakemake-wrappers bio/sra-tools/fasterq-dump pin 3.4.1

## 历史留存（legacy/）

`legacy/` 存放迁移自 nanoseq 流程 `nanoseq.sh/` 的原始脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `batch_prefetch.sh`（prefetch 串行下载 SRR 列表）
- `batch_sra_to_fastq.sh`（fastq-dump 串行转 FASTQ）
- `batch_sra_to_fastq_parallel.sh`（fastq-dump + GNU parallel 并行转 FASTQ）


---

## snakemake 实现

# sra-tools / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/sra-tools` 目前只有 `fasterq-dump` 一个 wrapper，
因此本目录为 prefetch（下载）与 fastq-dump（兼容转换）提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `sra_tools.smk` — 三个 rule，对应 nanoseq 的 SRA 获取链路：
  - `sra_prefetch`：`prefetch -f yes -t http -O <dir> <srr_id>`（迁移自 batch_prefetch.sh）
  - `sra_fastq_dump`：`fastq-dump --split-3 --gzip -O <outdir> <sra>`（迁移自 batch_sra_to_fastq*.sh）
  - `sra_fasterq_dump`：`fasterq-dump <sra> --split-3 -O <outdir> -e N -t <tmpdir>`（官方推荐高速版）

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/`，去除 while 串行循环 / GNU parallel
外部依赖 / 绝对路径（`./sratoolkit.3.2.0-centos_linux64/bin/`）；失败 SRR 列表由
Snakemake 的重试/日志机制覆盖，不再写 `failed_*.txt`。

## 用法

```python
# Snakefile 中
include: "modules/sra-tools/snakemake/sra_tools.smk"

# 运行
snakemake -j 8 sra/SRR12345678/SRR12345678.sra       # prefetch 下载
snakemake -j 8 fastq/SRR12345678.fastq.gz            # fastq-dump 转换
```

## 依赖环境

```yaml
# envs/sra-tools.yaml
channels: [conda-forge, bioconda]
dependencies:
  - sra-tools=3.4.1
```

## 与其它实现的关系

- `fasterq-dump` 场景也可直接切到官方 wrapper：`wrapper: "v3.13.0/bio/sra-tools/fasterq-dump"`
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# sra-tools native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：sra-tools 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: sra-tools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - sra-tools=3.4.1    # 提供 prefetch / fasterq-dump / fastq-dump
  - pyyaml>=6.0
  - pip
```
