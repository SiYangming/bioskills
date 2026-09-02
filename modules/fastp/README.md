# fastp 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# fastp / native — 自包含质控与去接头驱动

**fastp**（DNA/RNA 短读段质控与预处理）的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包 `fastp=0.24.0` 提供二进制 **`fastp`**。

## 功能

* `run` 子命令：单/双端 FASTQ(gz) 一步完成

  - 接头自动检测与切除（`--detect_adapter_for_pe` / `--adapter_sequence`）
  - 质量过滤（`-q`/`-u`）与长度过滤（`-l`）
  - HTML + JSON 质控报告（`-h`/`-j`）
  - 自动创建输出父目录、自动注入线程（fastp 0.20+ 为 `-w`）与 `TMPDIR`

* 与 `subworkflow/fastp_bwa_samtools` 编排器调用约定完全一致：
  `python main.py run -i R1.fq.gz -o clean_R1.fq.gz -h report.html -j report.json`

> ⚠️ **版本坑**：fastp 0.20.0 起线程参数由 `-t` 改为 `-w, --thread`；
> `-t` 现在表示 `--trim_tail1`。本驱动一律输出 `-w`，请勿用 `-t` 传线程。

## 用法

```bash
# 双端（PE，推荐开启 --detect-adapter-for-pe）
python main.py run -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz \
    -h report.html -j report.json --threads 8 --detect-adapter-for-pe

# 单端（SE）
python main.py run -i R1.fq.gz -o clean_R1.fq.gz -h report.html -j report.json

# 指定接头 + 收紧过滤
python main.py run -i R1.fq.gz -o clean_R1.fq.gz -h r.html -j r.json \
    --adapter-sequence AGATCGGAAGAGCACACGTCTGA \
    --qualified-quality-phred 20 --unqualified-percent-limit 30 --length-required 50

# 高级透传（cut_front/cut_tail/cut_right 等）：
python main.py run -i R1.fq.gz -o clean_R1.fq.gz --extra-args "--cut_front --cut_tail --cut_right 1"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `run` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: fastp-native（fastp=0.24.0）
conda activate fastp-native
```

### 2. Docker

```bash
docker build -t bioskills/fastp:0.24.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/fastp:0.24.0-v1.0 \
    run -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz -h r.html -j r.json
```

### 3. Apptainer / Singularity

```bash
apptainer build fastp.sif Apptainer.def
apptainer run -B $PWD:/data -H /data fastp.sif \
    run -i /data/R1.fq.gz -o /data/clean_R1.fq.gz -h /data/r.html -j /data/r.json
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 FASTQ；fastp 未装时退化为 argv 构造验证
```

## 版本

* fastp 0.24.0（bioconda::fastp=0.24.0，二进制 fastp）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（fastp 不在 Debian apt）

* ⚠️ 版本差异：nf-core / snakemake-wrappers master 当前均 pin `fastp=1.3.6`
  （比本实现 0.24.0 新），跨引擎迁移时注意参数兼容性；详见软件级 `../meta.yaml` 的 `software_versions`。

## 历史留存说明

本技能为新建（补齐 `subworkflow/fastp_bwa_samtools` 编排器对
`modules/fastp/native/main.py run` 的引用缺口），**无 legacy/ 迁移脚本**。
编排器与历史流程请直接以 `main.py` 为正式入口；若未来从旧流程迁移辅助脚本，
按 AGENT.md「脚本归位」原则放入 `native/legacy/`。


---

## snakemake 实现

# fastp / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/fastp` 存在（单 wrapper，见 `../snakemake-wrappers/`），
本目录提供自维护规则作为 **离线 / 中央缓存不可用 / 本地定制** 场景的兜底
（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `fastp.smk` — `rule fastp`：
  - 输入：`reads/{sample}_R1.fastq.gz` + `reads/{sample}_R2.fastq.gz`（PE）
  - 输出：`results/fastp/{sample}_{R1,R2}.clean.fastq.gz` + `_fastp.html` + `_fastp.json`
  - 日志：`results/fastp/logs/fastp_{sample}.log`
  - 命令：`fastp -i R1 -I R2 -o out1 -O out2 -h html -j json -w <threads>`
  - 文件底部附 `fastp_se` 单端变体（注释状态，按需启用）

> ⚠️ fastp 0.20+ 线程参数为 `-w/--thread`（`-t` 已被 `--trim_tail1` 占用）。

## 用法

```python
# Snakefile 中
include: "modules/fastp/snakemake/fastp.smk"

# 运行
snakemake -j 8 results/fastp/sample1_R1.clean.fastq.gz
```

可选 `config["fastp"]`（缺省自动跳过）：

```yaml
# config.yaml
fastp:
  adapter_sequence: "AGATCGGAAGAGCACACGTCTGA"   # R1 3' 接头（IUPAC）
  detect_adapter_for_pe: true                    # PE 重叠检测
  qualified_quality_phred: 15
  unqualified_percent_limit: 40
  length_required: 15
  extra: "--cut_front --cut_tail --cut_right 1"  # 额外透传
```

## 依赖环境

规则直接调用本地 `fastp` 二进制；如需隔离环境，规则内加
`conda: "envs/fastp.yaml"`：

```yaml
# envs/fastp.yaml
channels: [conda-forge, bioconda]
dependencies:
  - fastp=0.24.0
```

## 与其它实现的关系

- 官方 wrapper 存在：`../snakemake-wrappers/`（tag v3.13.0，pin fastp=1.3.6）；
  联网 / 中央缓存可用时优先 wrapper，本规则兜底
- 非 Snakemake 场景（独立 CLI / Agent Function Calling / fastp_bwa_samtools 编排器）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# fastp native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：fastp 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: fastp-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - fastp=0.24.0         # 提供二进制 fastp（DNA/RNA 短读质控与去接头）
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/fastp/overview
- **Docker**：`docker pull quay.io/biocontainers/fastp:1.3.6--h43da1c4_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/fastp%3A1.3.6--h43da1c4_0
- 安装方式（本地）：`mamba create -n fastp -c conda-forge -c bioconda fastp=1.3.6`
