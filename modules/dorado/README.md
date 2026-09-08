# dorado 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# dorado / native — 自包含 basecalling 驱动

Dorado（Oxford Nanopore 官方 basecaller）的本地自包含实现
（`source_type: custom`、`type: native`），命令逻辑覆盖 `dorado` 配置段语义
（`enable_dorado` 开关、`model: rna004_130bps_sup@v5.1.0`、
`docker_image: docker.1ms.run/nanoporetech/dorado:latest`）
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

## 环境安装（官方镜像优先，不维护本地配方）

官方说明：dorado 不在 Debian bookworm apt、也不在 bioconda（2026-09 抓 `anaconda.org/bioconda/dorado` 404）；官方只发布
静态二进制与官方 Docker 镜像（`nanoporetech/dorado`）。第三方频道仅陈旧版（YangmingSi `dorado=1.3.0`、HCC `dorado=0.7.2`），
不建议作安装源。`native/` 保留自建容器配方（Dockerfile / Apptainer.def，amd64；bookworm-slim + 官方二进制下载，默认
`DORADO_VERSION=2.1.2`）。

### 1. Conda / brew（包管理器安装）

```bash
# dorado 无 bioconda 包（第三方频道版本陈旧：YangmingSi 1.3.0 / HCC 0.7.2）；conda 环境仅装 native/main.py 驱动依赖
mamba create -n dorado-native -c conda-forge python=3.11 "pyyaml>=6.0" pip   # 或文末「Conda 环境」配方另存为 yml 离线使用
# dorado 二进制单独下载，见下方「### 4. 二进制包安装」
```

> brew 两源（homebrew-core / brewsci-bio）均无 dorado 公式（2026-09 核实 404），README 不登记 Homebrew 安装块。

### 2. Docker（官方镜像 / 自建）

```bash
# 官方镜像（nanoseq config 默认走国内加速通道）
docker pull docker.1ms.run/nanoporetech/dorado:latest        # 或 docker pull nanoporetech/dorado:latest
# 自建（可选，amd64）：默认 DORADO_VERSION=2.1.2，可 --build-arg 覆盖
docker build -t bioskills/dorado:2.1.2 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/dorado:2.1.2 basecaller \
    rna004_130bps_sup@v5.1.0 pod5/ --output-dir out --emit-fastq
# 建议挂载模型缓存目录（dorado 首次运行会自动下载模型，体积较大）
```

### 3. Apptainer / Singularity

dorado 无官方 biocontainer sif（不在 bioconda / depot.galaxyproject.org）→ 用本目录 `Apptainer.def` 自建：

```bash
apptainer build dorado.sif Apptainer.def
apptainer run -B $PWD:/data -H /data dorado.sif basecaller \
    rna004_130bps_sup@v5.1.0 /data/pod5/ --output-dir /data/out --emit-fastq
```

### 4. 二进制包安装（官方 release）

```bash
# 官方 release（GitHub 发布页 → cdn.oxfordnanoportal.com 直链）
mkdir -p ~/software && cd ~/software
wget https://cdn.oxfordnanoportal.com/software/analysis/dorado-2.1.2-linux-x64.tar.gz
tar zxf dorado-2.1.2-linux-x64.tar.gz
echo 'export PATH=$PATH:~/software/dorado-2.1.2-linux-x64/bin' >> ~/.bashrc
source ~/.bashrc

# 验证安装
dorado --version   # 断言 2.1.2
```

> native/main.py 驱动在宿主机运行（python）；dorado 二进制按上装好并在 PATH 即可被 `main.py`/`snakemake` 调用。

## 测试

```bash
bash test/run_test.sh   # dorado basecaller 需要真实 POD5 + 模型，本脚本退化为 argv 构造验证
```

## 版本

* dorado：2.1.2（官方最新，2026-08-26 发布；meta `software_versions.native` 对齐；macOS/Linux 均有二进制，含 CUDA 版 CUDA libs）

* 不在 Debian bookworm apt、不在 bioconda（YangmingSi/HCC 频道仅陈旧版）；官方只发布静态二进制；容器走 bookworm-slim + 官方二进制下载路线（自建配方仅 amd64）

* Docker 直用建议：`docker.1ms.run/nanoporetech/dorado:latest`（nanoseq config 默认；官方镜像渠道备选 `quay.io/bioinfortools/dorado:1.3.0` 已停更）

## 历史留存

nanoseq 流程中 dorado **无独立 shell 脚本**，basecall/demux 参数由流程 `config.yaml` 的 dorado 段配置；
dorado 的 native 命令逻辑按配置默认值 + 官方 CLI 在 `main.py` 实现。


---

## snakemake 实现

# dorado / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/dorado`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。
td2 式：每 rule 一个 config 驱动 `.smk`（无 conda env——dorado 不在 bioconda，
docker 模式走 rule `container` + `--use-container`，native 走 PATH 二进制）。

## 规则文件

- `dorado_basecall.smk` — `rule dorado_basecall`（POD5/FAST5 → FASTQ）：
  `dorado basecaller <model> <pod5> --estimate-poly-a > <fastq>`（nanoseq `DORADO_FAST5_TO_FASTQ` 等价）
- `dorado_demux.smk` — `rule dorado_demux`（FASTQ → 按 barcode 拆分目录）：
  `dorado demux <fastq> --kit-name <kit> --output-dir <dir>`（barcode 拆分，可选）

两规则均为 config 驱动、不依赖 workflow 的 `SAMPLES` / config 层级；`model` / `docker_image`
走 `config.setdefault("dorado", ...)` 内联默认值（`rna004_130bps_sup@v5.1.0` /
`docker.1ms.run/nanoporetech/dorado:latest`）。

## 用法（config 契约见各 .smk 头注与软件级 meta.yaml `snakemake_include_hint`）

```python
# Snakefile 中
include: "modules/dorado/snakemake/dorado_basecall.smk"
include: "modules/dorado/snakemake/dorado_demux.smk"   # 可选（demux 环节）

rule all:
    input: [config["dorado_fastq"], config["dorado_demux_outdir"]]   # 按需收集
```

```bash
# 独立运行（native；dorado 二进制需在 PATH）
snakemake -s modules/dorado/snakemake/dorado_basecall.smk \
    --config dorado_input_pod5=pod5/ dorado_fastq=basecall.fastq --cores 8
# docker 模式
snakemake -s modules/dorado/snakemake/dorado_basecall.smk \
    --config exec_mode=docker dorado_input_pod5=pod5/ dorado_fastq=basecall.fastq \
    --cores 8 --use-container
```

## 依赖环境

dorado **不在 bioconda**，无同目录 conda env；docker 模式需本机 docker + `--use-container`：

```yaml
# config.yaml 建议
exec_mode: "docker"
dorado:
  docker_image: "docker.1ms.run/nanoporetech/dorado:latest"
  model: "rna004_130bps_sup@v5.1.0"
```

首次运行 dorado 会自动下载模型（体积较大），建议挂载 `~/.cache/dorado` 复用。

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/dorado 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# dorado native Conda 环境配方
# 离线兜底：可另存为 dorado-native.yml 后 mamba env create -f dorado-native.yml；在线推荐上方 mamba create 直装命令
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
