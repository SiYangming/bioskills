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

## 实战示例：Iso-Seq 全长转录本流程中的 refine（lima 产物 → FLNC reads）

IsoSeq3 是 PacBio 官方提供的全长转录本（Iso-Seq）分析工具，用于分析 PacBio 长读长测序获得的全长转录本序列；完整流程为 ccs → lima → refine → cluster → polish 五步：ccs 将 subreads 聚合成高准确率共识序列，lima 去除测序引物与 barcode，refine 去除 polyA 尾和嵌合体序列、得到全长非嵌合（FLNC）reads，cluster 将相似的 FLNC reads 聚类生成全长转录本序列，polish 再用 subreads 对转录本序列进行修正、提高序列准确性（本模块聚焦 refine 一步，等价能力见上「用法」的 `refine` 子命令）：

```
subreads.bam → ccs → ccs.bam → lima → lima.bam → refine → flnc.bam → cluster → unpolished.bam → polish → polished.bam
```

### 1. refine 去除 polyA 尾与人工连接体

lima 按引物对拆分后每个片段各一个 BAM，refine 可一次通配传入（`*lima*.bam`），去除 polyA 尾与人工连接体，得到全长非嵌合（FLNC）reads：

```bash
isoseq3 refine sample*lima*.bam barcoded_primers.fasta sample.flnc.bam --require-polya
```

- 输入：lima 拆分产物 BAM（可多个）+ 引物 FASTA（与 lima 同款）
- 输出：`sample.flnc.bam`（及同前缀 `.pbi` / `.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv`，见上「功能」）
- `--require-polya`：仅保留检测到 polyA 尾的 reads（本模块默认开启）

### 2. 后续 cluster / polish（同属 isoseq3 套件，refine 的典型下游）

FLNC reads 经聚类生成全长转录本序列，再用原始 subreads 校正：

```bash
# 对 FLNC reads 聚类，得到全长转录本序列信息
isoseq3 cluster sample.flnc.bam unpolished.bam --verbose

# 用 subreads 对转录本序列进行修正，提高序列准确性
isoseq3 polish unpolished.bam sample.subreads.bam polished.bam
```

> cluster / polish 为 isoseq3 套件的其余子命令，不在本模块 `native/main.py` 的 refine 子命令范围内；refine 产物（FLNC BAM）可直接作为其输入。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda（宿主机直跑 main.py / HPC 无 root）

```bash
mamba create -n isoseq3-native -c conda-forge -c bioconda isoseq=4.0.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate isoseq3-native
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/isoseq3:4.0.0--h9ee0642_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/isoseq3:4.0.0--h9ee0642_0 isoseq3 refine -j 8 \
    /data/in.bam /data/primers.fasta /data/out.bam
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull isoseq3.sif docker://depot.galaxyproject.org/singularity/isoseq3:4.0.0--h9ee0642_0
apptainer run -B $PWD:/data -H /data isoseq3.sif isoseq3 refine -j 8 \
    /data/in.bam /data/primers.fasta /data/out.bam
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

isoseq3 属 PacBio IsoSeq 套件（conda 包名 isoseq，二进制 isoseq3），官方以 **conda（bioconda）为主要分发**，GitHub release 亦提供预编译二进制：

* **官方 GitHub**：<https://github.com/PacificBiosciences/IsoSeq>（release 附预编译二进制）

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/isoseq3/overview>

```bash
# conda 安装（官方推荐分发；包名 isoseq，提供二进制 isoseq3）
mamba create -n isoseq3 -c conda-forge -c bioconda isoseq=4.0.0
conda activate isoseq3
isoseq3 refine --help   # 验证安装
```

> 官方镜像/conda 包内为原生 isoseq3 入口（仅工具，无 main.py）；需要 Schema/自省/参数注入时在**宿主机**（conda env，见上）运行 `python main.py refine ...`（见「用法」）。

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；isoseq3 未安装时退化为 argv 构造验证
```

## 版本

- isoseq 4.0.0（bioconda::isoseq=4.0.0，binary `isoseq3`；由官方镜像/conda 提供，宿主机安装用 mamba/conda）
- 构建路线：official biocontainer（quay.io/biocontainers/isoseq3 / depot.galaxyproject.org，tag 见文末「容器与 Conda 链接」）；本地不再自建容器

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为 `main.py`**。

- `isoseq3_refine.py`


---

## snakemake 实现

# isoseq3 / snakemake / local — 自维护 Snakemake 规则（td2 式：每 rule 一个 config 驱动 .smk）

官方 `snakemake-wrappers` 无 `bio/isoseq3`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

### 本地拆分规则（td2 式：每 rule 一个 .smk，config 驱动）

| 文件 | 规则 | 作用 | 执行指令 |
|------|------|------|----------|
| `snakemake/isoseq3_refine.smk` | `isoseq3_refine` | lima 产物 BAM → 精炼 reads（去 polyA 尾与人工连接体；产物 `.bam` / `.pbi` / `.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv` 同前缀平铺） | `script:`（isoseq3_refine.py） |

- 配套文件（平铺 `snakemake/`，`.smk` 同目录相对引用）：`isoseq3.yaml`（conda env：`bioconda::isoseq=4.0.0`，提供二进制 `isoseq3`）、`isoseq3_refine.py`（wrapper）。
- 规则 **config 驱动、可独立运行**（不依赖流程 `SAMPLES` / `{sample}` 目录层级；输出前缀取自 `isoseq3_input_bam` 文件名去 `.bam`，可用 `isoseq3_prefix` 覆盖），契约见 `.smk` 头注。要点：
  - `isoseq3_input_bam`（必填输入）/ `isoseq3_primers`（必填引物 FASTA）/ `isoseq3_outdir`（默认 `isoseq3_out`）/ `isoseq3_prefix` / `threads`（默认 8）/ `exec_mode`（默认 conda）
  - 嵌套 `isoseq3.*`：`require_polya=true`（默认开启 → `--require-polya`）、`min_polya_length`（默认空 → 不传 `--min-polya-length`）、`extra_args`（透传）、`docker_image`（docker 模式）、`isoseq3_bin`（native 模式，默认 `isoseq3`）
- 独立运行示例：
  ```bash
  snakemake -s modules/isoseq3/snakemake/isoseq3_refine.smk \
      --config isoseq3_input_bam=lima/s1/s1.chunk1.bam isoseq3_primers=primers.fasta \
      --cores 8 --use-conda
  ```
- 流程内使用（输入为 lima 产物，可与 `pbccs` / lima 规则串联；单样本规则对每块输入各跑一次 refine）：
  ```python
  # Snakefile 中
  include: "modules/isoseq3/snakemake/isoseq3_refine.smk"
  # rule all:
  #     input: "isoseq3_out/s1.chunk1.bam"   # = <isoseq3_outdir>/<prefix>.bam（prefix 默认取 bam 名）
  ```
- 执行指令说明：refine 为**单条命令、无额外逻辑**（mkdir 仅建目录）→ 同目录 wrapper `isoseq3_refine.py`
  （docker/native/conda 三模式经共享 `modules/docker_wrapper.py` 的 `docker_wrapper_binary(config,
  "isoseq3", "isoseq3_bin", "isoseq3")` 分派）。`exec_mode` 默认 conda，docker/native 需在
  config.yaml 预设 `isoseq3.docker_image` / `isoseq3.isoseq3_bin`。
- 规则按上述单文件拆分（config 驱动），不依赖 workflow 级 `envs/isoseq3.yaml` 与 `lima/{sample}/`、`logs/` 约定；无 `envs/` / `logs/` 幽灵引用。

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/isoseq3 有目录），可切换回 snakemake-wrappers 登记层（见 `meta.yaml` / `software_versions`）
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`



---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# isoseq3 native Conda 环境配方
# 离线兜底：可另存为 isoseq3-native.yml 后 mamba env create -f isoseq3-native.yml；在线推荐上方 mamba create 直装命令
# 说明：isoseq（PacBio IsoSeq 套件，binary isoseq3）不在 Debian bookworm apt；
#      本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：官方镜像优先（quay.io/biocontainers/isoseq3），不再维护 Dockerfile/Apptainer.def。
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
- 安装方式（本地）：`mamba create -n isoseq3 -c conda-forge -c bioconda isoseq=4.0.0`（包名 isoseq，提供二进制 isoseq3）
