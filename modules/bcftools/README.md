# bcftools 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

bcftools 是处理 BCF/VCF 的变异检测与后处理工具集（samtools 家族，C 程序，与 htslib 同源）。核心子命令：`mpileup`（多 BAM → 位点 pileup → BCF/VCF）、`call`（变异检测与基因型判定）、`view`（格式转换与子集/表达式过滤）、`sort` / `index`（排序与 `.csi/.tbi` 索引）、`norm`（左对齐 + 拆分多等位 + 检查 REF）、`query`（灵活格式提取）、`consensus`（由 VCF 生成一致性序列）。官网：<https://samtools.github.io/bcftools/>；GitHub：<https://github.com/samtools/bcftools>。

基于 bioconda / brew / 官方镜像提供的 `bcftools=1.24` 的 Python 驱动包装：

* 子命令直接构造真实 `bcftools` 命令（`view` / `mpileup` / `call` / `sort` / `index` / `norm` / `query` / `consensus`）
* `sort` 自动注入 `-T <tmpdir>/bcftools_sort.<pid>` 临时前缀；全部经 `TMPDIR` 优化
* bcftools 多线程支持分散（部分子命令支持 `--threads`），本驱动不自动注入，需用时经 `--extra-args` 透传
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 bcftools 二进制）
* 运行时需本地安装 `bcftools`（conda / brew / 官方源码编译任选，见「环境安装」）；二进制不在 PATH 时抛清晰错误

## CLI 用法示例

```bash
# view：BCF → gzip VCF + 表达式过滤
python main.py view raw.bcf -O z -o raw.vcf.gz -i 'QUAL>30 && INFO/DP>10'

# 变异检测管线：mpileup → call → 排序/索引
python main.py mpileup -f ref.fa sample1.bam sample2.bam -O b -o raw.bcf
python main.py call raw.bcf -m -v -O z -o calls.vcf.gz
python main.py index calls.vcf.gz
python main.py norm calls.vcf.gz -f ref.fa -m -any -O z -o norm.vcf.gz

# query：批量提取位点信息
python main.py query calls.vcf.gz -f '%CHROM\t%POS\t%REF\t%ALT\n' -r chr1

# consensus：一致性序列
python main.py consensus calls.vcf.gz -f ref.fa -H 1 -o cons.fa

# 自省
python main.py --list-commands
python main.py --schema
```

## 实战示例（典型批量后处理流程）

以下为原生 bcftools CLI 的典型用法；等价能力由 `native/main.py` 的子命令提供（见上「CLI 用法示例」）。

### 1. 多样本变异检测（mpileup → call 管道，含线程与区域）

```bash
REF=hg38.fa
# 1) 每染色体并行 mpileup（bcftools 自 1.10 支持 --threads 用于输出压缩/BCF 写入）
bcftools mpileup -f $REF --threads 4 -a DP,AD -O b -o chr1.raw.bcf \
    $(cat bams.list | tr '\n' ' ') -r chr1
# 2) call（-m 多等位基因模型；-v 仅变异位点；--ploidy 2 默认）
bcftools call -m -v --threads 4 -O z -o chr1.calls.vcf.gz chr1.raw.bcf
# 3) 后处理：左对齐归一化 → 排序 → 索引
bcftools norm -f $REF -m -any chr1.calls.vcf.gz -O z -o chr1.norm.vcf.gz
bcftools sort chr1.norm.vcf.gz -O z -o chr1.sorted.vcf.gz
bcftools index -t chr1.sorted.vcf.gz
```

### 2. 站点/样本过滤与提取（批量 QC）

```bash
# QUAL + 深度过滤；按样本子集
bcftools view -i 'QUAL>30 && INFO/DP>10 && FMT/GQ>20' -s NA12878,NA12879 \
    all.sorted.vcf.gz -O z -o subset.vcf.gz
# 位点表格导出（后续 R/Excel 分析）
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%INFO/DP\n' subset.vcf.gz > sites.tsv
# 全部样本名清单
bcftools query -l subset.vcf.gz > samples.txt
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `mpileup -f ref` | 参考 FASTA（必须与比对一致）；`-a DP,AD` 输出 INFO/FORMAT 字段 |
| `call -m` | 多等位基因（multiallelic）caller 模型（`-c` 为旧 consensus 模型） |
| `call -v` | 只输出变异位点（过滤纯合参考） |
| `-O b/u/z/v` | 输出类型：BCF / 未压缩 BCF / gzip VCF / 未压缩 VCF |
| `view -i/-e` | 按表达式包含/排除（`INFO/DP`、`FMT/GQ`、`QUAL` 等） |
| `view -s` | 样本子集；`-r chr1:1-10000` 区域 |
| `norm -m -any/-snps/-indels` | 拆分多等位 / 仅 SNP / 仅 indel；`-f ref` 同时做左对齐 |
| `index -t` | VCF 建 `.tbi`（默认 `.csi`） |
| `query -f` | 格式串（`%CHROM`/`%POS`/`%REF`/`%ALT`/`%INFO/..`/`%FMT/..`） |
| `consensus -H 1/2` | 取第 1/2 个等位基因（`-H A` 为杂合 IUPAC 简并） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 bcftools 二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bcftools -c conda-forge -c bioconda bcftools=1.24
conda activate bcftools
bcftools --version | head -1   # 断言：bcftools 1.24
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install bcftools
bcftools --version | head -1   # 断言
# 注：brew 当前 1.24，与 meta 登记 1.24 一致
```

> 宿主机直跑 `python main.py view|call|...` 推荐用文末「Conda 环境」配方建环境（`name: bcftools-native`）。本模块不维护本地安装脚本：conda/brew/官方源码三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bcftools:1.24--h118bc1c_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bcftools:1.24--h118bc1c_2 \
    bcftools mpileup -f /data/ref.fa /data/s1.bam /data/s2.bam -O b -o /data/raw.bcf
```

> 容器内即 `bcftools` 二进制（单文件）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bcftools）运行 `python main.py`。tag 全列表以 quay 页面为准。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull bcftools.sif docker://depot.galaxyproject.org/singularity/bcftools:1.24--h118bc1c_2
apptainer run -B $PWD:/data -H /data bcftools.sif \
    bcftools call -m -v /data/raw.bcf -O z -o /data/calls.vcf.gz
```

### 4. 二进制包安装（官方 release：源码编译）

bcftools 官方 release 仅提供源码归档 `bcftools-1.24.tar.bz2`（无预编译二进制；`./configure && make`，依赖 htslib、zlib）：

```bash
wget https://github.com/samtools/bcftools/releases/download/1.24/bcftools-1.24.tar.bz2 -P ~/software/
tar xjf ~/software/bcftools-1.24.tar.bz2 -C ~/software/
cd ~/software/bcftools-1.24 && ./configure --prefix=$HOME/software/bcftools-1.24 && make -j4 && make install
echo 'export PATH=$HOME/software/bcftools-1.24/bin:$PATH' >> ~/.bashrc   # 用户级，免 root
```

> 验证安装：`bcftools --version | head -1` 应输出 `bcftools 1.24`（路径一律用户级 `~/software/`，禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：`modules/nf-core/bcftools/` 含 **30 个子模块**（annotate/call/concat/consensus/convert/csq/filter/index/isec/merge/mpileup/norm/plotvcfstats/plugins*/query/reheader/roh/sort/split/stats/view 等；2026-09-09 抓取核实）。以 `call` 为锚点 pin `bioconda::bcftools=1.23.1` + `htslib=1.23.1`（**比 native 的 1.24 低一个版本**，各子模块以自身 environment.yml 为准）。

```bash
nf-core modules install nf-core bcftools call    # 在用户项目安装官方子模块
# include: { BCFTOOLS_CALL } from './modules/nf-core/bcftools/call/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core bcftools <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/bcftools/` 含 **12 个 wrapper**（call/concat/filter/fixploidy/index/merge/mpileup/norm/reheader/sort/stats/view；2026-09-09 抓取核实），当前 master `call` pin `bcftools=1.24` + `snakemake-wrapper-utils=0.9.0`。

```python
rule bcftools_call:
    input: bcf="calls/raw.bcf", fasta="genome.fa"
    output: "calls/filtered.vcf.gz"
    params: extra="-m -v", export = "-Ov"
    log: "logs/bcftools/call.log"
    wrapper: "v9.17.1/bio/bcftools/call"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/bcftools/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要真实 bcftools）
```

## 版本

* bcftools **1.24**（默认锚点；官方 GitHub release 1.24，2026-07-09 实测；bioconda / brew core / snakemake-wrappers 均 1.24）
* 上游动态：nf-core 官方模块目前 pin **1.23.1**（低于 native 1.24，nf-core 尚未 bump）；需要与 nf-core 对齐时 conda 改 pin `bcftools=1.23.1`
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/bcftools / depot.galaxyproject.org）；本地不再自建容器配方
* bcftools 官方 release 无预编译二进制（源码 `bcftools-1.24.tar.bz2`，configure+make）

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bcftools native Conda 环境配方（与 native/environment.yml 相同）
# 说明：官方镜像（quay.io/biocontainers/bcftools）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def。
name: bcftools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bcftools=1.24
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/bcftools/overview>（1.24 等；linux-64/osx-64/linux-aarch64/osx-arm64）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/bcftools:1.24--h118bc1c_2`（同版另有 `1.24--h487d631_1/_0`，以 quay 实时为准）
* **Singularity**：<https://depot.galaxyproject.org/singularity/bcftools%3A1.24--h118bc1c_2>
* **GitHub 官方仓库**：<https://github.com/samtools/bcftools>（releases：1.24 源码 tar.bz2）
* 安装方式（本地）：`mamba create -n bcftools -c conda-forge -c bioconda bcftools=1.24`；或 `brew install bcftools`

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* 旧流程（GATK 3.x 时代）常用 `bcftools mpileup -uf ref | bcftools call -c`（consensus 模型）；GATK4 后社区默认 `-m`（multiallelic）模型，`-c` 已不建议。
* 更早的 samtools 0.1.x 时代对应命令为 `samtools mpileup -uf ref | bcftools view -vcg -`，参数语义与现 bcftools 差异较大，仅作版本对照。
* 文档中 `/home/train/...` 类教学固定路径为历史残留，不再沿用。
