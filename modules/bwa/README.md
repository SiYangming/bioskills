# bwa 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

BWA（Burrows-Wheeler Aligner）是低内存、高吞吐的短 reads 比对工具（C 程序）：`bwa index` 为参考基因组建立 BWT 索引族（`.bwt/.sa/.pac/.ann/.amb`）；**BWA-MEM**（`bwa mem`，0.7.17 起默认推荐）支持单端/双端/混合比对与嵌合 reads，输出 SAM；`bwa aln → bwa samse/sampe` 为 BWA-backtrack 旧算法（先逐条比对生成 `.sai`，再配对出 SAM）。官网：<https://bio-bwa.sourceforge.net/>；GitHub：<https://github.com/lh3/bwa>。

基于 bioconda / brew / 官方镜像提供的 `bwa=0.7.19` 的 Python 驱动包装：

* 子命令直接构造真实 `bwa` 命令（`index` / `mem` / `aln` / `samse` / `sampe`），自动注入 `-t` 线程（mem 默认 8 / aln 默认 4，可 `--threads` 覆盖）与 `TMPDIR`
* `bwa mem` 的 SAM 输出 stdout（原生行为），`aln/samse/sampe` 可用 `--output/-f` 落盘
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 bwa 二进制）
* 运行时需本地安装 `bwa`（conda / brew / 官方源码编译任选，见「环境安装」）；二进制不在 PATH 时抛清晰错误

## CLI 用法示例

```bash
# 建索引（大基因组自动 bwtsw）
python main.py index ref.fa --index-algorithm bwtsw

# BWA-MEM 双端比对（SAM 到 stdout；-M 兼容下游 Picard MarkDuplicates）
python main.py mem --index ref.fa --reads1 s_R1.fq.gz --reads2 s_R2.fq.gz \
    --threads 16 -M -R "@RG\tID:s1\tSM:s1\tLB:lib1\tPL:ILLUMINA" > out.sam

# BWA-backtrack（aln → sampe）
python main.py aln ref.fa s_R1.fq.gz --sai out_R1.sai --threads 8
python main.py sampe ref.fa out_R1.sai out_R2.sai s_R1.fq.gz s_R2.fq.gz -o out.sam

# 自省
python main.py --list-commands
python main.py --schema
```

## 实战示例（BWA-MEM 全基因组比对 + 后处理，2026 常规流程）

以下为原生 BWA CLI 的典型批量用法；等价能力由 `native/main.py` 的 `index` / `mem` 子命令提供（见上「CLI 用法示例」，无需手写二进制路径）。

### 1. 多样本 Shell 循环（比对 + samtools 排序/转 BAM 管道）

```bash
REF=hg38.fa
bwa index $REF          # 一次性建索引
for s in sampleA sampleB; do
  bwa mem -t 16 -M -R "@RG\tID:${s}\tSM:${s}\tLB:lib1\tPL:ILLUMINA" \
    $REF ${s}_R1.fastq.gz ${s}_R2.fastq.gz \
  | samtools sort -@ 8 -O BAM -o ${s}.sorted.bam -
  samtools index ${s}.sorted.bam
done
```

说明：`bwa mem` 输出 SAM 到 stdout，经管道直接交给 `samtools sort` 避免中间 SAM 落盘；`-R` 写入 RG 标签（多样本合并/去重必需）；`-M` 把 >1 处匹配的拆分 reads 标为次级比对（Picard/DeepVariant 兼容）。

### 2. 单端 / 混合长度模式

```bash
bwa mem -t 8 $REF se_reads.fq.gz > se.sam          # 单端
bwa mem -t 8 $REF long.fq.gz short_1.fq.gz short_2.fq.gz > mix.sam   # 长读+短读混合
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-t N` | 线程数（mem/aln；index 为单线程，多核收益有限） |
| `-R '@RG\t...'` | SAM 头 read group（`ID`/`SM`/`LB`/`PL` 等，建议逐样本唯一） |
| `-M` | 拆分比对标为次级（supplementary→secondary，Picard 兼容） |
| `-p` | 双端 interleaved FASTQ（两 ends 在同一文件交替） |
| `-k` / `-r` / `-c` | seed 长度 / 链重锚定 / 丢弃分数阈值（MEM 默认 -k 19） |
| `-a bwtsw` | 建索引算法：>2 Gb 基因组必须 bwtsw（默认自动：小基因组 is） |

**三种比对算法选型（历史演进；现官方主推 MEM）**：

| 算法 | 适用读长 | 特点 |
| ---- | ---- | ---- |
| `bwa mem` | 70 bp – 1 Mbp | 推荐用于 Illumina 数据；支持剪接比对（长读）、嵌合 reads 与混合读长；0.7.17 起默认 |
| `bwa bwasw` | 70 bp – 1 Mbp | Smith-Waterman 局部比对，适合长读长与测序错误率较高的数据（如 454/旧长读）；0.7.x 后并入 MEM、官方不再维护 |
| `bwa aln`（backtrack） | < 70 bp | backtrack 算法，适合传统短读长（Solexa/GA 时代）；`aln` 逐文件生成 `.sai`，再 `sampe`（双端配对）或 `samse`（单端）合成 SAM |

> 命令链要点：`bwa aln` 为**每端单独**建 `.sai`（`aln -t N ref r1.fq > r1.sai`）→
> `sampe ref r1.sai r2.sai r1.fq r2.fq > out.sam`（`sampe` 将两端 reads 的 `.sai`
> 合并为 SAM）。`bwasw` 无独立驱动子命令（官方已并入 MEM），如需复现可直调
> `bwa bwasw -t N ref <reads>`（README 仅登记，新项目请用 mem）。

> BWA-backtrack 已不建议用于新项目（0.7.17 起官方主推 MEM），保留 `aln/samse/sampe` 仅为旧流程兼容。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 bwa 二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bwa -c conda-forge -c bioconda bwa=0.7.19
conda activate bwa
bwa 2>&1 | head -3   # 断言（usage 输出）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install bwa
bwa 2>&1 | head -3   # 断言
# 注：brew 当前 0.7.19，与 meta 登记 0.7.19 一致
```

> 宿主机直跑 `python main.py index|mem|...` 推荐用文末「Conda 环境」配方建环境（`name: bwa-native`）。本模块不维护本地安装脚本：conda/brew/官方源码三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bwa:0.7.19--h577a1d6_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bwa:0.7.19--h577a1d6_1 \
    bwa mem -t 8 -M /data/hg38.fa /data/s_R1.fq.gz /data/s_R2.fq.gz > /data/out.sam
```

> 容器内即 `bwa` 二进制（单文件，无额外底座）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bwa）运行 `python main.py`。tag 全列表（0.7.17/0.7.18/0.7.19 各构建）以 quay 页面为准。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull bwa.sif docker://depot.galaxyproject.org/singularity/bwa:0.7.19--h577a1d6_1
apptainer run -B $PWD:/data -H /data bwa.sif \
    bwa mem -t 8 /data/hg38.fa /data/s_R1.fq.gz /data/s_R2.fq.gz > /data/out.sam
```

### 4. 二进制包安装（官方 release：源码编译）

bwa 官方 release **无预编译二进制资产**（v0.7.19 release 仅源码归档），官方只提供源码 + Makefile（依赖 zlib）：

```bash
# 官方 GitHub release 源码 tag 归档
wget https://github.com/lh3/bwa/archive/refs/tags/v0.7.19.tar.gz -P ~/software/
tar xzf ~/software/v0.7.19.tar.gz -C ~/software/
make -C ~/software/bwa-0.7.19 -j4
ln -s ~/software/bwa-0.7.19/bwa ~/software/bin/bwa     # 或写 PATH（用户级，免 root）
```

> 验证安装：`bwa 2>&1 | head -3` 应输出 usage（`install` 到 `~/software/` 用户级前缀，免 root、禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：`modules/nf-core/bwa/` 含 **5 个子模块** `aln / index / mem / sampe / samse`（各含 `main.nf` + `environment.yml` + `meta.yml` + `tests`；2026-09-09 抓取核实），conda pin `bioconda::bwa=0.7.19`（mem 另带 htslib=1.22.1 + samtools=1.22.1）。

```bash
nf-core modules install nf-core bwa mem        # 在用户项目安装官方子模块
# include: { BWA_MEM } from './modules/nf-core/bwa/mem/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core bwa <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/bwa/` 含 **7 个 wrapper** `aln / index / mem / mem-samblaster / sampe / samse / samxe`（2026-09-09 抓取核实），当前 master `mem` pin `bwa=0.7.19` + `samtools=1.24` + `picard-slim=3.5.0` + `fgbio-minimal=4.1.1` + `snakemake-wrapper-utils=0.9.0`。

```python
rule bwa_mem:
    input:
        reads=["reads/{sample}_1.fastq.gz", "reads/{sample}_2.fastq.gz"],
        index="genome.fa"
    output: "mapped/{sample}.bam"
    params:
        extra="-M -R '@RG\\tID:{sample}\\tSM:{sample}'",
        sort="samtools sort",          # mem 后接的排序命令（wrapper 内组装管道）
    threads: 8
    wrapper: "v9.17.1/bio/bwa/mem"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/bwa/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要真实 bwa）
```

## 版本

* bwa **0.7.19**（默认锚点；官方 GitHub release v0.7.19，2025-03-22 实测；bioconda / nf-core / brew core / snakemake-wrappers 均 0.7.19，全渠道一致）
* 上游动态：v0.7.17 曾长期稳定（2017-2025），0.7.18（2023）/0.7.19（2025）由 lh3 恢复维护；需旧版可用 conda `bwa=0.7.17`
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/bwa / depot.galaxyproject.org）；本地不再自建容器配方
* bwa 官方 release 无预编译二进制（源码 make 编译，仅依赖 zlib）

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bwa native Conda 环境配方（与 native/environment.yml 相同）
# 说明：官方镜像（quay.io/biocontainers/bwa）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def。
name: bwa-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bwa=0.7.19
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/bwa/overview>（0.7.19 等；linux-64/osx-64/linux-aarch64/osx-arm64）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/bwa:0.7.19--h577a1d6_1`（同版另有 `0.7.19--h577a1d6_0`；0.7.17/0.7.18 tag 亦在，以 quay 实时为准）
* **Singularity**：<https://depot.galaxyproject.org/singularity/bwa%3A0.7.19--h577a1d6_1>
* **GitHub 官方仓库**：<https://github.com/lh3/bwa>（releases：v0.7.19 源码 tag 归档）
* 安装方式（本地）：`mamba create -n bwa -c conda-forge -c bioconda bwa=0.7.19`；或 `brew install bwa`

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* 旧版本文档（0.7.17 时代）常见安装为「wget 源码 → `make` → 拷贝 `bwa` 到 `/usr/local/bin` 或教学目录」，归档时统一改用户级前缀；bwa 二进制不依赖运行库，单文件可直接放入 `~/software/bin/`。
* 0.7.17 之前 `bwa samse/sampe` 是双端 RNA/DNA 比对的默认路径（配合 `bwa aln` 两文件各自建 `.sai`）；GATK Best Practices 于 0.7.15+ 起切换为 `bwa mem`。
