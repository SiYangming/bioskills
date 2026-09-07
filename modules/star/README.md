# star 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake）的用法；官方 snakemake-wrappers 与 nf-core 子模块信息记录于此（不建目录，仅说明层）。安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# star / native

STAR（Spliced Transcripts Alignment to a Reference）是超快速的 RNA-seq 剪接比对工具，基于 uncompressed suffix array 算法，比对速度快、剪接位点检测灵敏度高，支持发现新剪接位点与融合基因，是目前 RNA-seq 分析的主流比对器之一（官网：<https://github.com/alexdobin/STAR>）。本目录为自包含的 STAR 驱动实现（`source_type: custom`）。

**文档**：https://github.com/alexdobin/STAR/blob/master/doc/STARmanual.pdf

官方镜像优先（bioconda → quay.io/biocontainers → depot.galaxyproject.org 已有 star 官方镜像），本地不再维护 Dockerfile/Apptainer.def；STAR 可执行文件名为 `STAR`。native 与 riboseq 流程统一 2.7.11b（bioconda 包 `star` / quay.io/biocontainers），历史锚点 2.7.10b（Debian apt 曾打包为 rna-star）仍可由 conda 安装，差异见文末「版本差异声明」。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `index` | STAR `--runMode genomeGenerate`：参考 FASTA（+可选 GTF）→ STAR 索引目录 | ✅（默认 8） |
| `align` | STAR `--runMode alignReads`：SE(`-U`)/PE(`-1/-2`) reads → SAM/BAM | ✅（默认 4） |

## 快速开始

> 安装 STAR 的四种方式（conda / docker / apptainer / 官方 release 源码编译）见下方「环境安装」节；以下 CLI 与自省命令在宿主机已装工具的环境执行。

### 1. CLI 调用

```bash
# 建索引（参考 FASTA -> genomeDir/ 下的 Genome/SA/SAindex；含 GTF 时生成剪接位点索引）
python main.py index refs.fa genomeDir --gtf ann.gtf --sjdb-overhang 100 --threads 8
# 小基因组（<2^14 bp）必须调小 genomeSAindexNbases：
python main.py index refs.fa genomeDir --genome-sa-index-nbases 5 --threads 8
# 双端比对 -> BAM（默认 --out-sam-type "BAM SortedByCoordinate"）
python main.py align --genome-dir genomeDir -1 r1.fq.gz -2 r2.fq.gz -o out.bam --threads 8
# 单端比对 -> SAM（SAM 走 stdout 不可靠时一律 -o 落盘）
python main.py align --genome-dir genomeDir -U single.fq.gz -o out.sam \
    --out-sam-type SAM --threads 4
```

### 2. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 3. 测试

```bash
bash test/run_test.sh
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑（容器内只含 STAR，无 python 驱动）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n star-native -c conda-forge -c bioconda star=2.7.11b
conda activate star-native
STAR --version    # 验证（可执行文件名为 STAR）
```

```bash
# 或用 Homebrew（macOS / Linux；STAR 在 homebrew-core 的公式名为 rna-star）
brew install rna-star    # 当前 2.7.11b，与上方 bioconda 一致
STAR --version           # 断言
```

> 完整离线配方（含 python=3.11 / pyyaml，可另存为 star-native.yml（离线兜底），在线直接 mamba create -n star-native -c conda-forge -c bioconda star=2.7.11b）见文末「Conda 环境」节（name: star-native）；历史锚点 2.7.10b（apt 包名 rna-star）见「版本差异声明」。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/star:2.7.11b--h5ca1c30_8    # 与 riboseq 流程一致；tag 见 quay 页面
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/star:2.7.11b--h5ca1c30_8 \
    STAR --runMode genomeGenerate --genomeDir /data/genomeDir \
    --genomeFastaFiles /data/refs.fa --sjdbGTFfile /data/ann.gtf --runThreadN 8
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/star:2.7.11b--h5ca1c30_8 \
    STAR --runMode alignReads --genomeDir /data/genomeDir \
    --readFilesIn /data/r1.fq.gz /data/r2.fq.gz --outSAMtype BAM SortedByCoordinate --runThreadN 8
```

容器内为原生 STAR 入口；需要 Schema/自省/参数注入时在**宿主机**（conda env 装 star）运行 `python main.py <subcommand> ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换；等价直链见文末「容器与 Conda 链接」）：

```bash
apptainer pull star.sif docker://depot.galaxyproject.org/singularity/star:2.7.11b--h5ca1c30_8
apptainer run -B "$PWD":/data -H /data star.sif \
    STAR --runMode alignReads --genomeDir /data/genomeDir \
    --readFilesIn /data/r1.fq.gz /data/r2.fq.gz --outSAMtype BAM SortedByCoordinate --runThreadN 8
```

### 4. 二进制包安装（官方 release 源码编译，无 conda / docker 依赖）

* **GitHub release**：<https://github.com/alexdobin/STAR/releases>

官方 release 分发源码包（无预编译二进制），编译生成 STAR 可执行文件（需支持 C++11 的编译器）：

```bash
wget https://github.com/alexdobin/STAR/releases/download/2.7.11b/STAR_2.7.11b.zip -P ~/software/
cd ~/software && unzip STAR_2.7.11b.zip && cd STAR-2.7.11b/source    # 解压目录名以实际为准
make STAR -j 8
mkdir -p ~/software/STAR-2.7.11b/bin && cp STAR ~/software/STAR-2.7.11b/bin/
echo 'export PATH=$PATH:~/software/STAR-2.7.11b/bin' >> ~/.bashrc
source ~/.bashrc

# 验证安装
STAR --version
```

> 💡 **编译说明**：STAR 编译需要支持 C++11 的编译器。CentOS 6 默认的 gcc 版本较老，可能需要先升级 gcc 或使用预编译的二进制版本。

## 实战示例：RNA-seq 建索引 → 比对 → 批量定量

STAR 基于 uncompressed suffix array，比对速度快且剪接位点检测灵敏度高，支持发现新剪接位点与融合基因，是 RNA-seq 主流比对器之一；等价能力由 `native/main.py` 的 `index` / `align` 子命令提供（见上「快速开始」）。以下为原生 `STAR` CLI 直接调用（版本与 native 2.7.11b 一致）。

### 1. 构建基因组索引（含剪接位点数据库）

```bash
# --sjdbOverhang = 读长 - 1（150 bp 读长取 149）
STAR --runThreadN 8 \
     --runMode genomeGenerate \
     --genomeDir star_index \
     --genomeFastaFiles genome.fasta \
     --sjdbGTFfile genome.gtf \
     --sjdbOverhang 149
```

### 2. 双端比对 + 链信息 + 基因定量

```bash
STAR --runThreadN 8 \
     --genomeDir star_index \
     --readFilesIn sample_1.fastq sample_2.fastq \
     --outFileNamePrefix sample. \
     --outSAMtype BAM SortedByCoordinate \
     --outSAMstrandField intronMotif \
     --quantMode GeneCounts
# 产物 sample.Aligned.sortedByCoord.out.bam；--quantMode GeneCounts 额外输出 sample.ReadsPerGene.out.tab
```

### 3. 批量比对多个样品

```bash
for f in *.1.fastq
do
    s=${f/.1.fastq/}
    echo "STAR --runThreadN 8 --genomeDir star_index \
--readFilesIn ${s}.1.fastq ${s}.2.fastq \
--outFileNamePrefix ${s}. --outSAMtype BAM SortedByCoordinate \
--outSAMstrandField intronMotif --quantMode GeneCounts"
done > command.star.list

# 生成命令列表后逐条执行，或用 xargs / ParaFly 等按行并行
xargs -P 2 -a command.star.list -I CMD bash -c "CMD"
```

### 4. 参数说明

| 参数 | 说明 |
|------|------|
| `--runThreadN N` | 线程数 |
| `--runMode genomeGenerate` | 构建索引模式 |
| `--genomeDir` | 索引目录（构建输出 / 比对输入） |
| `--genomeFastaFiles` | 参考基因组 FASTA |
| `--sjdbGTFfile` | 注释 GTF，用于构建剪接位点数据库 |
| `--sjdbOverhang` | 读长 - 1（150 bp 读长取 149） |
| `--readFilesIn` | 输入 reads（SE 一个 / PE 两个文件） |
| `--outFileNamePrefix` | 输出文件前缀 |
| `--outSAMtype BAM SortedByCoordinate` | 输出按坐标排序的 BAM |
| `--outSAMstrandField intronMotif` | 记录链方向信息（链特异性文库） |
| `--quantMode GeneCounts` | 同时输出基因水平计数 |

> STAR 内存占用较大（人类基因组索引约需 30 GB 内存），内存有限的环境可考虑 HISAT2 等替代。

## 性能优化约定

- **线程**：`index` 默认 8 线程（CPU 密集），`align` 默认 4；用户显式 `--threads` 永远优先。
- **临时目录**：align 默认在隔离 run_dir（输出同目录或 `$TMPDIR`）下运行，`Log.out` / `SJ.out.tab` 等副产物不污染工作目录；`TMPDIR` 通过 `meta.yaml.optimization.env_vars`（占位符 `{tmpdir}`）注入。
- **内存**：STAR 需将索引载入内存，通过 `meta.yaml.optimization.default_mem_mb`（16384 MB）声明，供上层调度器读取；人类基因组流程建议按索引类型单独放大。


---

## snakemake 实现

# star / snakemake（本地规则 + 官方 wrappers 参考）

### 本地拆分规则（type: snakemake_local）

`snakemake/` 下规则按「每 rule 一个 config 驱动 .smk」拆分（td2 式），规则不依赖流程级
`SAMPLES`/`samples` 表与 `config[paths]` 上下文，可脱离流程独立 dry-run：

| 文件 | 规则 | 作用 |
|------|------|------|
| `star_index.smk` | `star_index` | 参考 FASTA（+可选 GTF）→ STAR 索引目录（`--runMode genomeGenerate`），产物 `<star_outdir>/star_index/` |
| `star_align.smk` | `star_align` | SE(`-U`)/PE(`-1/-2`) reads → 基因组比对 BAM（`--runMode alignReads`），产物 `<star_outdir>/align/` |

- 配套文件平铺在 `snakemake/` 根（无 `envs/`、`scripts/` 子目录，`.smk` 内 `conda:`/`script:` 用同目录相对名）：`star.yaml`（bioconda star==2.7.11b，与 riboseq 一致）、`star_index.py` / `star_align.py`（docker/native/conda 三模式经共享 `modules/docker_wrapper.py` 的 `docker_wrapper_binary(config, "star", "star_bin", "STAR")` 分派）。
- 每个 `.smk` 顶部 `config.setdefault` 给默认、头注含独立运行示例与 config 契约；独立运行用 `--config` 提供输入（如 `star_genome_fasta` / `star_reads1,star_reads2`(PE) 或 `star_reads`(SE) / `star_outdir`），`star.*`（docker_image/star_bin/sjdb_overhang/index_extra/align_extra）在 Snakefile 的 config/config.yaml 预设。
- 组装完整流程时分别 `include` 两个 `.smk` 并用 `rule all` 指向产物（见各 `.smk` 头注与 `meta.yaml` 的 `snakemake_include_hint`）。

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> 本模块**不重写官方 wrapper 源码**。官方仓库 `bio/star/` 子模块如下（2026-09 抓取，以官方在线目录为准）：

| wrapper | wrapper 句柄 | 环境 pin（v3.13.0 与 master 一致） |
|---------|--------------|-----------------------------------|
| align | `vX.Y.Z/bio/star/align` | star=2.7.11b |
| index | `vX.Y.Z/bio/star/index` | star=2.7.11b |

引用示例（Snakefile）：

```python
rule star_align:
    input:
        reads=["reads_1.fastq", "reads_2.fastq"],
        idx=directory("refs/star_index"),
    output:
        "mapped.bam"
    log: "logs/star_align.log"
    params:
        extra="--outSAMtype BAM SortedByCoordinate"
    threads: 16
    wrapper: "v3.13.0/bio/star/align"
```

> ⚠️ 本模块未内置官方 wrapper 的 wrapper.py：Snakemake 运行时按 `wrapper:` 句柄解析（联网拉取中央 wrapper 缓存）；离线/私有环境缺失时请改用本模块 `snakemake/star_index.smk` + `snakemake/star_align.smk` 本地规则。
> 更新子模块清单的抓取命令：
> `curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/star | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### nf-core 官方参考（Nextflow，说明层）

本模块未建 `nextflow/` 目录；nf-core 官方 `modules/nf-core/star/` 子模块（2026-09 抓取，以官方在线目录为准）：

| 子模块 | environment.yml 关键 pin（以 align 为代表） |
|--------|---------------------------------------------|
| align | bioconda::star=2.7.11b, htslib=1.21, samtools=1.21, gawk=5.1.0 |
| genomegenerate | star=2.7.11b（同家族 pin） |
| indexversion | star=2.7.11b（同家族 pin） |
| starsolo | star=2.7.11b（同家族 pin，另含 solo 相关依赖） |

组装 Nextflow DSL2 流程时执行 `nf modules install nf-core star align genomegenerate indexversion starsolo`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），随后：

```nextflow
include { STAR_ALIGN }           from '../modules/nf-core/star/align/main'
include { STAR_GENOMEGENERATE }  from '../modules/nf-core/star/genomegenerate/main'
```

> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/star | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`


---

## 版本差异声明（native / snakemake-wrappers / nf-core）

| 实现 | star 版本 | 来源 |
|------|-----------|------|
| native（官方镜像/conda） | **2.7.11b** | quay.io/biocontainers/star:2.7.11b--h5ca1c30_8 / bioconda star=2.7.11b（riboseq 流程同款） |
| snakemake 本地规则 env | 2.7.11b | bioconda（本模块 `snakemake/star.yaml`，与 riboseq 流程一致） |
| snakemake-wrappers v3.13.0 / master | 2.7.11b | bioconda（bio/star/{align,index}/environment.yaml） |
| nf-core master | 2.7.11b | bioconda（modules/nf-core/star/*/environment.yml） |

> native 与 riboseq 流程统一 2.7.11b（官方容器 quay.io/biocontainers/star:2.7.11b--h5ca1c30_8 / conda star=2.7.11b）；历史锚点 2.7.10b（Debian apt 曾打包 rna-star，可执行文件为 STAR）仍可由 conda 安装，索引/比对细节敏感流程请统一 2.7.11b。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# star native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 star-native.yml 后 mamba env create -f star-native.yml；在线推荐上方 mamba create 直装命令
name: star-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - star=2.7.11b       # 与 riboseq 流程一致；历史锚点 2.7.10b 可改用 conda star=2.7.10b（见版本差异声明）
  - pyyaml>=6.0
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/bioconda/star
- **Docker**：`docker pull quay.io/biocontainers/star:2.7.11b--h5ca1c30_8`（riboseq 流程同款）
- **Singularity**：https://depot.galaxyproject.org/singularity/star%3A2.7.11b--h5ca1c30_8
- 安装方式（本地）：`mamba create -n star -c conda-forge -c bioconda star=2.7.11b`（Debian apt 包名 rna-star 与可执行文件说明见上「版本差异声明」）
- 上游 GitHub：https://github.com/alexdobin/STAR
