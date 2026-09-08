# fastqc 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# fastqc / native 自包含实现

FastQC 是高通量测序原始 reads 的质量控制工具：输入 FASTQ/FASTA/BAM/SAM，为每个文件输出一份 HTML 报告与 zip 结果包（zip 内含各模块图表与 summary 原始数据），覆盖碱基质量分布、GC 含量、接头序列污染、重复序列、N 含量、k-mer 过载等常见质控维度，是测序数据下机后、进入下游分析前的第一道质检。官网：<https://www.bioinformatics.babraham.ac.uk/projects/fastqc/>

基于 bioconda `fastqc=0.12.1` + OpenJDK 17 的 Python 驱动包装：

* 自动注入 `-t` 线程（默认 4，可 CPU 核数协商）

* 通过 `JAVA_OPTS` 注入 JVM 最大堆内存（默认 8 GB）与 `TMPDIR`

* `-o` 不存在时自动创建

* `--nogroup` / `--extract` / `-f` / `-c` / `-a` / `-k` 等常见参数透传

* 运行时仍需本地安装 `fastqc` + `java`：安装方式见下方「环境安装」节

## CLI 用法示例

```bash
python main.py run sample_R1.fq.gz sample_R2.fq.gz -o qc_out --threads 8 --java-mem-mb 16384
python main.py run sample.fastq -f fastq --nogroup
python main.py --list-commands
python main.py --schema
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n fastqc -c conda-forge -c bioconda fastqc=0.12.1
conda activate fastqc
fastqc --version
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install fastqc
fastqc --version   # 断言
```

> 宿主机直跑 `python main.py run`（自动注入 JAVA_OPTS 堆内存与 TMPDIR）推荐用文末「Conda 环境」节配方建环境（`name: fastqc`，含 openjdk 17 / pigz / perl / coreutils），其中 fastqc 同为 0.12.1。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
    fastqc /data/sample_R1.fq.gz -o /data/qc_out --threads 8
```

> 容器内为原生工具入口（fastqc）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 fastqc + openjdk 17）运行 `python main.py run ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull fastqc.sif docker://depot.galaxyproject.org/singularity/fastqc:0.12.1--hdfd78af_0
apptainer run -B $PWD:/data -H /data fastqc.sif \
    fastqc /data/sample_R1.fq.gz -o /data/qc_out --threads 8
```

### 4. 二进制包安装（官方 zip 解压即用，无 conda / docker 依赖）

* **官网下载**：<https://www.bioinformatics.babraham.ac.uk/projects/fastqc/>（官方 Win/Linux zip 安装包；运行依赖系统 Java，请先装好 JRE 8+ 并将 java 加入 PATH）

```bash
# 下载并解压
wget https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip -P ~/software/
unzip ~/software/fastqc_v0.12.1.zip -d ~/software/
chmod +x ~/software/FastQC/fastqc
echo 'export PATH=$PATH:~/software/FastQC/' >> ~/.bashrc
source ~/.bashrc

# 验证安装
fastqc --version
```

## 运行测试

```bash
bash test/run_test.sh
```

## 实战示例：多样本批量 QC 与报告解读

FastQC 输入 FASTQ/FASTA/BAM/SAM，为每个输入文件生成一个 HTML 报告与一个 zip 结果包（zip 内含各模块图表与 summary 原始数据）。以下为原生 fastqc CLI 的典型用法；等价能力由 `native/main.py run` 子命令提供（见上「CLI 用法示例」）。

### 1. 批量运行（多文件 / 通配符）

```bash
mkdir -p fastqc_out    # 原生 CLI 的 -o 目录需事先创建（main.py run 会自动创建）
fastqc -t 8 -o fastqc_out sample_*.fastq.gz
```

FastQC 一次可接收多个文件或以通配符展开输入，逐文件产出 `<名字>_fastqc.html` 与 `<名字>_fastqc.zip`；文件较多时可加 `-q` 进入静默模式，避免进度刷屏。

### 2. 结果查看

浏览器打开 HTML；zip 解压后含全部 QC 图与 summary 数据。每个模块以颜色标记：绿色 √ 合格、黄色 ！警告、红色 × 不合格。指标虽多，通常先看「碱基质量」与「碱基含量分布」两项：二者合格则其余多数指标会随之通过；且不同数据类型（DNA / RNA 等）适用指标有差异，需结合实际数据分析。

使用浏览器查看生成的 HTML 报告（可直接打开 HTML 文件，或将报告目录置于本地/服务器 HTTP 站点后用浏览器访问）：

```bash
# 方式一：直接打开某个样本的 HTML 报告（file:// 协议即可）
firefox fastqc_out/sample_R1_fastqc.html

# 方式二：报告目录已通过 HTTP 提供服务时，用浏览器访问对应 URL
#（示例为站点根目录下部署的报告目录路径，请按实际部署位置调整）
firefox http://localhost/FastQC/raw_data/
```

### 3. 主要模块速查（报告解读）

| 报告模块 | 关注点（FastQC 判定） |
|---------|----------------------|
| Basic Statistics | 总 reads 数、读长、%GC（具物种特异性，如人类约 42%）、Encoding（Phred 编码版本推断） |
| Per base sequence quality | 各碱基位置质量箱线图；一般要求各位置 10% 分位 > Q20 |
| Per tile sequence quality | 各测序小孔（tile）间的质量偏离，偏高提示 flowcell 局部异常（气泡/杂质） |
| Per sequence quality scores | 平均质量分布，用于发现整体偏差的 reads；峰值 < Q27 警告、< Q20 不合格 |
| Per base sequence content | 各位点 A/T 与 G/C 差 >10% 警告、>20% 不合格；线图交织提示接头或过表达序列污染 |
| Per sequence GC content | 实测与理论分布偏离 >15% 警告、>30% 不合格，提示文库污染 |
| Per base N content | 某位置 N 比例 >5% 警告、>20% 不合格（N 为仪器无法判读的碱基） |
| Sequence Length Distribution | reads 长度一致性；长度差异大提示本次测序数据不可信 |
| Sequence Duplication Levels | 重复 reads >20% 警告、>50% 不合格（高深度 / 高表达富集数据偏高属正常） |
| Overrepresented sequences | 某序列占全部 reads >0.1% 警告、>1% 不合格（仅统计前 200,000 条 reads） |
| Adapter Content | 接头含量 >5% 警告、>10% 不合格；未提供 `-a` 自定义接头时按内置通用接头统计 |
| Kmer Content | k-mer 频率高于统计期望即为过表达（长度可 `-k` 2–10 调节） |

### 4. 多样本汇总（MultiQC）

在含多个 FastQC zip 的目录下运行 `multiqc .`，可聚合为一份总报告（亦支持 trimmomatic、bowtie 等软件结果），便于整体浏览与交付。

***

## snakemake 实现

# fastqc snakemake 本地规则（td2 式：每 rule 一个 .smk，config 驱动）

`snakemake/fastqc.smk`（rule `fastqc`）为单规则 config 驱动本地实现。当 snakemake-wrappers 官方 bio/fastqc 不满足特定需求（如强制 `-f fastq_bismark`、定制 contaminant/adapter 列表等）时使用。

* 配套文件（均平铺 `snakemake/`，`.smk` 同目录相对引用）：`fastqc.yaml`（bioconda fastqc==0.12.1）、`fastqc.py`（nf-core 风格 wrapper：tempdir 运行防并发竞争、`--memory` 按线程均摊、exec\_mode 三模式分派，依赖共享 `modules/docker_wrapper.py`）。

* 规则 config 驱动、可独立 dry-run（单输入文件，多样本由调用方逐文件赋 config）：

  ```bash
  snakemake -s modules/fastqc/snakemake/fastqc.smk \
      --config fastqc_input=s1_R1.fastq.gz --cores 4 --use-conda
  ```

  产物 `<fastqc_outdir>/<输入去扩展名>_fastqc.{html,zip}`；config 契约（exec\_mode/docker\_image/fastqc\_bin/extra/mem\_mb/fastqc\_input/fastqc\_outdir 等）见 `.smk` 头注。

***

## nextflow 实现

# fastqc nextflow local 自定义实现

仅作为占位：当 nf-core 官方 FASTQC 不符合特殊参数需求（例如自定义 -k / -c 污染序列、强制 format 等）时使用。

## 启用步骤

1. 打开本目录下的 `main.nf.template`，按参数需求定制为 `main.nf`；
2. 将本目录复制到用户项目的 `modules/local/fastqc/`；
3. 在 workflow 中：

```nextflow
include { FASTQC_LOCAL } from './modules/local/fastqc/main'
FASTQC_LOCAL( reads_ch )
```

1. 在本目录写好 `meta.yaml` / `module.json`（已预置骨架）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
name: fastqc
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - conda-forge::python>=3.10
  - bioconda::fastqc=0.12.1
  - conda-forge::openjdk=17.*
  - conda-forge::pigz
  - conda-forge::perl
  - conda-forge::coreutils
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/fastqc/overview>

* **Docker**：`docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/fastqc%3A0.12.1--hdfd78af_0>

* 安装方式（本地）：`mamba create -n fastqc -c conda-forge -c bioconda fastqc=0.12.1`

