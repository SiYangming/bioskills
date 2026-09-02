# pbccs 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# pbccs / native — 自包含 ccs 驱动

PacBio **CCS（HiFi）一致性序列生成**的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包名为 `pbccs`，可执行二进制为 **`ccs`**。

## 功能

* `ccs <subreads.bam> <out.bam>`：subreads BAM → HiFi/CCS BAM

* 分块并行：`--chunk N/TOTAL`（大型样本按 ZMW 分块，可多机并行）

* 过滤阈值：`--min-rq --min-passes --min-snr --min-length --max-length --top-passes`

* 报告：`--report-file --report-json --metrics-json`（与输出同前缀自动生成）

* 自动注入线程（`-j`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py ccs --subreads sample.subreads.bam --outdir out --chunk-num 1 --chunk-total 4 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `ccs` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: pbccs-native
conda activate pbccs-native
```

### 2. Docker

```bash
docker build -t bioskills/pbccs:6.4.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/pbccs:6.4.0-v1.0 ccs --subreads sample.subreads.bam --outdir out --chunk-num 1 --chunk-total 1
```

### 3. Apptainer / Singularity

```bash
apptainer build pbccs.sif Apptainer.def
apptainer run -B $PWD:/data -H /data pbccs.sif \
    ccs --subreads /data/sample.subreads.bam --outdir /data/out --chunk-num 1 --chunk-total 1
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 subreads BAM；ccs 未安装时退化为 argv 构造验证
```

## 版本

* pbccs 6.4.0（bioconda::pbccs=6.4.0，二进制 `ccs`）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（pbccs 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `ccs_analysis.py`


---

## snakemake 实现

# pbccs / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/pbccs`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `pbccs.smk` — `rule pbccs`：subreads BAM → HiFi/CCS BAM（含 chunk 分块与过滤阈值）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/modules/pbccs/snakemake/pbccs.smk`，并去除对
`workflow/lib/helpers.py`（sample_to_bam / docker_run / LOG_DIR）的依赖：
- 输入路径模板：`subreads/{sample}.subreads.bam`
- 输出：`ccs/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.report.txt` / `.report.json` / `.metrics.json.gz`
- 参数：`--chunk {n}/{chunk_total}` + `--min-rq/--min-passes/--min-snr/--min-length/--max-length/--top-passes` + `-j {threads}`

## 用法

```python
# Snakefile 中
include: "modules/pbccs/snakemake/pbccs.smk"

# 运行（n 为分块编号通配符，如 1..4）
snakemake -j 8 ccs/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/pbccs.yaml"`，需要自备：

```yaml
# envs/pbccs.yaml
channels: [conda-forge, bioconda]
dependencies:
  - pbccs=6.4.0
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/pbccs 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# pbccs native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：pbccs 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: pbccs-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - pbccs=6.4.0        # 提供二进制 ccs
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/pbccs/overview
- **Docker**：`docker pull quay.io/biocontainers/pbccs:6.4.0--h9ee0642_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/pbccs%3A6.4.0--h9ee0642_0
- 安装方式（本地）：`mamba create -n pbccs -c conda-forge -c bioconda pbccs=6.4.0`
