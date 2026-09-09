# picard 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

Picard 是一组 Java 命令行工具（官方发布物为单个 `picard.jar`），用于操作 SAM/BAM/CRAM/VCF/FASTQ：`MarkDuplicates`（标记/去除 PCR 重复）、`SortSam`（coordinate/queryname 排序）、`AddOrReplaceReadGroups`（写入 RG 标签）、`CollectInsertSizeMetrics`（插入片段分布统计）、`ValidateSamFile`（BAM 完整性校验）、`CreateSequenceDictionary`（参考 .dict）、`MergeSamFiles`（合并 BAM）、`SamToFastq`（BAM→FASTQ）。官网：<https://broadinstitute.github.io/picard/>；GitHub：<https://github.com/broadinstitute/picard>。

基于 bioconda / brew（picard-tools）/ 官方 `picard.jar` 的 Python 驱动包装：

* 子命令（小写）自动映射为真实 Picard 工具名（如 `markduplicates` → `MarkDuplicates`），构造 `I=/O=/M=` 风格参数
* 自动解析调用入口：优先 PATH 上的 `picard` launcher（conda / brew / biocontainer 均提供）；否则按 `PICARD_JAR` 环境变量 → conda share / `~/software` 常见位置定位 `picard-*.jar`，以 `java -jar` 调用（需宿主 java 17+）
* 经 `JAVA_TOOL_OPTIONS` 注入 JVM 最大堆内存（默认 8 GB）与 `-Djava.io.tmpdir` + `TMPDIR`
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 java / picard）
* 运行时需本地安装 `java` + `picard`：安装方式见下方「环境安装」

## CLI 用法示例

```bash
# MarkDuplicates（标记重复；加 --remove-duplicates 直接去除）
python main.py markduplicates -I sample.sorted.bam -O sample.dedup.bam \
    -M metrics.txt --remove-duplicates

# SortSam（queryname 排序，供转 FASTQ / markdup 使用）
python main.py sortsam -I sample.bam -O sample.queryname.bam --sort-order queryname

# AddOrReplaceReadGroups
python main.py addorreplacereadgroups -I sample.bam -O sample.rg.bam \
    --read-group-id s1 --sample-name s1 --library lib1 --platform ILLUMINA

# ValidateSamFile（SUMMARY 模式）
python main.py validatesamfile -I sample.bam -O validation.txt

# 自省
python main.py --list-commands
python main.py --schema
```

每个子命令支持 `--threads` / `--tmpdir` / `--dry-run` 运行期覆盖。

## 实战示例（BAM 预处理与 QC 标准流程）

以下为原生 Picard CLI（`picard` launcher 或 `java -jar picard.jar`）的典型用法；等价能力由 `native/main.py` 的子命令提供（见上「CLI 用法示例」，子命令自动映射工具名，无需手写 `I=/O=` 前缀以外参数）。

### 1. 多样本循环：加 RG → 去重（GATK Best Practices 前置）

```bash
for s in sampleA sampleB; do
  # 1) 排序 + 加 RG（若上游 BAM 无 RG/未排序）
  picard AddOrReplaceReadGroups I=${s}.bam O=${s}.rg.bam \
      RGID=${s} RGSM=${s} RGLB=lib1 RGPL=ILLUMINA
  picard SortSam I=${s}.rg.bam O=${s}.rg.sorted.bam SORT_ORDER=coordinate
  # 2) 标记（保留）重复 → 产出 metrics
  picard MarkDuplicates I=${s}.rg.sorted.bam O=${s}.dedup.bam M=${s}.dup_metrics.txt
  picard BuildBamIndex I=${s}.dedup.bam          # 建 .bai
done
```

### 2. QC 统计（批量 Collect*Metrics）

```bash
# 插入片段分布 + 直方图；校验 BAM
picard CollectInsertSizeMetrics I=sampleA.dedup.bam \
    O=sampleA.insert_metrics.txt H=sampleA.insert_hist.pdf
picard ValidateSamFile I=sampleA.dedup.bam MODE=SUMMARY O=sampleA.validate.txt
```

### 3. 参数说明

| 参数（驱动/工具） | 说明 |
| ---- | ---- |
| `-I / I=` | 输入 BAM/SAM/CRAM（MarkDuplicates 单输入；MergeSamFiles 可多个 `-I`） |
| `-O / O=` | 输出文件（BAM / metrics / 校验汇总，按工具） |
| `-M / M=` | MarkDuplicates / CollectInsertSizeMetrics 的 metrics 文本 |
| `REMOVE_DUPLICATES=true` | 直接删除重复（默认 false 仅加 `Duplicate` flag） |
| `SORT_ORDER=coordinate/queryname` | SortSam/MergeSamFiles 排序方式（queryname 是转 FASTQ 前提） |
| `RGID/RGSM/RGLB/RGPL` | RG 必填四件套；`RGPU`（flowcell.lane）、`RGCN`（中心）可选 |
| `H=` | CollectInsertSizeMetrics 直方图 PDF |
| `MODE=SUMMARY` | ValidateSamFile 汇总模式（快；默认 VERBOSE 很慢） |

> Picard 各工具完整参数以官方 tool docs（`picard <Tool> --help`）为准；metrics 首行以 `## METRICS CLASS` 开头可直接进 MultiQC。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 Picard（容器内含 OpenJDK + `picard` launcher）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n picard -c conda-forge -c bioconda picard=3.5.0
conda activate picard
picard --version   # 断言（jar 内置 build 版本号）
```

```bash
# 或用 Homebrew（macOS / Linux；homebrew-core 公式名为 picard-tools（非 picard），
# 安装后提供 `picard` 可执行入口，含 openjdk 依赖）
brew install picard-tools
picard --version   # 断言
# 注：brew picard-tools 当前 3.5.0，与 meta 登记 3.5.0 一致（公式名沿袭历史名 picard-tools）
```

> 宿主机直跑 `python main.py markduplicates|...` 推荐用文末「Conda 环境」配方建环境（`name: picard-native`）。本模块不维护本地安装脚本：conda/brew/官方 jar 三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/picard:3.5.0--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/picard:3.5.0--hdfd78af_0 \
    picard MarkDuplicates I=/data/sample.sorted.bam O=/data/sample.dedup.bam \
    M=/data/dup_metrics.txt REMOVE_DUPLICATES=true
```

> 容器内为 `picard` launcher（含 OpenJDK 底座）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 picard + openjdk）运行 `python main.py`。镜像 tag 全列表以 quay 页面为准。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull picard.sif docker://depot.galaxyproject.org/singularity/picard:3.5.0--hdfd78af_0
apptainer run -B $PWD:/data -H /data picard.sif \
    picard CollectInsertSizeMetrics I=/data/sample.bam O=/data/ins.txt H=/data/ins.pdf
```

### 4. 二进制包安装（官方 jar，无 conda / docker 依赖）

* **官方下载**：<https://github.com/broadinstitute/picard/releases>（release 资产为单个 `picard.jar`；3.x 需 Java 17+，请先装好 JRE/JDK 并将 `java` 加入 PATH）
* Picard 官方不提供独立 `picard` shell 脚本（jar 即二进制），conda/brew 的 launcher 只是 `java -jar` 的封装

```bash
wget https://github.com/broadinstitute/picard/releases/download/3.5.0/picard.jar -P ~/software/picard-3.5.0/
java -jar ~/software/picard-3.5.0/picard.jar MarkDuplicates --help
# main.py 自动识别：export PICARD_JAR=~/software/picard-3.5.0/picard.jar
```

> 验证安装：`picard MarkDuplicates --help`（或 `java -jar picard.jar ...`）应打印 USAGE（路径一律用户级 `~/software/`，禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：`modules/nf-core/picard/` 含 **28 个子模块**（addorreplacereadgroups/collect*/createsequencedictionary/markduplicates/mergesamfiles/sortsam/validatesamfile/samtofastq 等；2026-09-09 抓取核实），conda pin `bioconda::picard=3.5.0`。

```bash
nf-core modules install nf-core picard markduplicates   # 在用户项目安装官方子模块
# include: { PICARD_MARKDUPLICATES } from './modules/nf-core/picard/markduplicates/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core picard <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/picard/` 含 **16 个 wrapper**（addorreplacereadgroups/collect*/createsequencedictionary/markduplicates/mergesamfiles/revertsam/samtofastq/sortsam 等；2026-09-09 抓取核实），当前 master `markduplicates` pin `picard=3.5.0` + `samtools=1.24` + `snakemake-wrapper-utils=0.9.0`。

```python
rule picard_markduplicates:
    input: bam="mapped/{sample}.sorted.bam"
    output:
        bam="dedup/{sample}.bam",
        metrics="dedup/{sample}.metrics.txt"
    params: extra="REMOVE_DUPLICATES=true"
    wrapper: "v9.17.1/bio/picard/markduplicates"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/picard/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要 java / picard）
```

## 版本

* picard **3.5.0**（默认锚点；官方 GitHub release 3.5.0，2026-07-31 实测；bioconda / nf-core / snakemake-wrappers / brew picard-tools 均 3.5.0）
* Java 要求：Picard 3.x 需 Java 17+（2.x 为 Java 8+；conda/brew 包自动带 openjdk）
* 上游动态：2.27.x 时代结束于 2023 前后，3.x 起 release 仅提供 `picard.jar`（不再有 zip）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/picard / depot.galaxyproject.org）；本地不再自建容器配方

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# picard native Conda 环境配方（与 native/environment.yml 相同）
# 说明：Picard 为 noarch Java 包，openjdk 由其依赖自动带入；官方镜像即由 bioconda 本环境构建；
#      本地不再自建 Dockerfile/Apptainer.def。
name: picard-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - picard=3.5.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/picard/overview>（3.5.0 noarch Java 包）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/picard:3.5.0--hdfd78af_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/picard%3A3.5.0--hdfd78af_0>
* **GitHub 官方仓库**：<https://github.com/broadinstitute/picard>（releases：3.5.0 的 picard.jar）
* **brew**：`brew install picard-tools`（homebrew-core 公式名 picard-tools，提供 `picard`）
* 安装方式（本地）：`mamba create -n picard -c conda-forge -c bioconda picard=3.5.0`

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* 旧文档常见「wget picard-tools-2.x.zip 解压到教学目录后 `java -jar picard.jar`」的 2.x 流程；2.27.5 起官方改用 GitHub release 单 jar 分发，3.x 起要求 Java 17。2.x 的 `picard.jar` 仍可跑但工具选项以 3.x 为准。
* GATK3 时代 `AddOrReplaceReadGroups` 常用 `RGPL=ILLUMINA RGCN=BI` 等旧字段组合，与 3.x 一致。
* 文档中 `/home/train/...`、`/opt/biosoft/...` 教学固定路径为历史残留，不再沿用。
