# pilon 软件模块

> 汇总说明：本 README 合并各实现（native 等）的用法；安装方式见下方「环境安装」，容器与 conda
> 环境信息见文末「容器与 Conda 链接」。
>
> Pilon（Walker et al., PLoS ONE 2014）使用 Illumina 短读数据对基因组组装做**碱基水平修正**
> （polishing）与**变异检测**：官方发布物为单个 `pilon-<ver>.jar`（`java -jar` 运行），
> bioconda / Homebrew（brewsci/bio）另提供 `pilon` launcher 封装。官网
> <https://github.com/broadinstitute/pilon/>。本模块仅实现 `native/`（`correct` 子命令），
> 官方登记：**nf-core `modules/nf-core/pilon` 存在（单子模块，pin bioconda::pilon=1.24）、
> snakemake-wrappers `bio/pilon` 404**（2026-09 核实）→ 不建 nextflow/、snakemake/ 目录。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/pilon/` **存在**（2026-09 抓取返回 200），为单子模块（含
  `main.nf` / `meta.yml` / `environment.yml` / `tests`），`environment.yml` pin
  `bioconda::pilon=1.24`。Nextflow 场景请用 `nf modules install nf-core pilon` 安装到项目自身目录，
  不要直接引用本仓库示例；缺失时走本模块 `native/` 兜底。

* **snakemake-wrappers**：`bio/pilon` **不存在**（2026-09 抓取返回 404）。Snakemake 场景请容器化后
  直调 `pilon` / `java -jar`，或走本模块 `native/` 的 `correct` 子命令。

***

## native 实现

# pilon / native — 组装修正 / 变异检测驱动（Pilon 1.23）

Pilon 的本地自包含实现（`source_type: custom`、`type: native`）。上游为**单条命令** Java 工具
（`java -jar pilon-1.23.jar …`；bioconda/brew 封装为 `pilon …`）：

```
java -jar pilon-1.23.jar --genome genome.fa [--frags aln.bam] [--jumps aln.bam]
    [--unpaired aln.bam] [--bam aln.bam] [--tracks tracks.txt]
    [--fix all|snps|indels|local|bases|gaps] [--changes] [--output <prefix>]
    [--variant [--vcf]] [--outdir <dir>] [--threads <N>]
```

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `correct` | `java -jar pilon-1.23.jar --genome … --frags … --fix all --changes --output …` | 组装修正（碱基/indel/小片段变异）或 `--variant` 变异检测；`--threads` 自动注入 |

> * `--fix all` 修正所有类型；`--changes` 输出变化清单 `<output>.changes`；产物为 `<output>.fasta`。
> * `--frags/--jumps/--unpaired/--bam` 可按读对类型多给（至少给其一才能做修正）。
> * JVM 堆内存经 `JAVA_OPTS`（`-Xmx` 与 `-Djava.io.tmpdir`）注入，见 `meta.yaml optimization.env_vars`。

## 用法

```bash
# CLI 直跑（教学文档形态：--fix all --changes --output pilon01）
python main.py correct --genome genome00.fasta --frags bowtie2_RD.00.bam \
    --fix all --changes --output pilon01 --threads 8

# 变异检测模式（--variant --vcf）
python main.py correct --genome genome00.fasta --frags bowtie2_RD.00.bam --variant --vcf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。`--threads` 优先级：用户显式 >
`optimization.per_subcommand_threads` > `default_cpus`。

## 实战示例：Illumina 组装修正（多轮）

> 典型多轮修正流程如下；**等价能力由 `native/main.py` 的
> `correct` 子命令提供**（比对/排序/去重仍由 bowtie2 + samtools + picard 完成，见各自模块）。

```bash
# 0) 大写化序列（教学文档用 perl 完成；属性不变）
perl -e 'while (<>) { if (m/^>/) { print; } else { tr/atcg/ATCG/; print; } }' genome.fasta > genome00.fasta

# 1) 构建 bowtie2 索引 + 比对 Illumina 双端 + 排序去重 + 索引 + faidx
bowtie2-build --threads 8 genome00.fasta genome00
bowtie2 -x genome00 -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 \
    -I 0 -X 1000 --fr -S bowtie2.00.sam 2> bowtie2.00.log
samtools sort -@ 8 -o bowtie2.00.bam -O BAM bowtie2.00.sam
java -jar picard.jar MarkDuplicates I=bowtie2.00.bam O=bowtie2_RD.00.bam M=bowtie2_RD.00.metrics
samtools index bowtie2_RD.00.bam
samtools faidx genome00.fasta

# 2) 运行 Pilon 修正（等价能力由 native/main.py 的 correct 子命令提供）
java -Xmx100G -jar pilon-1.23.jar --genome genome00.fasta --frags bowtie2_RD.00.bam \
    --fix all --changes --output pilon01
# 等价驱动调用：
#   python main.py correct --genome genome00.fasta --frags bowtie2_RD.00.bam \
#       --fix all --changes --output pilon01

# 3) 多轮修正（用上一轮 pilon01.fasta 作为下一轮参考，重复比对 + 修正，通常 2–3 轮）
for i in 1 2 3; do
    ln -sf pilon0${i}.fasta genome0${i}.fasta
    bowtie2-build --threads 8 genome0${i}.fasta genome0${i}
    bowtie2 -x genome0${i} -1 illumina.1.fastq -2 illumina.2.fastq --score-min L,-0.3,-0.3 -p 8 \
        -I 0 -X 1000 --fr -S bowtie2.0${i}.sam 2> bowtie2.0${i}.log
    samtools sort -@ 8 -o bowtie2.0${i}.bam -O BAM bowtie2.0${i}.sam
    samtools index bowtie2.0${i}.bam && samtools faidx genome0${i}.fasta
    java -Xmx100G -jar pilon-1.23.jar --genome genome0${i}.fasta --frags bowtie2_RD.0${i}.bam \
        --fix all --changes --output pilon0$((i+1))
done
```

### 参数说明

| 参数（main.py / pilon） | 说明 |
| --- | --- |
| `--genome` | 待修正的参考组装 FASTA（必需） |
| `--frags` / `--jumps` / `--unpaired` / `--bam` / `--tracks` | 比对输入（可按读对类型多给） |
| `--fix` | 修正类型列表（`all`/`snps`/`indels`/`local`/`bases`/`gaps`）；默认 `all` |
| `--changes` / `--no-changes` | 是否输出变化清单 `<output>.changes`（默认开启） |
| `--output` / `--outdir` | 输出前缀 / 输出目录 |
| `--variant` / `--vcf` | 变异检测模式 / VCF 输出 |
| `--threads` | 线程数（驱动自动注入） |
| `JAVA_OPTS` | JVM 堆内存与临时目录（`-Xmx{mem_mb}m -Djava.io.tmpdir={tmpdir}`） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护：**bioconda → quay.io/biocontainers → depot.galaxyproject.org** 均有 pilon 镜像/包
（`quay.io/biocontainers/pilon:1.23--0`，2026-09 核实 tag 存在）→ 直接拉官方镜像即用。官方同时
提供**预编译 jar（GitHub release）**与**源码（GitHub）**两条路线，二者并列保留、预编译为首选。

### 1. 官方预编译二进制包（首选：GitHub release jar）

```bash
# 官方 release 单 jar（平台无关；本仓库已核实 1.23 sha256 =
# bde1d3c8da5537abbc80627f0b2a4165c2b68551690e5733a6adf62413b87185）
wget https://github.com/broadinstitute/pilon/releases/download/v1.23/pilon-1.23.jar -P ~/software/
echo 'export PATH=$HOME/software/pilon-1.23/bin:$PATH' >> ~/.bashrc   # 用 install.sh 会自动建 bin 封装

# 一键：下载 jar → 校验 sha256 → 生成 pilon 封装（java -jar）→ 写 PATH
bash native/install.sh --method jar          # 安装到 ~/software/pilon-1.23
pilon --version                              # 断言
```
（也可直接 `java -Xmx100G -jar pilon-1.23.jar --genome … `，见「实战示例」。）

### 2. 官方源码编译（并列保留）

官方源码见 <https://github.com/broadinstitute/pilon>（Gradle 工程，`gradle shadowJar` 产出
`pilon-<ver>.jar`）。本仓库未核实其构建流程细节，如需自编译请以仓库 README 为准；日常使用推荐
上方预编译 jar 或官方镜像。

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n pilon-native -c conda-forge -c bioconda pilon=1.23   # 自带 openjdk
conda activate pilon-native
pilon --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install pilon
pilon --version          # 断言（brew 当前 1.24，与 meta 登记 1.23 略有差异，版本以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `pilon`，
> 无 conda 且宿主有 java 时自动下载官方 release jar 到 `~/software/pilon-<ver>` 并生成 `pilon`
> 封装；版本默认 1.23，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/pilon:1.23--0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/pilon:1.23--0 \
    --genome /data/genome00.fasta --frags /data/bowtie2_RD.00.bam --fix all --changes --output pilon01
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull pilon.sif docker://depot.galaxyproject.org/singularity/pilon:1.23--0
apptainer run -B $PWD:/data -H /data pilon.sif \
    --genome /data/genome00.fasta --frags /data/bowtie2_RD.00.bam --fix all --changes --output pilon01
```

## 测试

```bash
bash modules/pilon/native/test/run_test.sh   # 自省 + argv 构造断言恒跑；java+jar/pilon 已装时真跑 --version 冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/pilon/overview>
* **官方 release**：<https://github.com/broadinstitute/pilon/releases>
* **Docker**：`docker pull quay.io/biocontainers/pilon:1.23--0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/pilon%3A1.23--0>
* **Homebrew**：`brew tap brewsci/bio && brew install pilon`（brewsci/bio 公式，当前 1.24）
* 安装方式（本地）：`mamba create -n pilon -c conda-forge -c bioconda pilon=1.23`

## 版本

* pilon **1.23**（native pin，与教学文档一致；bioconda 最新 1.24、nf-core pin 1.24）
* 构建路线：官方镜像/conda/release jar 提供（quay.io/biocontainers/pilon:1.23--0 / depot.galaxyproject.org；
  本地不自建容器）
* JVM 类工具：堆内存经 `JAVA_OPTS -Xmx{mem_mb}m` 注入（`default_mem_mb=16384`），临时目录
  `-Djava.io.tmpdir={tmpdir}`
