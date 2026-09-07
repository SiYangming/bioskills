# orffinder 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# orffinder / native — 自包含 ORF 预测驱动

**ORFfinder**（NCBI 开放阅读框查找工具，本地版）的自包含实现（`source_type: custom`、`type: native`）。
conda 包 `orffinder=0.4.3` 提供二进制 **`ORFfinder`**（来自 NCBI；对应容器
`quay.io/preskaa/orffinder:0.4.3`）。

## 功能

* `run`：在核酸序列中查找 ORF 并输出蛋白翻译

  `ORFfinder -in <fasta> -out <file> -outfmt <int> [-g <code>] [-s <0|1|2>] [-ml <nt>] [-strand <both|plus|minus>] [-n]`

* 输出格式（`-outfmt`；输出后缀映射见下）：
  - `0` → ORFs FASTA（后缀 `_orf.fa`）
  - `1` → CDS FASTA（后缀 `_cds.fa`）
  - `2` → Text ASN.1（后缀 `.asn1`，默认）
  - `3` → Feature table（后缀 `.ft`）

* 自动解压 `.gz` 输入、自动生成默认输出路径、注入 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py run -in transcripts.fa -out out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `run` 支持 `--threads` / `--tmpdir` 运行期覆盖（ORFfinder 单线程，线程数仅调度参考）。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: orffinder-native（orffinder=0.4.3）
conda activate orffinder-native
```

### 2. Docker

官方（作者组织）镜像直拉即可，无需本地构建（2026-09 核实 tag 存在）：

```bash
docker pull quay.io/preskaa/orffinder:0.4.3
# preskaa 镜像直接以 ORFfinder 二进制运行（无本仓库 main.py 驱动）：
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/preskaa/orffinder:0.4.3 \
    ORFfinder -in transcripts.fa -out out/result.asn1 -outfmt 2 -start 2 -minlen 30
```

需要 main.py 统一驱动（自省/Schema/run 子命令）时再用本地自建镜像（可选，见 native/Dockerfile）：

```bash
cd native && docker build -t bioskills/orffinder:0.4.3-v1.0 -f Dockerfile . && cd ..
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/orffinder:0.4.3-v1.0 \
    run -in transcripts.fa -out out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30
```

### 3. Apptainer / Singularity

```bash
apptainer build orffinder.sif Apptainer.def
apptainer run -B $PWD:/data -H /data orffinder.sif \
    run -in /data/transcripts.fa -out /data/out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30
```

## 测试

```bash
bash test/run_test.sh   # 无需真实核酸序列；工具未装时退化为 argv 构造验证
```

## 版本

* orffinder 0.4.3（bioconda orffinder=0.4.3 / quay.io/preskaa/orffinder:0.4.3，二进制 ORFfinder 来自 NCBI）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（orffinder 不在 Debian apt）

## 历史留存

供追溯对照的 Snakemake wrapper 脚本存放于 `snakemake/`（wrapper 平铺同目录，规则直接使用），**正式入口为 `main.py`**。

- `orffinder.py` — ORFfinder wrapper（snakemake.shell + docker_wrapper）


---

## snakemake 实现

# orffinder / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/orffinder`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `orffinder.smk` — `rule orffinder`：核酸 FASTA → ORF 预测结果（td2 式 config 驱动单规则）
- `orffinder.py` — 规则配套 wrapper（同目录；两级 sys.path 注入 + docker_wrapper 三模式解析）
- `orffinder.yaml` — conda 环境（`orffinder=0.4.3`）

输入/输出/参数全部由 config 驱动，不依赖 Snakefile 顶部的 `SAMPLES` / `{sample}` 层级：
- 输入：`orffinder_input_fasta`（明文或 `.gz`，wrapper 自动解压）
- 输出：`<orffinder_outdir>/<fasta_stem><suffix>`；suffix 依 `orffinder.outfmt`（默认 2 → `.asn1`；suffix_map：0=`_orf.fa`, 1=`_cds.fa`, 2=`.asn1`, 3=`.ft`）
- 透传：`orffinder.extra_params`（如 `"-s 2 -ml 30"`：起始密码子=任意有义密码子，最小 ORF 长度=30 nt）

## 用法

```bash
# 独立运行（默认 outfmt=2 -> <outdir>/transcripts.asn1）
snakemake -s modules/orffinder/snakemake/orffinder.smk \
    --config orffinder_input_fasta=transcripts.fa orffinder_outdir=orffinder_out \
    --cores 4 --use-conda

# 流程内使用
include: "modules/orffinder/snakemake/orffinder.smk"
```

改输出格式时，用 `--config "orffinder={outfmt: 3}"` 覆盖，并注意 output 目标名后缀（见 suffix_map）。

## 依赖环境

规则内 `conda: "orffinder.yaml"`（同目录；snakemake 以 `.smk` 所在目录为基准解析）：

```yaml
# snakemake/orffinder.yaml
channels: [yangmingsi, bioconda, conda-forge]
dependencies:
  - orffinder=0.4.3
```

## 与其它实现的关系

- 官方 wrapper 当前不存在（`../snakemake-wrappers/` 登记层注明 bio/orffinder 404）；若未来出现可切换
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# orffinder native Conda 环境配方（native/environment.yml；与 snakemake/orffinder.yaml 频道一致）
# 离线兜底：可另存为 orffinder-native.yml 后 mamba env create -f orffinder-native.yml；在线推荐上方 mamba create 直装命令
# 说明：orffinder 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      orffinder=0.4.3 由 YangmingSi 自建频道提供（裸 ORFfinder 二进制，配方 native/conda-recipe/meta.yaml，
#      NCBI 官方二进制 + libuv/libnghttp2 依赖）；python/pyyaml 供 main.py 驱动（自省/Schema）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: orffinder-native
channels:
  - yangmingsi
  - bioconda
  - conda-forge
dependencies:
  - python=3.11
  - orffinder=0.4.3
  - pyyaml>=6.0
```

## 容器与 Conda 链接

官方 biocontainers 无 ORFfinder；使用社区镜像 quay.io/preskaa/orffinder:0.4.3 或本地 conda/源码（NCBI ORFfinder）
- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/orffinder/overview
- **YangmingSi 频道（自建，仅裸 ORFfinder 二进制）**：https://anaconda.org/channels/YangmingSi/packages/orffinder/overview
  - 安装：`conda install -c YangmingSi orffinder=0.4.3`
  - 配方归档：`native/conda-recipe/linux-64/meta.yaml`（仅 linux-64；NCBI 无 macOS ORFfinder 二进制。
    `conda build conda-recipe/linux-64` 重建后 anaconda upload 即发布到该频道）
