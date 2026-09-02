# dorado 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# dorado / native — 自包含 basecalling 驱动

Dorado（Oxford Nanopore 官方 basecaller）的本地自包含实现
（`source_type: custom`、`type: native`），命令逻辑提炼自
`snakemake.smk/nanoseq.smk/config/config.yaml` 的 `dorado` 段（`enable_dorado` 开关、
`model: rna004_130bps_sup@v5.1.0`、`docker_image: docker.1ms.run/nanoporetech/dorado:latest`）
与 dorado 官方 CLI 用法。nanoseq 流程中 dorado 为**可选**环节（`enable_dorado: false` 时跳过）。

## 功能

两个子命令覆盖 nanoseq / dorado 官方的高频用法：

| 子命令        | 命令                                                                                         | 作用                                                            |
| ---------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `basecall` | `dorado basecaller <model> <reads> --emit-fastq [--output-dir] [--device] [--num-workers]` | POD5/FAST5 原始信号 → FASTQ（RNA 用 `rna004_130bps_sup@v5.1.0` 等模型） |
| `demux`    | `dorado demux <reads> [--kit-name] [--output-dir]`                                         | 按 barcode 拆分 reads                                            |

nanoseq Snakefile 中的 dorado 规则（`dorado basecaller <model> <pod5> --estimate-poly-a > <fastq>`）
由 `basecall` 子命令 + `--estimate-poly-a`（经 `--extra-args` 透传）等价覆盖。

## 用法

```bash
# CLI 直跑
python main.py basecall rna004_130bps_sup@v5.1.0 pod5_dir/ --output-dir out --emit-fastq --threads 8
python main.py demux reads.fastq --kit-name SQK-RNA004-24 --output-dir demux_out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: dorado-native（仅 python 驱动；dorado 二进制需单独下载）
# dorado 官方二进制（不在 bioconda）：
curl -Ls https://cdn.oxfordnanoportal.com/software/analysis/dorado-<ver>-linux-x64.tar.gz | tar -xz
export PATH=$PWD/dorado-<ver>-linux-x64/bin:$PATH
```

### 2. Docker

```bash
docker build -t bioskills/dorado:latest-v1.0 -f Dockerfile .   # --build-arg DORADO_VERSION=<release> 可 pin
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/dorado:latest-v1.0 basecall \
    rna004_130bps_sup@v5.1.0 pod5/ --output-dir out --emit-fastq
# 建议挂载模型缓存目录（dorado 首次运行会自动下载模型，体积较大）
```

### 3. Apptainer / Singularity

```bash
apptainer build dorado.sif Apptainer.def
apptainer run -B $PWD:/data -H /data dorado.sif basecall \
    rna004_130bps_sup@v5.1.0 /data/pod5/ --output-dir /data/out --emit-fastq
```

## 测试

```bash
bash test/run_test.sh   # dorado basecaller 需要真实 POD5 + 模型，本脚本退化为 argv 构造验证
```

## 版本

* dorado：latest（官方 release，如 0.9.x / 0.10.x；Dockerfile 用 `ARG DORADO_VERSION` 可 pin）

* 不在 Debian bookworm apt、不在 bioconda；容器走 bookworm-slim + 官方二进制下载路线

* Docker 直用建议：`docker.1ms.run/nanoporetech/dorado:latest`（nanoseq config 默认）

## 历史留存（legacy/）

nanoseq 流程中 dorado **无 shell 脚本**（`nanoseq.sh/` 下没有 dorado 脚本），只有
`config/config.yaml` 的 dorado 配置段，因此 `legacy/` 目录以 README 记录该 config 段原文，
不做脚本留存。dorado 的 native 命令逻辑按 config 默认值 + 官方 CLI 在 `main.py` 实现。

* `legacy/README.md`（config 段说明）


## 历史说明（来自原 legacy/README.md）

nanoseq 流程中 dorado 无 shell 脚本（nanoseq.sh/ 下没有 dorado 脚本），
仅通过 config 的 dorado 段配置 basecall 参数；native 实现见 main.py 的 basecall 子命令。


---

## snakemake 实现

# dorado / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/dorado`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `dorado.smk` — 两个 rule，对应 nanoseq 的 dorado 环节 + dorado 官方用法：
  - `dorado_basecall`：`dorado basecaller <model> <pod5> --estimate-poly-a > <fastq>`（迁移自 nanoseq Snakefile 的 `DORADO_FAST5_TO_FASTQ`）
  - `dorado_demux`：`dorado demux <fastq> --kit-name <kit> --output-dir <dir>`（barcode 拆分，可选）

规则迁移自 `snakemake.smk/nanoseq.smk/workflow/Snakefile`，保留 `enable_dorado` 开关语义
（`config["enable_dorado"]` 为 false 时 rule all 不收集输出，整条链路跳过）；`model` /
`docker_image` 走 `config.get("dorado", {...})` 内联默认值（`rna004_130bps_sup@v5.1.0` /
`docker.1ms.run/nanoporetech/dorado:latest`）。

## 用法

```python
# Snakefile 中（需先定义 SAMPLES 与 config）
include: "modules/dorado/snakemake/dorado.smk"

# 运行（enable_dorado: true 时）
snakemake -j 8 01_DORADO_BASECALL/sample1.fastq
```

## 依赖环境

dorado **不在 bioconda**，rule 内用 `container` 而非 `conda`：

```yaml
# config.yaml 建议
enable_dorado: true
dorado:
  docker_image: "docker.1ms.run/nanoporetech/dorado:latest"
  model: "rna004_130bps_sup@v5.1.0"
  exec_mode: "docker"
```

首次运行 dorado 会自动下载模型（体积较大），建议挂载 `~/.cache/dorado` 复用。

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/dorado 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# dorado native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：dorado 不在 Debian apt、不在 bioconda；官方只提供静态二进制（Linux x64）。
#      本文件仅安装 python 驱动依赖（pyyaml）；dorado 二进制需单独下载：
#        curl -Ls https://cdn.oxfordnanoportal.com/software/analysis/dorado-<ver>-linux-x64.tar.gz | tar -xz
#        export PATH=$PWD/dorado-<ver>-linux-x64/bin:$PATH
#      容器默认路线：Dockerfile / Apptainer.def 走「apt 运行时 + 官方二进制下载」。
name: dorado-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - pyyaml>=6.0
  - pip
```
