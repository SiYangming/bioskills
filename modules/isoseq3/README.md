# isoseq3 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# isoseq3 / native — 自包含 isoseq3 refine 驱动

PacBio **IsoSeq3 refine**（去 polyA 尾与人工连接体）的本地自包含实现
（`source_type: custom`、`type: native`）。
> ⚠️ 命名差异：bioconda 包名为 **`isoseq`**，可执行二进制为 **`isoseq3`**
> （PacBio IsoSeq 套件入口，内含 refine / cluster / polish 等子命令）。本技能聚焦 `refine`。

## 功能

- `isoseq3 refine <bam> <primers> <out.bam>`：lima 产物 → 精炼 reads（polyA 修剪、去连接体）
- 默认 `--require-polya`（可用 `--no-require-polya` 关闭）
- `--min-polya-length`：polyA 尾最小长度
- 自动注入线程（`-j`，与 `--num-threads` 等价）
- 报告：`.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv` / `.pbi`（与输出同前缀）

## 用法

```bash
# CLI 直跑
python main.py refine --bam in.bam --primers primers.fasta --outdir out --prefix sample --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `refine` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: isoseq3-native
conda activate isoseq3-native
```

### 2. Docker

```bash
docker build -t bioskills/isoseq3:4.0.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/isoseq3:4.0.0-v1.0 refine --bam in.bam --primers primers.fasta --outdir out
```

### 3. Apptainer / Singularity

```bash
apptainer build isoseq3.sif Apptainer.def
apptainer run -B $PWD:/data -H /data isoseq3.sif \
    refine --bam /data/in.bam --primers /data/primers.fasta --outdir /data/out
```

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；isoseq3 未安装时退化为 argv 构造验证
```

## 版本

- isoseq 4.0.0（bioconda::isoseq=4.0.0，binary `isoseq3`）
- 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（isoseq 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `isoseq3_refine.py`


---

## snakemake 实现

# isoseq3 / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/isoseq3`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

* `isoseq3.smk` — `rule isoseq3_refine`：lima 产物 → 精炼 reads（去 polyA 尾与人工连接体）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/modules/isoseq3/snakemake/isoseq3.smk`，并去除对
`workflow/lib/helpers.py`（get\_isoseq\_input\_bam / docker\_run / ISOSEQ\_DIR / LOG\_DIR）的依赖：

* 输入路径模板：`lima/{sample}/{sample}.chunk{n}.bam` + `primers.fasta`

* 输出：`isoseq3/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv`

* 参数：`isoseq3 refine -j {threads} [--require-polya] <bam> <primers> <out>`

## 用法

```python
# Snakefile 中
include: "modules/isoseq3/snakemake/isoseq3.smk"

# 运行
snakemake -j 8 isoseq3/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/isoseq3.yaml"`，需要自备：

```yaml
# envs/isoseq3.yaml
channels: [conda-forge, bioconda]
dependencies:
  - isoseq=4.0.0     # 提供二进制 isoseq3
```

## 与其它实现的关系

* 官方 wrapper 若未来出现（重新抓取 bio/isoseq3 有目录），可切换回 `../snakemake-wrappers/` 登记层

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`



---

## Conda 环境（原 native/environment.yml）

```yaml
# isoseq3 native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：isoseq（PacBio IsoSeq 套件，binary isoseq3）不在 Debian bookworm apt；
#      本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: isoseq3-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - isoseq=4.0.0       # 提供二进制 isoseq3
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/isoseq3/overview
- **Docker**：`docker pull quay.io/biocontainers/isoseq3:4.0.0--h9ee0642_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/isoseq3%3A4.0.0--h9ee0642_0
- 安装方式（本地）：`mamba create -n isoseq3 -c conda-forge -c bioconda isoseq3=4.0.0`
