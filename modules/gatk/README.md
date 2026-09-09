# gatk 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

GATK v4（Genome Analysis Toolkit）是 Broad Institute 的变异检测金标准工具套件（Java，官方发布物为 `gatk-4.x.zip`，内含 `gatk` launcher 脚本）：`HaplotypeCaller`（胚系短变异检测，`-ERC GVCF` 输出 gVCF 供 cohort 联合分析）、`GenotypeGVCFs` / `CombineGVCFs`（gVCF 联合基因分型）、`BaseRecalibrator` / `ApplyBQSR`（BQSR 碱基质量校正）、`VariantFiltration` / `SelectVariants`（变异过滤与类型选择）、`SplitNCigarReads`（RNA-seq 比对 N-CIGAR 拆分）。官网：<https://gatk.broadinstitute.org/>；GitHub：<https://github.com/broadinstitute/gatk>。

基于 bioconda（`gatk4`/`gatk4-main`）/ 官方 zip 的 Python 驱动包装：

* 子命令（小写）自动映射为真实 GATK 工具名（如 `haplotypecaller` → `HaplotypeCaller`），构造 `-I/-R/-O/-V` 参数
* 自动解析调用入口：优先 PATH 上的 `gatk` launcher（conda / biocontainer 均提供）；否则按 `GATK_JAR` 环境变量 → conda share / `~/software` 常见位置定位 `gatk-package-*-local.jar`，以 `java -jar` 调用（需宿主 java 17）
* `HaplotypeCaller` 自动注入 `--native-pair-hmm-threads`（默认 4，可 `--threads` 覆盖）
* 经 `JAVA_TOOL_OPTIONS` 注入 JVM 最大堆内存（默认 16 GB）与 `-Djava.io.tmpdir` + `TMPDIR`
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 java / gatk）
* 运行时需本地安装 `java` + `gatk`：安装方式见下方「环境安装」

## CLI 用法示例

```bash
# 胚系 gVCF（GATK Best Practices 单样本段）
python main.py haplotypecaller -I sample.dedup.bam -R hg38.fa \
    -O sample.g.vcf.gz --erc GVCF --threads 8

# cohort 联合：CombineGVCFs -> GenotypeGVCFs
python main.py combinegvcfs -V s1.g.vcf.gz -V s2.g.vcf.gz -R hg38.fa -O cohort.g.vcf.gz
python main.py genotypegvcfs -V cohort.g.vcf.gz -R hg38.fa -O cohort.vcf.gz

# BQSR（先建校正表，再应用）
python main.py baserecalibrator -I sample.dedup.bam -R hg38.fa \
    -O sample.recal.table --known-sites dbsnp_151.hg38.vcf.gz
python main.py applybqsr -I sample.dedup.bam -R hg38.fa \
    -O sample.bqsr.bam --bqsr-recal-file sample.recal.table

# 自省
python main.py --list-commands
python main.py --schema
```

## 实战示例（GATK Best Practices 胚系短变异流程）

以下为原生 GATK CLI（官方 zip 的 `gatk` launcher）的典型用法；等价能力由 `native/main.py` 的子命令提供（见上「CLI 用法示例」）。

### 1. 多样本循环：单样本 HaplotypeCaller → gVCF

```bash
REF=hg38.fa
for s in sampleA sampleB; do
  gatk HaplotypeCaller -I ${s}.bqsr.bam -R $REF \
      -O ${s}.g.vcf.gz -ERC GVCF --native-pair-hmm-threads 8
done
```

说明：`-ERC GVCF` 输出含参考块的 gVCF（后续 cohort 联合必需）；单样本跑完即可合并 `CombineGVCFs`。

### 2. cohort 联合基因分型 + 硬过滤

```bash
# 2a. 合并全部 gVCF（写进 gvcf.list，每行一个 -V 文件）
gatk CombineGVCFs -R $REF $(for f in *.g.vcf.gz; do printf ' -V %s' "$f"; done) \
    -O cohort.g.vcf.gz
# 2b. 联合基因分型
gatk GenotypeGVCFs -R $REF -V cohort.g.vcf.gz -O cohort.vcf.gz
# 2c. 硬过滤（VQSR 前的简单方案）
gatk VariantFiltration -R $REF -V cohort.vcf.gz -O cohort.hf.vcf.gz \
    --filter-expression "QD < 2.0" --filter-name LowQD \
    --filter-expression "FS > 60.0" --filter-name HighFS
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-I` | 输入 BAM/CRAM（HaplotypeCaller / BQSR / ApplyBQSR / SplitNCigarReads） |
| `-V` | 输入 VCF/GVCF（GenotypeGVCFs / VariantFiltration / SelectVariants；CombineGVCFs 可重复） |
| `-R` | 参考 FASTA（须同前缀 `.dict`（CreateSequenceDictionary）与 `.fai`（samtools faidx）） |
| `-O` | 输出文件（GATK4 不允许省略） |
| `-ERC GVCF` | HaplotypeCaller 输出 gVCF（`NONE` 默认 / `BP_RESOLUTION` 位点级） |
| `--native-pair-hmm-threads N` | HaplotypeCaller pair-HMM 并行线程 |
| `-L` | 区间（`chr1:1000-2000` 或 interval 文件） |
| `--known-sites` | BaseRecalibrator 已知位点（dbSNP + 1000G，可多个） |
| `--bqsr-recal-file` | ApplyBQSR 读入的校正表（BaseRecalibrator 的 `-O` 产物） |

> 完整工具清单以 `gatk --list` 为准（含内嵌 Picard）；RNA-seq 建议 HaplotypeCaller 前用 `SplitNCigarReads` 拆分 N-CIGAR。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 GATK（容器内含 OpenJDK + `gatk` launcher）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
# bioconda 包名为 gatk4（noarch，最新 4.6.2.0）；要官方最新 4.7.0.0 用 gatk4-main
mamba create -n gatk -c conda-forge -c bioconda gatk4=4.6.2.0
#   （或 mamba create -n gatk -c conda-forge -c bioconda gatk4-main=4.7.0.0）
conda activate gatk
gatk --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；homebrew-core 无公式，公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio
brew install gatk
gatk --version   # 断言
# 注：brewsci/bio gatk 公式基于官方 4.6.2.0 zip 构建（比 meta 登记的官方最新 4.7.0.0 低一版）
```

> 宿主机直跑 `python main.py haplotypecaller|...` 推荐用文末「Conda 环境」配方建环境（`name: gatk-native`）。本模块不维护本地安装脚本：conda/brew/官方 zip 三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/gatk4:4.6.2.0--py310hdfd78af_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/gatk4:4.6.2.0--py310hdfd78af_1 \
    gatk HaplotypeCaller -I /data/sample.bam -R /data/hg38.fa \
    -O /data/sample.g.vcf.gz -ERC GVCF
```

> 容器内为 `gatk` launcher（含 OpenJDK 底座）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 gatk + openjdk）运行 `python main.py`。注意 quay tag 对应 bioconda `gatk4`（最新 4.6.2.0；4.7.0.0 尚无 quay tag，以 quay 实时为准）。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull gatk4.sif docker://depot.galaxyproject.org/singularity/gatk4:4.6.2.0--py310hdfd78af_1
apptainer run -B $PWD:/data -H /data gatk4.sif \
    gatk GenotypeGVCFs -R /data/hg38.fa -V /data/cohort.g.vcf.gz -O /data/cohort.vcf.gz
```

### 4. 二进制包安装（官方 zip，自带 launcher）

* **官方下载**：<https://github.com/broadinstitute/gatk/releases>（release 资产 `gatk-4.7.0.0.zip`，内含 `gatk` launcher + `gatk-package-*-local.jar` + 可选 jre；需 Java 17，或直接使用 zip 内捆绑 jre）
* GATK 官方同时提供 Docker 镜像 `broadinstitute/gatk`（Docker Hub），zip 为本机/离线首选

```bash
wget https://github.com/broadinstitute/gatk/releases/download/4.7.0.0/gatk-4.7.0.0.zip -P ~/software/
unzip ~/software/gatk-4.7.0.0.zip -d ~/software/
export PATH=~/software/gatk-4.7.0.0:$PATH      # 或加入 ~/.bashrc（用户级，免 root）
gatk --version   # 断言
# main.py 自动识别：export GATK_JAR=~/software/gatk-4.7.0.0/gatk-package-4.7.0.0-local.jar
```

> 验证安装：`gatk --version` 应输出 4.7.0.0（路径一律用户级 `~/software/`，禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

⚠️ **登记名差异**：`modules/nf-core/gatk/` 仅存 GATK3 时代 3 个旧子模块（`indelrealigner`/`realignertargetcreator`/`unifiedgenotyper`，2026-09-09 抓取核实）；**GATK4 现代工具全部登记在 `modules/nf-core/gatk4/`**（65 个子模块：haplotypecaller/genotypegvcfs/combinegvcfs/baserecalibrator/applybqsr/variantfiltration/selectvariants/splitncigarreads/mutect/...）。`haplotypecaller` 子模块 pin `bioconda::gatk4-main=4.7.0.0` + `gcnvkernel=0.9`（与 native 4.7.0.0 一致）。

```bash
nf-core modules install nf-core gatk4 haplotypecaller   # 在用户项目安装官方子模块
# include: { GATK4_HAPLOTYPECALLER } from './modules/nf-core/gatk4/haplotypecaller/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core gatk4 <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/gatk/` 含 **36 个 wrapper**（haplotypecaller/genotypegvcfs/combinegvcfs/mutect/applybqsr/baserecalibrator/variantfiltration/selectvariants/splitncigarreads/...；2026-09-09 抓取核实），当前 master `haplotypecaller` pin `gatk4=4.6.2.0` + `snakemake-wrapper-utils=0.9.0`（**低于**官方最新 4.7.0.0）。

```python
rule gatk_haplotypecaller:
    input:
        bam="bqsr/{sample}.bam",
        fasta="genome.fa"
    output: "gvcf/{sample}.g.vcf.gz"
    params:
        extra="--emit-ref-confidence GVCF",
        intervals=None
    log: "logs/gatk/haplotypecaller/{sample}.log"
    wrapper: "v9.17.1/bio/gatk/haplotypecaller"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/gatk/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要 java / gatk）
```

## 版本

* gatk **4.7.0.0**（native 锚点；官方 GitHub release 4.7.0.0，2026-08-18 实测）
* **版本差异要点**：bioconda `gatk4` 最新 **4.6.2.0**（noarch，quay tag 4.6.2.0--py310hdfd78af_1 即其产物）；bioconda `gatk4-main` 与 nf-core 均 pin **4.7.0.0**；brewsci/bio gatk 公式构建 **4.6.2.0**。三者可共存，需 4.7.0.0 时 conda 用 `gatk4-main=4.7.0.0` 或官方 zip
* Java 要求：GATK 4.x 需 Java 17（官方 zip 亦可捆绑 jre 运行）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/gatk4 / depot.galaxyproject.org / broadinstitute/gatk）；本地不再自建容器配方

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# gatk native Conda 环境配方（与 native/environment.yml 相同）
# 说明：官方镜像（quay.io/biocontainers/gatk4）即由 bioconda gatk4 本环境构建；
#       openjdk 由 conda 依赖自动带入；本地不再自建 Dockerfile/Apptainer.def。
name: gatk-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - gatk4-main=4.7.0.0   # 官方 4.7.0.0 版（linux-64/osx-64）；Apple Silicon 或需经典包则用 gatk4=4.6.2.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/gatk4/overview>（4.6.2.0 noarch）；`gatk4-main`：<https://anaconda.org/bioconda/gatk4-main>（4.7.0.0，linux-64/osx-64）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/gatk4:4.6.2.0--py310hdfd78af_1`（4.7.0.0 tag 未构建，以 quay 实时为准）
* **Singularity**：<https://depot.galaxyproject.org/singularity/gatk4%3A4.6.2.0--py310hdfd78af_1>
* **Docker（上游官方）**：`docker pull broadinstitute/gatk`（Docker Hub 官方镜像，tag 如 4.7.0.0）
* **GitHub 官方仓库**：<https://github.com/broadinstitute/gatk>（releases：4.7.0.0 的 gatk-4.7.0.0.zip）
* **brew**：`brew tap brewsci/bio && brew install gatk`（4.6.2.0 源码/zip 构建）
* 安装方式（本地）：`mamba create -n gatk -c conda-forge -c bioconda gatk4=4.6.2.0`（或 `gatk4-main=4.7.0.0`）

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* GATK3 时代：`UnifiedGenotyper`/`IndelRealigner`/`RealignerTargetCreator` 已随 GATK4 移除（nf-core/gatk 目录仍留 3 个旧模块）；`-T` 传工具名的旧语法改为 `gatk <Tool>`。
* GATK4 早期（4.0-4.2）文档常用 `--emitRefConfidence GVCF`（驼峰）写法，4.3+ 统一为 kebab-case `--emit-ref-confidence`；两者在 4.x 仍兼容但新写法为准。
* 旧教程 `-R /opt/biosoft/.../hg38.fa`、`/home/train/...` 等教学固定路径为历史残留，不再沿用（参考一律放用户目录并用变量 `$REF`）。
