# trimmomatic 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

# trimmomatic / native 自包含实现（Java CLI 驱动）

Trimmomatic 是灵活的 Illumina NGS reads 修剪工具（Java）：支持单端（SE）与双端（PE）模式，可去除接头序列（ILLUMINACLIP）、切除低质量碱基（LEADING / TRAILING / SLIDINGWINDOW / MAXINFO / CROP / HEADCROP / TAILCROP / AVGQUAL）、过滤短 reads（MINLEN）与 Phred 编码转换（TOPHRED33/64），处理 Phred+33/+64 的 FASTQ（`.gz` / `.bz2`）。官网：<http://www.usadellab.org/cms/?page=trimmomatic>；GitHub：<https://github.com/usadellab/Trimmomatic>。

基于 bioconda `trimmomatic=0.39`（noarch Java 包，自带 openjdk）的 Python 驱动包装：

* 自动解析调用入口：优先 PATH 上的 `trimmomatic` launcher（conda / brew / biocontainer 均提供）；否则按 `TRIMMOMATIC_JAR` 环境变量 → conda share / `~/software` 常见位置定位 `trimmomatic-*.jar`，以 `java -jar` 调用（需宿主 java 8+）
* 通过 `JAVA_TOOL_OPTIONS` 注入 JVM 最大堆内存（默认 8 GB）与 `-Djava.io.tmpdir`（JVM 自动读取，无需依赖 launcher 转发 JAVA_OPTS）+ `TMPDIR`
* 自动注入 `-threads`（PE 默认 4 / SE 默认 2，可 `--threads` 覆盖）
* `ILLUMINACLIP` 步骤若只给裸 adapter 文件名（如 `TruSeq3-PE.fa`），自动在 jar 同侧 `adapters/`、conda share、`cwd/adapters` 定位补全路径（0.39 需要完整路径；v0.40+ 官方已支持自动发现）
* 修剪步骤参数按字符串原样透传（如 `LEADING:3`、`SLIDINGWINDOW:4:15`、`TOPHRED33`）
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 java / trimmomatic）
* 运行时需本地安装 `java` + `trimmomatic`：安装方式见下方「环境安装」节

## CLI 用法示例

```bash
# PE 双端（标准去接头 + 质量/长度修剪；步骤字符串按序透传）
python main.py pe sample_R1.fq.gz sample_R2.fq.gz \
    out_P1.fq.gz out_U1.fq.gz out_P2.fq.gz out_U2.fq.gz \
    "ILLUMINACLIP:adapters/TruSeq3-PE.fa:2:30:10" LEADING:3 TRAILING:3 \
    SLIDINGWINDOW:4:15 MINLEN:36 --threads 8 --java-mem-mb 16384

# SE 单端
python main.py se sample.fq.gz out.fq.gz \
    "ILLUMINACLIP:TruSeq3-SE.fa:2:30:10" LEADING:3 TRAILING:3 MINLEN:36

# 自省
python main.py --list-commands
python main.py --schema
```

每个子命令支持 `--threads` / `--tmpdir` / `--java-mem-mb` / `--phred33` / `--phred64` / `--trimlog` / `--summary` / `--dry-run` 运行期覆盖。

## 实战示例（源自 Illumina 测序质控文档 §3 Trimmomatic）

以下为原生 Trimmomatic CLI（`java -jar trimmomatic-0.39.jar`，即 conda/官方 zip 解压后的运行方式）的典型用法；等价能力由 `native/main.py` 的 `pe` / `se` 子命令提供（见上「CLI 用法示例」，步骤字符串逐项透传，无需手写 `java -jar` 前缀）。

### 1. PE 双端标准流程（0.39 版，`TOPHRED33` 放在步骤末尾）

```bash
# 基因组 / 重测序 / 转录组数据通用：ILLUMINACLIP 去接头 → LEADING/TRAILING 去低质量端 → SLIDINGWINDOW → MINLEN
java -jar /path/to/trimmomatic-0.39.jar PE -threads 4 \
  sample_1.fastq sample_2.fastq \
  sample_1.clean.fastq sample_1.unpaired.fastq \
  sample_2.clean.fastq sample_2.unpaired.fastq \
  ILLUMINACLIP:/path/to/Trimmomatic-0.39/adapters/TruSeq3-PE-2.fa:2:30:10 \
  LEADING:5 TRAILING:5 SLIDINGWINDOW:4:15 MINLEN:50 TOPHRED33
```

说明：双端模式下 2 个输入 + 4 个输出（paired 两端都存活 / unpaired 仅一端存活，顺序为 R1-paired、R1-unpaired、R2-paired、R2-unpaired）；`TruSeq3-PE-2.fa`（含 Nextera 等通用接头）与 `TruSeq3-PE.fa` 均在官方 zip 的 `adapters/` 内，按建库试剂盒选型（HiSeq/MiSeq 用 TruSeq3，老 GA2 用 TruSeq2）。

### 2. SE 单端标准流程

```bash
java -jar /path/to/trimmomatic-0.39.jar SE -phred33 \
  sample.fastq sample.clean.fastq \
  ILLUMINACLIP:/path/to/Trimmomatic-0.39/adapters/TruSeq3-SE.fa:2:30:10 \
  LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
```

### 3. 多样本 Shell 循环批处理（转录组示例）

```bash
for i in sample_A_1.fastq sample_B_1.fastq; do
    s=${i/_1.fastq/}
    java -jar /path/to/trimmomatic-0.39.jar PE -threads 4 \
      ${s}_1.fastq ${s}_2.fastq \
      ${s}_1.clean.fastq ${s}_1.unpaired.fastq \
      ${s}_2.clean.fastq ${s}_2.unpaired.fastq \
      ILLUMINACLIP:/path/to/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10 \
      LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36 TOPHRED33
done
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `PE` / `SE` | 双端 / 单端模式 |
| `-threads N` | 线程数（0.39 置于模式词后、文件前） |
| `-phred33` / `-phred64` | 声明输入 Phred 编码（0.32+ 默认自动检测） |
| `ILLUMINACLIP:fa:seed:mismatch:score` | 去接头；`2:30:10` = 种子匹配数、palindrome 错配阈值、simple 比对分数阈值（可追加 `:minPalClipLen[:keepBoth]`） |
| `LEADING:Q` | 去除 5' 端质量 < Q 的碱基 |
| `TRAILING:Q` | 去除 3' 端质量 < Q 的碱基 |
| `SLIDINGWINDOW:win:avgQ` | 从 5' 滑动窗口（宽 4、均值 < 15 即截断） |
| `MINLEN:L` | 丢弃修剪后长度 < L 的 reads |
| `CROP:L` / `HEADCROP:N` / `TAILCROP:N` | 截断到长度 / 切除 5' 端 / 3' 端 N 个碱基（0.36+ 支持范围） |
| `AVGQUAL:Q` / `MAXINFO` / `BASECOUNT` | 平均质量过滤 / 自适应平衡 / 计数（0.30+/0.38+） |
| `TOPHRED33` / `TOPHRED64` | 质量编码转换（作为末尾步骤；0.33 及更早用 `-phred33` 位置参数，见「历史留存」） |

> 步骤按命令行出现顺序依次执行，官方建议接头切除（ILLUMINACLIP）放最前。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（容器内含 OpenJDK + `trimmomatic` launcher）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n trimmomatic -c conda-forge -c bioconda trimmomatic=0.39
conda activate trimmomatic
trimmomatic --help
# adapters 位于 env 内：$(conda info --base)/envs/trimmomatic/share/trimmomatic-*/adapters/
```

```bash
# 或用 Homebrew（macOS / Linux；homebrew-core 无此公式，公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio
brew install trimmomatic
trimmomatic --help   # 断言
# 注：brewsci/bio 公式为 0.39_1（源码 + ant 构建，依赖 openjdk@11），与 meta 登记 0.39 一致（_1 为 formula revision）
```

> 宿主机直跑 `python main.py pe|se` 推荐用文末「Conda 环境」节配方建环境（`name: trimmomatic-native`，含 trimmomatic=0.39，openjdk 由包依赖自动带入）。一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `trimmomatic`，无 conda 时下载官方 zip 到 `~/software/trimmomatic-0.39` 并生成 `bin/trimmomatic` launcher + 写 PATH；版本默认 0.39，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2 \
    trimmomatic PE -threads 4 \
    /data/sample_R1.fq.gz /data/sample_R2.fq.gz \
    /data/out_P1.fq.gz /data/out_U1.fq.gz /data/out_P2.fq.gz /data/out_U2.fq.gz \
    ILLUMINACLIP:/usr/local/share/trimmomatic/adapters/TruSeq3-PE.fa:2:30:10 \
    LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
```

> 容器内为 `trimmomatic` launcher（含 OpenJDK 底座，也可直接 `docker run ... trimmomatic SE ...`）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 trimmomatic + openjdk）运行 `python main.py pe|se ...`。镜像 tag 全列表（0.38--0/1、0.39--0/1/--hdfd78af_2、0.40--hdfd78af_0、0.41--hdfd78af_0 等）以 quay 页面为准；上游官方另发布 GHCR 容器 `ghcr.io/usadellab/trimmomatic:v0.40`（v0.40 起）。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（BioContainers 官方 Singularity 镜像源，tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull trimmomatic.sif docker://depot.galaxyproject.org/singularity/trimmomatic:0.39--hdfd78af_2
apptainer run -B $PWD:/data -H /data trimmomatic.sif \
    trimmomatic SE /data/sample.fq.gz /data/out.fq.gz \
    ILLUMINACLIP:/usr/local/share/trimmomatic/adapters/TruSeq3-SE.fa:2:30:10 \
    LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
```

### 4. 二进制包安装（官方 zip 解压即用，无 conda / docker 依赖）

* **官网**：<http://www.usadellab.org/cms/?page=trimmomatic>（页面确认 0.39 binary/source/manual 直链仍提供；**≥0.40 官方下载已迁移至 GitHub releases**：<https://github.com/usadellab/Trimmomatic/releases>，含官方容器 `ghcr.io/usadellab/trimmomatic:v0.40`）
* 运行依赖系统 Java（0.39 需 Java 8+，请先装好 JRE/JDK 并将 `java` 加入 PATH）

```bash
# 下载官方二进制 zip（含 trimmomatic-0.39.jar + adapters/）
wget http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip -P ~/software/
unzip ~/software/Trimmomatic-0.39.zip -d ~/software/

# 直接以 java -jar 运行
java -jar ~/software/Trimmomatic-0.39/trimmomatic-0.39.jar SE -h

# 或由 native/install.sh 生成 bin/trimmomatic launcher（推荐，含 PATH 写入）：
bash modules/trimmomatic/native/install.sh --method binary
```

> 验证安装：跑一个最小 SE 修剪应输出 `Completed successfully`（`install.sh` 内置该冒烟断言）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：**单模块** `modules/nf-core/trimmomatic/`（`environment.yml` + `main.nf` + `meta.yml` + `tests`，**无 PE/SE 子模块目录**；2026-09-08 抓取核实），conda pin `bioconda::trimmomatic=0.39`。

```bash
nf-core modules install nf-core trimmomatic    # 在用户项目安装官方模块
# include: { TRIMMOMATIC } from './modules/nf-core/trimmomatic/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core trimmomatic` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：**单 wrapper** `bio/trimmomatic/`（`wrapper.py` + `environment.yaml` + `meta.yaml` + `test`，**无子命令子目录**；2026-09-08 抓取核实），当前 master pin `trimmomatic=0.41` + `snakemake-wrapper-utils=0.9.0`（snakedeploy-bot 2026-07 autobump，比 native/nf-core 的 0.39 新）。

```python
rule trimmomatic_se:
    input:  "reads/{sample}.fastq.gz"
    output: "trimmed/{sample}.fastq.gz"
    params: extra="LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"
    threads: 4
    wrapper: "v9.16.0/bio/trimmomatic"   # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/trimmomatic"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + pe/se dry-run argv 构造回归；本机有 trimmomatic/java+jar 时追加 SE/PE 真实修剪回归
```

## 版本

* trimmomatic **0.39**（默认锚点；`bioconda::trimmomatic=0.39` noarch Java 包 / 官方 usadellab zip / nf-core pin / brewsci 0.39_1 一致）
* 上游动态：GitHub 官方 release 最新 **v0.40**（2025-08；0.40+ 官网下载迁移 GitHub，官方容器 `ghcr.io/usadellab/trimmomatic:v0.40`）；bioconda/quay 最新 **0.41**（2026-07 noarch；quay tag `0.41--hdfd78af_0`）。需要新版走 conda `trimmomatic=0.41` 或 quay 新 tag；官方 ≥0.40 二进制 URL/sha256 未核实
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/trimmomatic / depot.galaxyproject.org；本地不再自建容器配方）
* 与 nf-core 单模块（0.39）一致；snakemake-wrappers 当前 pin 0.41（差异见 `meta.yaml software_versions` note）

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# trimmomatic native Conda 环境配方（与 native/environment.yml 相同）
# 说明：Trimmomatic 为 noarch Java 包，openjdk 由其依赖自动带入；
#      官方镜像（quay.io/biocontainers/trimmomatic）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def（见上「环境安装」）。
name: trimmomatic-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - trimmomatic=0.39
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/trimmomatic/overview>（0.39/0.40/0.41 noarch；更早 0.32–0.36 有 linux-64/macOS-64 构建）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2`（tag 全列表含 0.38--0/1、0.39--0/1/--hdfd78af_2、0.40--hdfd78af_0、0.41--hdfd78af_0，以 quay 实时为准）
* **Docker（上游官方 GHCR，v0.40 起）**：`docker pull ghcr.io/usadellab/trimmomatic:v0.40`
* **Singularity**：<https://depot.galaxyproject.org/singularity/trimmomatic%3A0.39--hdfd78af_2>
* **GitHub 官方仓库**：<https://github.com/usadellab/Trimmomatic>（releases：v0.39 及更早 zip 资产 / v0.40 起新版）
* 安装方式（本地）：`mamba create -n trimmomatic -c conda-forge -c bioconda trimmomatic=0.39`

## 历史留存

以下为质控文档（§3 Trimmomatic）中的**历史教学用法归档**，仅作追溯对照；正式能力请走 `main.py` 的 `pe` / `se` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* **CentOS 8 / 通用（0.39）zip 安装**（旧文档将 zip 解压到 `/opt/biosoft/`，归档时改为 `~/software/`）：

  ```bash
  wget http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip -P ~/software/
  unzip ~/software/Trimmomatic-0.39.zip -d ~/software/
  ```

* **CentOS 6（0.33 旧版）**：`Trimmomatic-0.33.zip` 参数格式与 0.39 不同 —— **0.33 用 `-phred33` 位置参数**（紧跟 `PE -threads 4` 之后），0.39 用 `TOPHRED33`（末尾步骤）：

  ```bash
  java -jar ~/software/Trimmomatic-0.33/trimmomatic-0.33.jar PE -threads 4 -phred33 \
    V1.1.fastq V1.2.fastq V1.1.clean.fastq V1.1.unpaired.fastq V1.2.clean.fastq V1.2.unpaired.fastq \
    ILLUMINACLIP:~/software/Trimmomatic-0.33/adapters/TruSeq3-PE.fa:2:30:10 \
    LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
  ```

* 文档中 `/home/train/03.sequencing_data_quality_control/...`、`~/00.incipient_data/...` 为教学固定路径，非通用做法，不再沿用。
