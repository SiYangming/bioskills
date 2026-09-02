# orffinder 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# orffinder / native — 自包含 ORF 预测驱动

**ORFfinder**（NCBI 开放阅读框查找工具，本地版）的自包含实现（`source_type: custom`、`type: native`）。
conda 包 `orffinder=0.4.3` 提供二进制 **`ORFfinder`**（来自 NCBI，flrnaseq 流程对应
`quay.io/preskaa/orffinder:0.4.3`）。

## 功能

* `run`：在核酸序列中查找 ORF 并输出蛋白翻译

  `ORFfinder -in <fasta> -out <file> -outfmt <int> [-g <code>] [-s <0|1|2>] [-ml <nt>] [-strand <both|plus|minus>] [-n]`

* 输出格式（`-outfmt`，与 flrnaseq config.yaml suffix_map 一致）：
  - `0` → ORFs FASTA（后缀 `_orf.fa`）
  - `1` → CDS FASTA（后缀 `_cds.fa`）
  - `2` → Text ASN.1（后缀 `.asn1`，flrnaseq 默认）
  - `3` → Feature table（后缀 `.ft`）

* 自动解压 `.gz` 输入、自动生成默认输出路径、注入 `TMPDIR`

## 用法

```bash
# CLI 直跑（参数与 flrnaseq config.yaml orffinder 段对应）
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

```bash
docker build -t bioskills/orffinder:0.4.3-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
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

## 历史留存（legacy/）

`legacy/` 存放迁移自 flrnaseq.smk 流程 `workflow/scripts/` 的原始 Snakemake wrapper 脚本，
仅供追溯对照，**正式入口为 `main.py`**。

- `orffinder.py` — ORFfinder 原始 wrapper（snakemake.shell + docker_wrapper）


---

## snakemake 实现

# orffinder / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/orffinder`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `orffinder.smk` — `rule orffinder`：核酸 FASTA → ORF 预测结果

规则迁移自 `snakemake.smk/flrnaseq.smk/workflow/rules/orffinder.smk`，去除对
Snakefile 顶部全局变量（SAMPLES / os / config）与 `docker_wrapper.py` 的依赖：
- 输入路径模板：`long_read/{sample}.fasta`
- 参数内联（与 flrnaseq config.yaml orffinder 段一致）：
  - `outfmt: 2`（Text ASN.1；suffix_map：0=_orf.fa, 1=_cds.fa, 2=.asn1, 3=.ft）
  - `extra: "-s 2 -ml 30"`（起始密码子=任意有义密码子，最小 ORF 长度=30 nt）
- docker/container 分支移除，直接调用 `ORFfinder` 二进制

## 用法

```python
# Snakefile 中
include: "modules/orffinder/snakemake/orffinder.smk"

# 运行（默认 outfmt=2 -> orffinder/sample1.asn1）
snakemake -j 4 orffinder/sample1.asn1
```

改输出格式时，同步调整 `params.outfmt` 与 `output.file` 后缀（见 suffix_map）。

## 依赖环境

规则内 `conda: "envs/orffinder.yaml"`，需要自备：

```yaml
# envs/orffinder.yaml
channels: [conda-forge, bioconda]
dependencies:
  - orffinder=0.4.3
```

## 与其它实现的关系

- 官方 wrapper 当前不存在（`../snakemake-wrappers/` 登记层注明 bio/orffinder 404）；若未来出现可切换
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# orffinder native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：orffinder 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
# 对齐 flrnaseq envs/orffinder.yaml：orffinder=0.4.3（二进制 ORFfinder 来自 NCBI）。
name: orffinder-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - orffinder=0.4.3      # 提供二进制 ORFfinder
  - pyyaml>=6.0
  - pip
```
