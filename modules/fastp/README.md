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

## 环境安装（三选一；官方镜像/conda 提供）

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n fastp-native -c conda-forge -c bioconda fastp=0.24.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate fastp-native
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 1.3.6，与 meta 登记 0.24.0 略有差异（版本以 formula 为准）
brew install fastp
fastp --version   # 断言
```

### 2. 官方镜像（Docker；官方镜像内只含 fastp 工具）

```bash
docker pull quay.io/biocontainers/fastp:<tag>        # tag 见文末「容器与 Conda 链接」
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/fastp:<tag> \
    -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz -h r.html -j r.json
```

### 3. Apptainer / Singularity（官方镜像直拉）

```bash
apptainer pull fastp.sif docker://quay.io/biocontainers/fastp:<tag>
# 或直链 depot.galaxyproject.org/singularity/fastp%3A<tag>（与 quay 同 build tag）
apptainer exec fastp.sif fastp -i R1.fq.gz -o clean_R1.fq.gz -h r.html -j r.json
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 FASTQ；fastp 未装时退化为 argv 构造验证
```

## 版本

* fastp 0.24.0（官方镜像/conda 提供：quay.io/biocontainers/fastp / bioconda::fastp=0.24.0，二进制 fastp）

* 构建路线：官方镜像优先，本地不再自建容器（bioconda → quay.io/biocontainers/fastp → depot.galaxyproject.org）

* ⚠️ 版本差异：nf-core / snakemake-wrappers master 当前均 pin `fastp=1.3.6`
  （比本实现 0.24.0 新），跨引擎迁移时注意参数兼容性；详见软件级 `../meta.yaml` 的 `software_versions`。

## 历史留存说明

本模块为新建实现，**无历史 legacy 脚本**；`fastp` 能力正式入口为
`modules/fastp/native/main.py`（`run` 子命令，供 `subworkflow/fastp_bwa_samtools` 编排器调用）。


---

## snakemake 实现

# fastp / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/fastp` 存在（单 wrapper，见 `../snakemake-wrappers/`），
本目录提供自维护规则作为 **离线 / 中央缓存不可用 / 本地定制** 场景的兜底
（`source_type: custom`、`type: snakemake_local`）。td2 式：SE/PE 各一单规则文件
（config 驱动），共享 wrapper `fastp.py`（两级注入 `modules/`）与环境 `fastp.yaml`
（同目录，bioconda::fastp=0.24.0）。

## 规则文件

- `fastp_pe.smk` — `rule fastp_pe`（双端）：
  - 输入：`fastp_read1` + `fastp_read2`
  - 输出：`fastp_out1` / `fastp_out2` + `fastp_html` + `fastp_json`
  - 日志：`<fastp_outdir>/logs/fastp_pe.log`
- `fastp_se.smk` — `rule fastp_se`（单端）：
  - 输入：`fastp_read1`
  - 输出：`fastp_out1` + `fastp_html` + `fastp_json`
  - 日志：`<fastp_outdir>/logs/fastp_se.log`
- 命令（wrapper `fastp.py`）：`fastp -i R1 [-I R2] -o out1 [-O out2] -h html -j json -w <threads>`
- `fastp.yaml` — conda env（bioconda `fastp=0.24.0`，与 native 版本锚点一致）

> ⚠️ fastp 0.20+ 线程参数为 `-w/--thread`（`-t` 已被 `--trim_tail1` 占用）。

## 用法（config 契约见各 .smk 头注与软件级 meta.yaml `snakemake_include_hint`）

```python
# Snakefile 中（按需 include）
include: "modules/fastp/snakemake/fastp_pe.smk"
include: "modules/fastp/snakemake/fastp_se.smk"

rule all:
    input: [config["fastp_out1"], config["fastp_out2"], config["fastp_html"], config["fastp_json"]]
```

```bash
# 独立运行（PE；SE 用 fastp_se.smk 且只传 fastp_read1）
snakemake -s modules/fastp/snakemake/fastp_pe.smk \
    --config fastp_read1=s1_R1.fastq.gz fastp_read2=s1_R2.fastq.gz \
    fastp_outdir=fastp_out --cores 8 --use-conda
```

可选 `config["fastp"]`（缺省自动跳过；`exec_mode` 支持 conda/docker/native）：

```yaml
# config.yaml
exec_mode: conda
fastp:
  adapter_sequence: "AGATCGGAAGAGCACACGTCTGA"   # R1 3' 接头（IUPAC）
  detect_adapter_for_pe: true                    # PE 重叠检测
  qualified_quality_phred: 15
  unqualified_percent_limit: 40
  length_required: 15
  extra: "--cut_front --cut_tail --cut_right 1"  # 额外透传
```

## 与其它实现的关系

- 官方 wrapper 存在：`../snakemake-wrappers/`（tag v3.13.0，pin fastp=1.3.6）；
  联网 / 中央缓存可用时优先 wrapper，本规则兜底
- 非 Snakemake 场景（独立 CLI / Agent Function Calling / fastp_bwa_samtools 编排器）请走 `../../native/`


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# fastp native Conda 环境配方
# 离线兜底：可另存为 fastp-native.yml 后 mamba env create -f fastp-native.yml；在线推荐上方 mamba create 直装命令
# 说明：官方镜像/conda 提供 fastp（quay.io/biocontainers/fastp / bioconda fastp=0.24.0）；
#      本文件仅作 HPC 无 root / 离线场景的 Conda 兜底（本地不再自建容器）。
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
