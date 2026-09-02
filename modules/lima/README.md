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

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: lima-native
conda activate lima-native
```

### 2. Docker

```bash
docker build -t bioskills/lima:2.9.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/lima:2.9.0-v1.0 lima reads.bam primers.fasta out/demux.bam --isoseq
```

### 3. Apptainer / Singularity

```bash
apptainer build lima.sif Apptainer.def
apptainer run -B $PWD:/data -H /data lima.sif \
    lima /data/reads.bam /data/primers.fasta /data/out/demux.bam --isoseq
```

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；lima 未安装时退化为 argv 构造验证
```

## 版本

- lima 2.9.0（bioconda::lima=2.9.0）
- 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（lima 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `lima_analysis.py`


---

## snakemake 实现

# lima / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/lima`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `lima.smk` — `rule lima`：reads + primers → 去引物/拆分后的 reads（bam/pbi/report/summary/counts）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/modules/lima/snakemake/lima.smk`，并去除对
`workflow/lib/helpers.py`（get_lima_input / docker_run / LIMA_DIR / LOG_DIR）的依赖：
- 输入路径模板：`ccs/{sample}/{sample}.chunk{n}.bam` + `primers.fasta`
- 输出：`lima/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.lima.report` / `.lima.summary` / `.lima.counts`
- 参数：`<bam> <primers> <out> [extra] -j {threads}`

## 用法

```python
# Snakefile 中
include: "modules/lima/snakemake/lima.smk"

# 运行
snakemake -j 8 lima/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/lima.yaml"`，需要自备：

```yaml
# envs/lima.yaml
channels: [conda-forge, bioconda]
dependencies:
  - lima=2.9.0
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/lima 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# lima native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：lima 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
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
