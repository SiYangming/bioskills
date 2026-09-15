# ea-utils 软件模块

> 汇总说明：本 README 说明 ea-utils 各实现（native 为主）的用法；安装方式见下方各节，容器与 conda 信息记录于此。

***

## native 实现

# ea-utils / native — 自包含 FASTQ 处理驱动

ea-utils 的本地自包含实现（`source_type: custom`、`type: native`）。覆盖 QIIME 1.x 双端拼接与常用 FASTQ 清洗：
`join_paired_ends.py` 的底层 `fastq-join`，以及 `fastq-mcf` / `fastq-stats` / `fastq-clipper`。

## 功能

| 子命令       | 对应程序         | 命令                                                                  | 作用                          |
| --------- | ------------ | ------------------------------------------------------------------- | --------------------------- |
| `join`    | `fastq-join` | `fastq-join <R1.fq> <R2.fq> [mate.fq] -o <out.%.fq>`                | 按双端重叠拼接 paired-end reads    |
| `mcf`     | `fastq-mcf`  | `fastq-mcf [options] <adapters.fa\|n/a> <reads.fq> [mates...]`       | 检测/切除接头引物 + 质量过滤             |
| `stats`   | `fastq-stats`| `fastq-stats [options] <fastq-file>`                                | reads/碱基/重复/逐碱基统计            |
| `clipper` | `fastq-clipper` | `fastq-clipper [options] <fastq-file> <adapters>`                | 去除冒号分隔的接头序列                 |

> 说明：ea-utils 各子程序均为**单线程**，不接受线程参数（`fastq-mcf` 的 `-p` 是接头差异百分比，非线程）；
> `--threads` 作为契约字段被接受但不注入命令行。

## 用法

```bash
# CLI 直跑
python main.py join R1.fastq R2.fastq -o joined.
python main.py mcf adapters.fa reads.fq -o clean.fq -q 30 -l 50
python main.py stats reads.fastq -x per_base.tsv
python main.py clipper reads.fastq AGATCGGAAGAGC -o clipped.fastq

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（ea-utils 无线程参数，`--threads` 仅契约记录）。

## 实战示例：QIIME 1.x 双端拼接与清洗

fastq-join 依据双端重叠把 paired-end reads 拼成单端序列，是 QIIME 1.x `join_paired_ends.py` 的核心引擎；
等价能力由 `native/main.py` 的 `join` 子命令提供，批量用法如下（与 `join_paired_ends.py` 对应）。

### 1. 批量双端拼接（逐样本 → 拼接产物汇总）

```bash
mkdir -p 02.join_paired_ends
for s in F3D0 F3D1 F3D2 F3D141 F3D142 F3D143
do
    python main.py join 00.qiime_data/${s}_L001_R1_001.fastq.gz \
                        00.qiime_data/${s}_L001_R2_001.fastq.gz \
                        -o 02.join_paired_ends/${s}.
done
# 产物：<s>.join（拼接）/ <s>.un1、<s>.un2（未拼接），即 fastq-join 的默认三件套
```

### 2. 接头切除 + 质量过滤（fastq-mcf）

```bash
python main.py mcf adapters.fa reads.R1.fq.gz reads.R2.fq.gz \
    -o clean.R1.fq.gz -o clean.R2.fq.gz -q 30 -l 50 --qual-mean 30
```

### 3. 参数说明（fastq-join / fastq-mcf）

| 参数    | 适用         | 说明                              |
| ----- | ---------- | ------------------------------- |
| `-o`  | join/mcf/clipper | join 为文件名模板（含 `%` 或后缀 join/un1/un2）；mcf 每个输入一个 |
| `-m`  | join       | 最小重叠长度（默认 6）                    |
| `-p`  | join/mcf/clipper | 允许的最大差异百分比（join 8 / mcf 10）    |
| `-v`  | join       | 校验 read id 匹配到第 C 个字符（Illumina 用空格） |
| `-r`  | join       | verbose stitch length report 输出 |
| `-q`  | mcf        | 触发碱基切除的质量阈值（默认 10）              |
| `-l`  | mcf        | 过滤后最小剩余长度（默认 19）                |
| `-s`  | mcf        | 接头最小匹配长度的 log 尺度（默认 2.2）        |
| `-t`  | mcf        | 接头切除 occurrence 阈值（默认 0.25）      |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。

> ⚠️ **版本差异**：bioconda 提供 `1.1.2.537` 与 `1.1.2.779` 两个版本；官方**容器（quay/depot）目前仅构建了
> 1.1.2.779**（`ea-utils:1.1.2.779--h9dd4a16_0`），`1.1.2.537` 无官方镜像 tag（2026-09 核实）。

### 1. Conda（包管理器安装）

```bash
mamba create -n ea-utils-native -c conda-forge -c bioconda ea-utils=1.1.2.537
conda activate ea-utils-native
fastq-join    # 断言
```

> Homebrew：homebrew-core 与 brewsci/bio 两源均**无 ea-utils 公式**（2026-09 核实 404），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `ea-utils`，
> 无 conda 时回退官方 GitHub 源码编译到 `~/software/ea-utils-<ver>` 并写 PATH；版本默认 1.1.2.537，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ea-utils:1.1.2.779--h9dd4a16_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ea-utils:1.1.2.779--h9dd4a16_0 \
    fastq-join R1.fastq R2.fastq -o joined.
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull ea-utils.sif docker://depot.galaxyproject.org/singularity/ea-utils:1.1.2.779--h9dd4a16_0
apptainer run -B $PWD:/data -H /data ea-utils.sif fastq-join /data/R1.fastq /data/R2.fastq -o /data/joined.
```

### 4. 官方源码编译（无官方预编译二进制）

ea-utils 官方**无预编译二进制包**（GitHub 无 release assets，仅源码仓库），宿主机无 conda/docker 时走源码编译：

* **官网**：<https://expressionanalysis.github.io/ea-utils/>

* **GitHub 源码**：<https://github.com/ExpressionAnalysis/ea-utils>

```bash
# 官方源码归档（GitHub tag 1.04.807；内容实为 1.1.2-779 源码，与 bioconda recipe 同源）
wget https://github.com/ExpressionAnalysis/ea-utils/archive/1.04.807.tar.gz -P ~/software/
tar zxf ~/software/1.04.807.tar.gz -C ~/software/
cd ~/software/ea-utils-1.04.807/clipper
make -j 4     # 依赖 g++ / gsl / zlib（apt: build-essential libgsl-dev zlib1g-dev）
echo 'export PATH=$PATH:'"$HOME"'/software/ea-utils-1.04.807/clipper' >> ~/.bashrc
source ~/.bashrc
fastq-mcf -h | grep Version   # 断言
```

> 说明：GitHub 官方唯一带 tag 的源码归档为 `1.04.807.tar.gz`，其 `ea-utils.spec` 实为 **1.1.2-779** 源码；
> 如需精确的 `1.1.2.537` 请走 conda 路线。亦可直接运行 `native/install.sh --method source` 自动完成上述步骤。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证为真实回归；fastq-join/clipper 已安装时追加真实执行
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/ea-utils/overview>

* **Docker**：`docker pull quay.io/biocontainers/ea-utils:1.1.2.779--h9dd4a16_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/ea-utils%3A1.1.2.779--h9dd4a16_0>

* 安装方式（本地）：`mamba create -n ea-utils -c conda-forge -c bioconda ea-utils=1.1.2.537`

## 版本

* ea-utils 1.1.2.537（bioconda::ea-utils=1.1.2.537；上游命名 1.1.2-537）

* 官方容器/quay/depot 当前仅 1.1.2.779（`ea-utils:1.1.2.779--h9dd4a16_0`）；1.1.2.537 仅 conda 提供

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/ea-utils / depot.galaxyproject.org；本地不维护容器配方）

* nf-core 子模块：`eautils/fastqstats`（bioconda::ea-utils=1.1.2.779）与 `ea-utils/gtf2bed`（仅 perl=5.26.2）

* snakemake-wrappers：官方无 `bio/ea-utils` / `bio/eautils`（2026-09 抓取 404）
