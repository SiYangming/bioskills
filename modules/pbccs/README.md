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
mamba create -n pbccs-native -c conda-forge -c bioconda pbccs=6.4.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate pbccs-native
```

### 2. Docker（官方镜像直拉，不维护本地 Dockerfile）

```bash
docker pull quay.io/biocontainers/pbccs:<tag>        # tag 见 quay 页面（或文末「容器与 Conda 链接」）
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data quay.io/biocontainers/pbccs:<tag> \
    ccs -j 8 /data/sample.subreads.bam /data/sample.ccs.bam
```

### 3. Apptainer / Singularity（官方镜像直拉，不维护本地 Apptainer.def）

```bash
apptainer pull pbccs.sif docker://quay.io/biocontainers/pbccs:<tag>
# 或直链 depot.galaxyproject.org/singularity/pbccs%3A<tag>（与 quay 同 build tag）
apptainer run -B $PWD:/data -H /data pbccs.sif \
    ccs -j 8 /data/sample.subreads.bam /data/sample.ccs.bam
```

> 官方镜像内为原生 ccs 入口（仅工具，无 main.py；分块 `--chunk N/TOTAL` 由 main.py 的 `--chunk-num/--chunk-total` 转换）；
> 需要 Schema/自省/参数注入时在**宿主机**（已装 pbccs 或 conda env）运行 `python main.py ccs ...`。

## 测试

```bash
bash test/run_test.sh   # 无需真实 subreads BAM；ccs 未安装时退化为 argv 构造验证
```

## 版本

* pbccs 6.4.0（bioconda::pbccs=6.4.0，二进制 `ccs`；由官方镜像/conda 提供：quay.io/biocontainers/pbccs、bioconda pbccs=6.4.0）

* 构建路线：official biocontainer（quay.io/biocontainers/pbccs / depot.galaxyproject.org）；本地不再自建容器

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为 `main.py`**。

- `ccs_analysis.py`


---

## snakemake 实现

# pbccs / snakemake / local — 自维护 Snakemake 规则（td2 式：每 rule 一个 config 驱动 .smk）

官方 `snakemake-wrappers` 无 `bio/pbccs`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

### 本地拆分规则（td2 式：每 rule 一个 .smk，config 驱动）

| 文件 | 规则 | 作用 | 执行指令 |
|------|------|------|----------|
| `snakemake/pbccs.smk` | `pbccs` | subreads BAM → 单块 HiFi/CCS BAM（`--chunk {chunk}/{chunk_total}` + 报告/阈值）；块号由输出目标 `{chunk}` 通配符驱动（1..chunk_total，`chunk_total=1` 即不分块） | `script:`（pbccs.py） |

- 配套文件（平铺 `snakemake/`，`.smk` 同目录相对引用）：`pbccs.yaml`（conda env：`bioconda::pbccs=6.4.0`）、`pbccs.py`（wrapper）。
- 规则 **config 驱动、可独立运行**（不依赖流程 `SAMPLES` / `{sample}` 目录层级；样本名取自 `pbccs_subreads` 文件名去 `.subreads`），契约见 `.smk` 头注。要点：
  - `pbccs_subreads`（必填输入）/ `pbccs_outdir`（默认 `ccs_out`，`<sample>.chunk{n}.bam/.pbi/.report.txt/.report.json/.metrics.json.gz` 平铺其下）/ `pbccs_chunk_total`（默认 4）/ `threads`（默认 8）/ `exec_mode`（默认 conda）
  - 嵌套 `pbccs.*`：`min_rq=0.9`、`min_passes=3`、`min_snr=2.5`、`min_length=10`、`max_length=50000`、`top_passes=60`、`ccs_extra_params`、`docker_image`（docker 模式）、`ccs_bin`（native 模式，默认 `ccs`）（CLI 点号写法，如 `'pbccs.min_rq=0.95'`）
- 独立运行示例：
  ```bash
  snakemake -s modules/pbccs/snakemake/pbccs.smk \
      --config pbccs_subreads=sample.subreads.bam pbccs_outdir=ccs_out pbccs_chunk_total=2 \
      --cores 8 --use-conda \
      ccs_out/sample.chunk1.bam ccs_out/sample.chunk2.bam
  ```
- 流程内使用：include 后对 1..chunk_total 展开全部块目标即可并行调度（多块互不依赖，各跑一个 `ccs --chunk n/total`）：
  ```python
  # Snakefile 中
  include: "modules/pbccs/snakemake/pbccs.smk"
  # rule all:
  #     input: [os.path.join(config["pbccs_outdir"], f"{sample}.chunk{n}.bam")
  #             for n in range(1, config["pbccs_chunk_total"] + 1)]   # sample 自行替换
  ```
- 执行指令说明：ccs 单块为**单条命令、无额外逻辑**（mkdir 仅建目录）→ 同目录 wrapper `pbccs.py`
  （docker/native/conda 三模式经共享 `modules/docker_wrapper.py` 的 `docker_wrapper_binary(config, "pbccs",
  "ccs_bin", "ccs")` 分派；参考 `modules/samtools/snakemake/samtools_sort.py`）。`exec_mode` 默认 conda，
  docker/native 需在 config.yaml 预设 `pbccs.docker_image` / `pbccs.ccs_bin`。
- 规则按上述单文件拆分（config 驱动），不依赖 workflow 级 `envs/pbccs.yaml` 与 `logs/` 约定；无 `envs/` / `logs/` 幽灵引用。

### 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/pbccs 有目录），可切换回 snakemake-wrappers 登记层（见 `meta.yaml` / `software_versions`）
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `native/`


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# pbccs native Conda 环境配方
# 离线兜底：可另存为 pbccs-native.yml 后 mamba env create -f pbccs-native.yml；在线推荐上方 mamba create 直装命令
# 说明：pbccs 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：官方镜像优先（quay.io/biocontainers/pbccs），不再维护 Dockerfile/Apptainer.def。
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
