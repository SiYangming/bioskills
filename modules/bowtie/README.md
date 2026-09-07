# bowtie 软件模块（v1 · legacy 短读无 gap 比对器）

> 汇总说明：本 README 合并各实现（native）的用法；官方 nf-core 子模块与 snakemake-wrappers 缺失情况记录于此（不建目录，仅说明层）。安装方式见下方「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# bowtie / native — 自包含短读无 gap 比对驱动

Bowtie1 是 Bowtie 系列的早期版本，一个**超快速、内存高效**的短读长比对工具，基于 FM-Index 将 reads **无 gap** 地比对到长参考序列，**适合 50bp 以下的短序列精确比对**（v1 已属 legacy 工具：不支持 gapped / 剪接比对；多数新场景建议改用 bowtie2，见文末「与 bowtie2 的区别提醒」）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/bowtie / bioconda bowtie）或官方 GitHub release zip 提供。

## 能力

| 子命令     | 说明                                          | 线程             |
| ------- | ------------------------------------------- | -------------- |
| `index` | bowtie-build：参考序列 → `.ebwt` 索引族（FM-Index）   | ✅（默认 8，原生默认 1） |
| `align` | bowtie：SE/PE reads → SAM（无 gap，`-S` 标志自动注入） | ✅（默认 4）        |

## 快速开始

### 1. 安装环境

```bash
# 路线 A：官方容器/conda（bioconda bowtie → quay.io/biocontainers/bowtie；v1 上游无官方
#          Dockerfile，由 biocontainer 自动构建覆盖；官方镜像内只含 bowtie 工具，main.py 驱动在宿主机跑）
docker pull quay.io/biocontainers/bowtie:<tag>        # tag 见文末「容器与 Conda 链接」
# 路线 B：本机二进制（一键脚本，conda 或官方 release zip 双路线，见下「环境安装 §1/§4」）
bash native/install.sh --help
# 路线 C：conda 兜底（HPC 无 root 时），配方见文末「Conda 环境」节
mamba create -n bowtie-native -c conda-forge -c bioconda bowtie=1.3.1 python=3.11 pyyaml
conda activate bowtie-native
```

### 2. CLI 调用

```bash
# 建立索引（参考 FASTA -> genome.1.ebwt ... genome.rev.2.ebwt）
python main.py index refs.fa genome --threads 8
# 双端比对（bowtie v1：SAM 默认写 stdout，-o 指定文件）
python main.py align -x genome -1 r1.fq.gz -2 r2.fq.gz -o out.sam --threads 8
# 单端比对
python main.py align -x genome -U single.fq.gz -o out.sam --threads 4
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制：

```bash
# Docker：工具直跑（官方镜像内只含 bowtie/bowtie-build/bowtie-inspect，main.py 驱动在宿主机运行）
docker pull quay.io/biocontainers/bowtie:<tag>        # tag 见 quay 页面 / 文末链接
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data quay.io/biocontainers/bowtie:<tag> \
  bowtie-build --threads 8 /data/refs.fa /data/genome
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data quay.io/biocontainers/bowtie:<tag> \
  bowtie --threads 8 -S -x /data/genome -1 /data/r1.fq.gz -2 /data/r2.fq.gz /data/out.sam

# Singularity/Apptainer
apptainer pull bowtie.sif docker://quay.io/biocontainers/bowtie:<tag>
# 或直链 depot.galaxyproject.org/singularity/bowtie%3A<tag>（与 quay 同 build tag）
```

> 容器内为原生工具入口（bowtie / bowtie-build）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bowtie 或官方镜像同款 env）运行 `python main.py <subcommand> ...`。

### 5. 测试

```bash
bash test/run_test.sh   # 自省必跑；本机装有 bowtie 时追加 index+align 最小回归
```

## 性能优化约定

* **线程**：`index` 默认 8 线程（bowtie-build 原生默认 1，CPU 密集），`align` 默认 4；用户显式 `--threads` 永远优先。

* **临时目录**：通过 `TMPDIR`（`meta.yaml.optimization.env_vars`，占位符 `{tmpdir}`）注入（bowtie v1 无原生 -T 参数），避免污染工作目录。

* **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 实战示例：短读（<50bp）无 gap 比对（建索引 → 比对）

Bowtie v1 基于 FM-index，内存占用低、速度极快，适合小 RNA、ChIP 等 50bp 以下短 reads 的**无 gap 精确比对**（如建库后预比对质控、单核苷酸多态性扫描等）。以下为原生 CLI 的典型批量用法；等价能力由 `native/main.py` 的 `index` / `align` 子命令提供（见上「快速开始」）。

### 1. 建立参考索引

```bash
mkdir -p bowtie_out
cd bowtie_out

# 参考基因组 FASTA -> genome.1.ebwt ... genome.rev.2.ebwt（索引前缀 genome）
bowtie-build --threads 8 genome.fasta genome
```

### 2. 单端短 reads 比对（逐样本：统计日志走 stderr）

```bash
# v1 中单端 reads 为位置参数；-S 输出 SAM；比对统计走 stderr，重定向为日志
bowtie -p 8 -S -x genome sample1_36bp.fastq sample1.sam 2> sample1.bowtie.log

bowtie -p 8 -S -x genome sample2_36bp.fastq sample2.sam 2> sample2.bowtie.log
```

### 3. 双端 reads 比对 + read group（SAM 头）

```bash
# -1/-2 双端 reads；末尾位置参数为 SAM 输出文件；--sam-RG 系列写入 SAM 头 @RG
bowtie -p 8 -S -x genome -1 sample1_1.fastq -2 sample1_2.fastq \
    sample1.sam --sam-RG ID:sample1 --sam-RG SM:sample1 --sam-RG PL:ILLUMINA \
    2> sample1.bowtie.log
```

### 4. 严格阈值场景：允许 0 错配 / 只报最优层

变异检测或接头污染后的严格复比，可用 `-v 0` 限定 0 错配，或 `--best --strata` 只保留最优层（配合 `-a` 报告全部最优比对）：

```bash
bowtie -p 4 -S -v 0 -x genome sample1.clean.fastq sample1.v0.sam 2> sample1.v0.log
bowtie -p 4 -S -a --best --strata -x genome sample2.clean.fastq sample2.best.sam 2> sample2.best.log
```

### 5. 参数说明

| 参数                    | 说明                                                                                 |
| --------------------- | ---------------------------------------------------------------------------------- |
| `-x <basename>`       | 索引前缀（bowtie-build 产出的 `genome.1.ebwt` 等文件取 `genome`）                               |
| `-1` / `-2`           | 双端 reads（mate1 / mate2）                                                            |
| `<reads>`             | 单端 reads 文件（位置参数，可逗号分隔多个文件）                                                        |
| `<hit>`               | SAM 输出文件（末尾位置参数，缺省为 stdout）                                                        |
| `-S` / `--sam`        | SAM 格式输出（驱动自动注入；需配 `--sam-nohead`/`--sam-nosq` 等可再透传）                              |
| `-p N`（同 `--threads`） | 线程数                                                                                |
| `-v <int>`            | 比对模式：允许 ≤V 个错配（0-3，忽略碱基质量）                                                         |
| `--best --strata`     | 保证只报告“最优层”比对（配合 `-a` 报告该层全部比对）                                                     |
| `--sam-RG <text>`     | SAM 头 @RG 字段（如 `ID:x` / `SM:x` / `PL:x`），可多次给出（v1 用 `--sam-RG`，非 bowtie2 的 `--rg`） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。**bowtie v1 上游无官方 Dockerfile**，由 quay.io/biocontainers/bowtie（bioconda 自动构建）覆盖，本地不再自建容器。

> 💡 一键安装：`bash native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `bowtie`，无 conda 时自动下载官方 GitHub release zip 到 `~/software/bowtie-<ver>` 并写 PATH；版本默认 1.3.1，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bowtie -c conda-forge -c bioconda bowtie=1.3.1
conda activate bowtie
bowtie --version        # bowtie-align-s version 1.3.1
```

```bash
# 或用 Homebrew（macOS / Linux；bowtie 公式在 brewsci/bio tap，需先添加 tap）
# brew 版本：brewsci/bio/bowtie 1.3.1（brew info 确认；与 meta 登记版本 1.3.1 一致）
brew tap brewsci/bio     # 首次使用需要
brew install bowtie
bowtie --version         # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bowtie:1.3.1--hb82490e_11
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bowtie:1.3.1--hb82490e_11 \
    bowtie-build --threads 8 genome.fasta genome
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bowtie:1.3.1--hb82490e_11 \
    bowtie --threads 8 -S -x genome -1 sample_1.fq -2 sample_2.fq sample.sam
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull bowtie.sif docker://depot.galaxyproject.org/singularity/bowtie:1.3.1--hb82490e_11
apptainer run -B $PWD:/data -H /data bowtie.sif bowtie-build --threads 8 \
    /data/genome.fasta /data/genome
# 注：bowtie v1 无 -U 标志，单端 reads 为位置参数；SAM 输出文件亦为末尾位置参数
apptainer run -B $PWD:/data -H /data bowtie.sif bowtie --threads 8 -S \
    -x /data/genome /data/reads.fq /data/out.sam
```

### 4. 二进制包安装（官方 release zip，无 conda / docker 依赖）

**官网**：[http://bowtie-bio.sourceforge.net/index.shtml](http://bowtie-bio.sourceforge.net/index.shtml)

**下载页**：[https://sourceforge.net/projects/bowtie-bio/files/bowtie/](https://sourceforge.net/projects/bowtie-bio/files/bowtie/)

**GitHub release**：[https://github.com/BenLangmead/bowtie](https://github.com/BenLangmead/bowtie)

官方二进制已迁移至 **GitHub release** 分发（旧 sourceforge 下载页仍保留镜像，但 GitHub 为当前维护地址）。当前版本 1.3.1，与 `software_versions` 对齐：

```bash
# 下载官方 release zip（本机为 linux x86_64 示例；另有 linux-aarch64 / macos-x86_64 资产）
wget https://github.com/BenLangmead/bowtie/releases/download/v1.3.1/bowtie-1.3.1-linux-x86_64.zip \
    -P ~/software/

# 解压安装（解压到用户目录后加 PATH 即可，无需 root）
unzip ~/software/bowtie-1.3.1-linux-x86_64.zip -d ~/software/
echo 'export PATH=$PATH:~/software/bowtie-1.3.1-linux-x86_64/' >> ~/.bashrc
source ~/.bashrc

# 验证安装
bowtie --version
```

> 💡 推荐直接使用 `native/install.sh --method binary`（默认前缀 `~/software/bowtie-1.3.1`，解压即用 + 自动写 PATH，等价上面手工步骤的“用户级”版本）。

## 测试

```bash
bash test/run_test.sh   # 自省必跑；本机装有 bowtie 时追加 index+align 最小回归
```

## 版本

* bowtie 1.3.1（bioconda::bowtie=1.3.1，v1 最终版本）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/bowtie / depot.galaxyproject.org；本地不再自建容器）

* 与 nf-core 子模块 bowtie/align + bowtie/build 的 bioconda pin 一致（bowtie=1.3.1）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/bowtie/` 子模块（2026-09 在线核实；以官方在线目录为准）：

| 子模块   | environment.yml 关键 pin                             |
| ----- | -------------------------------------------------- |
| align | bioconda::bowtie=1.3.1, htslib=1.21, samtools=1.21 |
| build | bioconda::bowtie=1.3.1, htslib=1.21, samtools=1.21 |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core bowtie align build`（安装到项目自身 `modules/nf-core/`，
> 不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { BOWTIE_ALIGN } from '../modules/nf-core/bowtie/align/main'
> include { BOWTIE_BUILD } from '../modules/nf-core/bowtie/build/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/bowtie | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/bowtie`（2026-09 抓取 `bio/` 目录下仅有 bowtie2，`bio/bowtie` 404）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `bowtie_native` 为兜底，或参照 bowtie2 模块自行维护本地 `snakemake/bowtie_{index,align}.smk` 规则（td2 式）。

> 抓取命令：`curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/bowtie`

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | bowtie 版本   | 来源                                                                                                           |
| ------------------ | ----------- | ------------------------------------------------------------------------------------------------------------ |
| native（官方容器/conda） | **1.3.1**   | official biocontainer：quay.io/biocontainers/bowtie:1.3.1--hb82490e\_11（2026-06 build）/ bioconda bowtie=1.3.1 |
| nf-core master     | 1.3.1       | bioconda::bowtie=1.3.1（modules/nf-core/bowtie/{align,build}/environment.yml，含 htslib=1.21、samtools=1.21）     |
| snakemake-wrappers | 官方无 wrapper | bio/bowtie 404（2026-09）；bio/ 仅 bowtie2                                                                       |

> bowtie v1 已停止新功能开发（最终版 1.3.1，2019 年后仅维护）；三条路线版本一致，均为 1.3.1。

## 与 bowtie2 的区别提醒

| 维度         | bowtie（v1，本模块）                                | bowtie2（modules/bowtie2）               |
| ---------- | --------------------------------------------- | -------------------------------------- |
| 定位         | **legacy** 短读工具：无 gap 比对，适合 **<50bp** 短序列精确匹配 | 现代主流：支持 gapped / local / 双端，长读长（数百 bp） |
| 索引         | `.ebwt` 族（bowtie-build，small/large 自动）        | `.bt2` 族（bowtie2-build）                |
| 输出         | `-S` 无参标志 + 末尾 `<hit>` 位置参数写文件                | `-S <file>` 直接指定 SAM 文件                |
| 单端 reads   | 位置参数（无 `-U`）                                  | `-U <file>`                            |
| read group | `--sam-RG ID:x`（可多次）                          | `--rg-id x` / `--rg "SM:x"`            |
| 报告模式       | 默认等价 `-k 1`；`-a/-k/-m/--best/--strata`        | `-k N` / `-a` / `--score-min` 等        |
| 场景建议       | 极短 reads 精确比对 / 早期流程复现                        | **大多数新场景推荐使用 bowtie2**                 |

> 训练材料中 Bowtie1 常与 TopHat 时代的 RNA-seq 流程捆绑，属于历史链路；做新项目时请优先评估 bowtie2 / HISAT2 / BWA。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bowtie native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 bowtie-native.yml 后 mamba env create -f bowtie-native.yml；在线推荐上方 mamba create 直装命令
name: bowtie-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bowtie=1.3.1
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/bowtie>

* **Docker**：`docker pull quay.io/biocontainers/bowtie:1.3.1--hb82490e_11`（bowtie v1 无官方 Dockerfile，由 biocontainer 自动构建）

* **Singularity**：<https://depot.galaxyproject.org/singularity/bowtie%3A1.3.1--hb82490e_11>

* 安装方式（本地）：`mamba create -n bowtie -c conda-forge -c bioconda bowtie=1.3.1`，或 `bash native/install.sh`

* 上游 GitHub：<https://github.com/BenLangmead/bowtie（release> 资产：`bowtie-1.3.1-{linux-x86_64,linux-aarch64,macos-x86_64}.zip`）

