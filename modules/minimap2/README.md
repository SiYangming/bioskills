# minimap2 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# minimap2 / native

minimap2 是通用的核酸序列比对工具，主打 PacBio / Nanopore（ONT）长读长比对，也支持短读长、splice-aware 转录组比对与基因组间比对等模式；速度极快，是目前长读长比对的首选工具（官网：<https://github.com/lh3/minimap2>）。在基因组组装中常用于长 reads 比对、打磨修正等步骤。本目录为自包含的 minimap2 驱动实现（`source_type: custom`）。

**论文**：https://doi.org/10.1093/bioinformatics/bty191

## 能力

| 子命令     | 说明                                           | <br />        | <br />                          |
| ------- | -------------------------------------------- | ------------- | ------------------------------- |
| `align` | reads → 参考基因组比对；`--bam` 输出 BAM（\`minimap2 -a | samtools sort | samtools view -b -h\`），否则输出 PAF |

支持 `--cigar-paf`（PAF 输出 CIGAR，`-c`）与 `--cigar-bam`（长 CIGAR 写 CG 标签，`-L`）；
不提供 `--reference` 时退化为 reads vs reads 自比对；命令逻辑与 nf-core `minimap2/align` 核心行为一致。

## 快速开始

> 安装 minimap2 的四种方式（conda / docker / apptainer / 官方 release）见下方「环境安装」节；以下 CLI 与自省命令在宿主机已装工具的环境执行（BAM 输出另需 samtools）。

### 1. CLI 调用

```bash
# PAF 输出
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --prefix sample --threads 8

# BAM 输出（依赖 samtools）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --bam --threads 8

# 透传 minimap2 参数（splice 模式示例）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln \
    --args "-x splice -uf -k14" --bam --threads 8
```

### 2. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py align --reads x.fa --reference r.fa --dry-run   # 只打印构建出的命令
```

### 3. 测试

```bash
bash test/run_test.sh
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑（容器内只含 minimap2，无 python 驱动）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n minimap2-native -c conda-forge -c bioconda minimap2=2.31 samtools=1.21
conda activate minimap2-native
minimap2 --version    # 验证
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 2.31，与 meta 登记 2.31 略有差异（版本以 formula 为准）
brew install minimap2
minimap2 --version   # 断言
```

> BAM 输出（`minimap2 | samtools sort | samtools view`）需同环境 samtools；完整离线配方（含 python=3.11 / pyyaml，可另存为 minimap2-native.yml（离线兜底），在线直接 mamba create -n minimap2-native -c conda-forge -c bioconda minimap2=2.31 samtools=1.21）见文末「Conda 环境」节（name: minimap2-native）。

### 2. Docker（官方镜像）

```bash
# 示例为与历史流程对齐的 2.28 build（见「版本说明」节）；各版本 tag 见 quay 页面与文末「容器与 Conda 链接」
docker pull quay.io/biocontainers/minimap2:2.28--h577a1d6_4
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/minimap2:2.28--h577a1d6_4 \
    minimap2 -x splice -uf -k14 -t 8 -o /data/aln.paf /data/ref.fa /data/flnc.fa
```

容器内为原生 minimap2 入口（PAF 直出；BAM 输出 `minimap2 | samtools sort | samtools view` 的 samtools 环节需在宿主机或镜像内另备）；需要 Schema/自省/参数注入时在**宿主机**（已装 minimap2 或 conda env）运行 `python main.py align ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换；等价直链见文末「容器与 Conda 链接」）：

```bash
apptainer pull minimap2.sif docker://depot.galaxyproject.org/singularity/minimap2:2.28--h577a1d6_4
apptainer run -B "$PWD":/data -H /data minimap2.sif \
    minimap2 -x splice -uf -k14 -t 8 -o /data/aln.paf /data/ref.fa /data/flnc.fa
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

* **官网/GitHub**：<https://github.com/lh3/minimap2>

官方 release 提供 Linux x86\_64 预编译二进制（亦提供源码包 `minimap2-2.31.tar.bz2` 可自行 make）：

```bash
wget https://github.com/lh3/minimap2/releases/download/v2.31/minimap2-2.31_x64-linux.tar.bz2 -P ~/software/
mkdir -p ~/software/minimap2-2.31
tar jxf ~/software/minimap2-2.31_x64-linux.tar.bz2 -C ~/software/minimap2-2.31
echo 'export PATH=$PATH:~/software/minimap2-2.31' >> ~/.bashrc
source ~/.bashrc

# 验证安装（预编译包若解压出 minimap2-2.31_x64-linux/ 子目录，PATH 指向其中的 minimap2 即可）
minimap2 --version
```

## 实战示例：reads 比对（长读长 / 短读长 / 转录组 / 基因组间）

minimap2 为通用核酸序列比对器：默认输出轻量 PAF，`-a` 输出 SAM；`-x` 按数据类型预设比对参数。等价能力由 `native/main.py` 的 `align` 子命令提供（见上「快速开始」，支持 PAF/BAM 输出与参数透传）；以下为原生 CLI 直接调用。

### 1. 按数据类型的典型模式

```bash
# PacBio 长读长（subreads / CCS）
minimap2 -ax map-pb -t 8 genome.fasta subreads.fasta > pacbio.sam

# Nanopore 长读长
minimap2 -ax map-ont -t 8 genome.fasta ont_reads.fastq > ont.sam

# 二代短读长（双端）
minimap2 -ax sr -t 8 genome.fasta sample_1.fastq sample_2.fastq > short_reads.sam

# 全长转录组剪接比对（Iso-Seq FLNC 常叠加 -uf -k14）
minimap2 -ax splice -t 8 genome.fasta isoseq_reads.fasta > isoseq.sam

# 基因组 vs 基因组（按物种分歧度选 asm5 / asm10 / asm20）
minimap2 -ax asm5 -t 8 genome.fasta query_genome.fasta > genome_vs_genome.sam

# SAM -> 排序 BAM 并建索引（依赖 samtools）
samtools sort -@ 8 -O BAM -o reads.sorted.bam pacbio.sam
samtools index reads.sorted.bam
```

### 2. 三代组装中的 reads 回贴（打磨修正）

```bash
# wtdbg2 等粗装配流程：把 subreads 回贴到 draft 供一致性打磨
minimap2 -t 8 -a -x map-pb -r 500 draft.fasta subreads.fasta | samtools sort -@ 4 -O BAM -o draft.bam

# nanopolish 抛光：把 Nanopore reads 回贴到 draft（多轮循环中每轮同款）
minimap2 -ax map-ont -t 8 draft.fasta nanopore_reads.fastq | samtools sort -@ 4 -o reads.sorted.bam
samtools index reads.sorted.bam
```

### 3. 参数说明

| 参数                    | 说明                |
| --------------------- | ----------------- |
| `-a`                  | 输出 SAM（默认输出 PAF）  |
| `-x map-pb`           | PacBio 长读长比对模式    |
| `-x map-ont`          | Nanopore 长读长比对模式  |
| `-x sr`               | 短读长（Illumina）比对模式 |
| `-x splice`           | 剪接比对模式（全长转录组）     |
| `-x asm5/asm10/asm20` | 基因组间比对（按分歧度选择）    |
| `-t N`                | 线程数               |

> PAF 为默认输出格式，轻量紧凑，适合快速评估比对概况；需要下游 SAM/BAM 处理时用 `-a`。

## 版本说明

* **native 二进制**：`minimap2 2.31`，由**官方镜像/conda 提供**（quay.io/biocontainers/minimap2、bioconda minimap2=2.31；宿主机安装用 mamba/conda；BAM 管线另需 samtools）。

* **与流程原配差异**：原流程配 bioconda `minimap2=2.28`（`quay.io/biocontainers/minimap2:2.28--h577a1d6_4`）。
  2.31 与 2.28 对本流程（Iso-Seq FLNC 比对）行为一致；若需完全对齐 2.28，拉取对应官方镜像 tag
  或宿主机用 conda/mamba 装 `bioconda::minimap2=2.28`。

* nf-core / snakemake-wrappers 侧版本见软件级 `meta.yaml` 的 `software_versions`。

## 性能优化约定

* **线程**：`align` 默认 8 线程（CPU 密集），用户显式 `--threads` 永远优先；`-t` 注入 minimap2，
  samtools sort/view 同步使用。

* **临时目录**：`--tmpdir` 覆盖 `$TMPDIR`；中间 SAM 走管道不落盘（`pipefail` 保证失败传导）。

* **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为** **`main.py`**。

* `minimap2_align.py`

***

## snakemake 实现

# minimap2 / snakemake（本地规则 + 官方 wrappers 参考）

### 本地拆分规则（type: snakemake\_local）

`snakemake/` 下规则按「每 rule 一个 config 驱动 .smk」拆分（td2 式自维护版），规则不依赖流程级
`SAMPLES`/`samples` 表与 `config[paths]` 上下文，可脱离流程独立 dry-run：

| 文件                   | 规则               | 作用                                                                                                                                                                |
| -------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `minimap2_align.smk` | `minimap2_align` | reads（可选 reference）→ 排序 BAM + `.bai` + versions.yml（`minimap2 -a \| samtools sort \| samtools view -b -h` + `samtools index`），产物 `<minimap2_outdir>/<prefix>.bam` |
| `minimap2_align.py`  | —                | 上述规则的同目录 script wrapper（docker/native/conda 三模式经共享 `modules/docker_wrapper.py` 的 `docker_wrapper_binary(config, "minimap2", ...)` 分派）                             |
| `minimap2.yaml`      | —                | conda env：bioconda minimap2==2.31 + samtools==1.24（与官方 wrapper v3.13.0 bio/minimap2/aligner 锚点一致）                                                                 |

* 配套文件平铺在 `snakemake/` 根（无 `envs/`、`scripts/` 子目录，`.smk` 内 `conda:`/`script:` 用同目录相对名）。

* 规则 config 驱动：`minimap2_reads`（必填）/`minimap2_reference`（可选，缺省 reads vs reads 自比对）/`minimap2_outdir`/`minimap2_prefix` 由 `--config` 提供；`exec_mode`（conda 默认/docker/native）、`threads` 与 `minimap2.*`（docker\_image/minimap2\_bin/samtools\_bin/args/cigar\_bam）在 Snakefile 的 config/config.yaml 预设。config 契约与独立运行示例见 `.smk` 头部，例如：

```bash
snakemake -s modules/minimap2/snakemake/minimap2_align.smk \
    --config minimap2_reads=flnc.fa.gz minimap2_reference=ref.fa threads=8 \
    --cores 8 --use-conda
```

* 组装完整流程时 `include` 该 `.smk` 并用 `rule all` 指向产物（见 `.smk` 头注与软件级 `meta.yaml` 的 `execution.snakemake_include_hint`）。

* BAM 管线为多步（minimap2 | samtools sort | samtools view + index + versions 写入）且有执行模式分派 → 用 `script:` 同目录 wrapper；若只需单条命令（PAF 直出等），用官方 `wrapper:` 句柄（见下）或自行写 `shell:` 一行规则。

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> 本模块**不重写官方 wrapper 源码**。官方仓库 `bio/minimap2/` 子模块如下（2026-08 抓取，以官方在线目录为准）：

| wrapper | wrapper 句柄                    | 环境 pin（v3.13.0，见软件级 meta.yaml software\_versions）             |
| ------- | ----------------------------- | ------------------------------------------------------------- |
| aligner | `vX.Y.Z/bio/minimap2/aligner` | minimap2=2.31 + samtools=1.24 + snakemake-wrapper-utils=0.9.0 |
| index   | `vX.Y.Z/bio/minimap2/index`   | 同上                                                            |

引用示例（Snakefile）：

```python
rule minimap2_align:
    input:
        ref="refs/genome.fa",
        reads="reads.fastq.gz"
    output:
        "mapped.bam"
    log: "logs/minimap2_align.log"
    params:
        extra="-x splice -uf -k14 -a"
    threads: 16
    wrapper: "v3.13.0/bio/minimap2/aligner"
```

> ⚠️ 本模块未内置官方 wrapper 的 wrapper.py：Snakemake 运行时按 `wrapper:` 句柄解析（联网拉取中央 wrapper 缓存）；离线/私有环境缺失时请改用本模块 `snakemake/minimap2_align.smk` 本地规则。
> 更新子模块清单的抓取命令：
> `curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/minimap2 | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# minimap2 native Conda 环境配方
# 离线兜底：可另存为 minimap2-native.yml 后 mamba env create -f minimap2-native.yml；在线推荐上方 mamba create 直装命令
# 说明：容器走官方镜像（quay.io/biocontainers/minimap2），不再维护本地配方；
#      本文件仅作 HPC 无 root 场景 / 非容器场景的 Conda 兜底。
#      如需与历史流程原配完全对齐，可把 minimap2 pin 改为 2.28。
name: minimap2-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - minimap2=2.31
  - samtools=1.21
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/minimap2/overview>

* **Docker（最新）**：`docker pull quay.io/biocontainers/minimap2:2.31--h118bc1c_0`

* **Singularity（最新）**：<https://depot.galaxyproject.org/singularity/minimap2%3A2.31--h118bc1c_0>

* 安装方式（本地）：`mamba create -n minimap2 -c conda-forge -c bioconda minimap2=2.31`

* 注：流程原配版本见上文（minimap2 历史版本），本链接为 bioconda 最新容器。

