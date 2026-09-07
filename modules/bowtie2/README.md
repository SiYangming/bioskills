# bowtie2 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake）的用法；官方 snakemake-wrappers 与 nf-core 子模块信息记录于此（不建目录，仅说明层）。安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# bowtie2 / native

Bowtie2 是快速、内存高效的短 reads 比对工具：基于 FM-index 将 SE/PE reads 比对到长参考序列，支持 gapped、局部（local）与双端比对模式，内存占用低、速度快，是基因组重测序、变异检测以及转录组无剪接定量（如 Bowtie2 + RSEM）等场景的常用比对器，配套 `bowtie2-build` 生成 .bt2 索引族。官网：<https://bowtie-bio.sourceforge.net/bowtie2/index.shtml>

自包含的 bowtie2 驱动实现（`source_type: custom`），二进制由**官方容器/conda**（quay.io/biocontainers/bowtie2 / bioconda bowtie2）提供。

## 能力

| 子命令     | 说明                                       | 线程      |
| ------- | ---------------------------------------- | ------- |
| `build` | bowtie2-build：参考序列 → .bt2 索引族            | ✅（默认 8） |
| `align` | bowtie2：SE(`-U`)/PE(`-1/-2`) reads → SAM | ✅（默认 4） |

## 快速开始

### 1. CLI 调用

```bash
# 建立索引（参考 FASTA -> bt2idx.1.bt2 ... bt2idx.rev.2.bt2）
python main.py build refs.fa bt2idx --threads 8
# 双端比对
python main.py align -x bt2idx -1 r1.fq.gz -2 r2.fq.gz -o out.sam --threads 8
# 单端比对（SAM 走 stdout 时省略 -o/-S）
python main.py align -x bt2idx -U single.fq.gz -o out.sam --threads 4
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

## 性能优化约定

* **线程**：`build` 默认 8 线程（CPU 密集），`align` 默认 4；用户显式 `--threads` 永远优先。

* **临时目录**：通过 `TMPDIR`（`meta.yaml.optimization.env_vars`，占位符 `{tmpdir}`）注入，避免污染工作目录。

* **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 实战示例：基因组重测序双端比对（建索引 → 比对）

以下为原生 CLI 的典型批量用法；等价能力由 `native/main.py` 的 `build` / `align` 子命令提供（见上「快速开始」）。

### 1. 建立参考索引

```bash
mkdir -p bowtie2_out
cd bowtie2_out

# 参考基因组 FASTA -> genome.1.bt2 ... genome.rev.2.bt2（索引前缀 genome）
bowtie2-build --threads 8 genome.fasta genome
```

### 2. 双端重测序比对（逐样本：read group + 统计日志）

```bash
# -1/-2 双端 reads；-S 输出 SAM；--rg 系列将 read group 写入 SAM 头；比对统计走 stderr，重定向为日志
bowtie2 -p 8 -x genome -1 sample1_1.fastq -2 sample1_2.fastq \
    -S sample1.sam --rg-id sample1 --rg "PL:Illumina" --rg "SM:sample1" \
    2> sample1.bowtie2.log

bowtie2 -p 8 -x genome -1 sample2_1.fastq -2 sample2_2.fastq \
    -S sample2.sam --rg-id sample2 --rg "PL:Illumina" --rg "SM:sample2" \
    2> sample2.bowtie2.log
```

### 3. 变异检测场景：校正后数据用严格阈值再比对

变异检测流程常先用宽松参数将 clean data 比对，数据校正（如 BLESS）后再以更严格阈值重比对：

```bash
bowtie2 -p 4 -x genome --score-min L,-0.3,-0.3 \
    --rg-id sample1 --rg SM:sample1 --rg PL:ILLUMINA \
    -1 sample1.corrected_1.fastq -2 sample1.corrected_2.fastq \
    -S sample1.corr.sam 2> sample1.corr.bowtie2.log
```

### 4. 参数说明

| 参数                             | 说明                                                   |
| ------------------------------ | ---------------------------------------------------- |
| `-x <basename>`                | 索引前缀（bowtie2-build 产出的 `genome.1.bt2` 等文件取 `genome`） |
| `-1` / `-2`                    | 双端 reads（mate1 / mate2）；单端用 `-U`                     |
| `-S <file>`                    | SAM 输出文件（缺省为 stdout）                                 |
| `-p N`（同 `--threads`）          | 线程数                                                  |
| `--rg-id <id>`                 | read group ID                                        |
| `--rg "SM:<样本>"` / `"PL:<平台>"` | read group 字段，可多次给出                                  |
| `--score-min L,-0.3,-0.3`      | 收紧得分阈值、仅保留高分比对（严格模式，用于校正后数据）                         |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bowtie2 -c conda-forge -c bioconda bowtie2=2.5.4
conda activate bowtie2
bowtie2 --version
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 2.5.5，与 meta 登记 2.5.4 略有差异（版本以 formula 为准）
brew install bowtie2
bowtie2 --version   # 断言
```

> 宿主机直跑 `python main.py`（build / align 子命令）亦可使用文末「Conda 环境」节配方建环境（`name: bowtie2-native`，含 python/pyyaml）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bowtie2:2.5.4--he96a11b_7
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bowtie2:2.5.4--he96a11b_7 \
    bowtie2-build /data/refs.fa /data/bt2idx --threads 8
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bowtie2:2.5.4--he96a11b_7 \
    bowtie2 -x /data/bt2idx -1 /data/r1.fq.gz -2 /data/r2.fq.gz -S /data/out.sam --threads 8
```

> 容器内为原生工具入口（bowtie2 / bowtie2-build）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bowtie2 或官方镜像同款 env）运行 `python main.py <subcommand> ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull bowtie2.sif docker://depot.galaxyproject.org/singularity/bowtie2:2.5.4--he96a11b_7
apptainer run -B $PWD:/data -H /data bowtie2.sif \
    bowtie2 -x /data/bt2idx -1 /data/r1.fq.gz -2 /data/r2.fq.gz -S /data/out.sam --threads 8
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

* **GitHub Releases**：<https://github.com/BenLangmead/bowtie2/releases>（官方分发 Linux/macOS 预编译 zip，文件名以 releases 页实际资产为准）
* https://sourceforge.net/projects/bowtie-bio/files/bowtie2/

```bash
# 下载并解压（以 2.5.4 Linux x86_64 为例；macOS 选 bowtie2-2.5.4-macos-arm64.zip）
wget https://github.com/BenLangmead/bowtie2/releases/download/v2.5.4/bowtie2-2.5.4-linux-x86_64.zip -P ~/software/
unzip ~/software/bowtie2-2.5.4-linux-x86_64.zip -d ~/software/
echo 'export PATH=$PATH:~/software/bowtie2-2.5.4-linux-x86_64/' >> ~/.bashrc
source ~/.bashrc

# 验证安装
bowtie2 --version
```

> 版本说明：native 统一 2.5.4（官方容器 quay.io/biocontainers/bowtie2:2.5.4--he96a11b\_7 / bioconda bowtie2=2.5.4，与 riboseq 流程同款），各实现版本差异见文末「版本差异声明」。

***

## snakemake 实现

# bowtie2 / snakemake（本地规则 + 官方 wrappers 参考）

### 本地拆分规则（td2 式：每 rule 一个 .smk，config 驱动）

| 文件                            | 规则              | 作用                                   |
| ----------------------------- | --------------- | ------------------------------------ |
| `snakemake/bowtie2_index.smk` | `bowtie2_index` | 参考 FASTA → `.bt2` 索引族（bowtie2-build） |
| `snakemake/bowtie2_align.smk` | `bowtie2_align` | reads（SE/PE）→ SAM（bowtie2 align）     |

* 配套文件（均平铺 `snakemake/`，`.smk` 同目录相对引用）：`bowtie2.yaml`（conda env）、`bowtie2_index.py` / `bowtie2_align.py`（wrapper，docker/native/conda 三模式分派，注入共享 `modules/docker_wrapper.py`）。

* 规则 **config 驱动、可独立运行**（不依赖流程 `samples`/`is_pe()`/`config["paths"]`），契约见各 `.smk` 头注。独立运行示例：

  ```bash
  snakemake -s modules/bowtie2/snakemake/bowtie2_index.smk \
      --config bowtie2_input_fasta=ref.fa bowtie2_index_prefix=bt2/bowtie2 --cores 8 --use-conda
  ```

* 两规则共用同一 `bowtie2_index_prefix` 时 include 两文件即可自动串联（index 产物为 align 输入）。

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> 本模块**不重写官方 wrapper 源码**。官方仓库 `bio/bowtie2/` 子模块如下（2026-09 抓取，以官方在线目录为准）：

| wrapper | wrapper 句柄                 | 环境 pin（master）                                              |
| ------- | -------------------------- | ----------------------------------------------------------- |
| align   | `vX.Y.Z/bio/bowtie2/align` | bowtie2=2.5.5, samtools=1.24, snakemake-wrapper-utils=0.9.0 |
| build   | `vX.Y.Z/bio/bowtie2/build` | bowtie2=2.5.5                                               |

引用示例（Snakefile）：

```python
rule bowtie2_align:
    input:
        reads=["reads_1.fastq", "reads_2.fastq"],
        idx=multiext("refs", ".1.bt2", ".2.bt2", ".3.bt2", ".4.bt2", ".rev.1.bt2", ".rev.2.bt2"),
    output:
        "mapped.sam"
    log: "logs/bowtie2_align.log"
    params:
        extra=""
    threads: 8
    wrapper: "v3.13.0/bio/bowtie2/align"
```

> ⚠️ 本模块未内置官方 wrapper 的 wrapper.py：Snakemake 运行时按 `wrapper:` 句柄解析（联网拉取中央 wrapper 缓存）；离线/私有环境缺失时请改用本模块 `snakemake/bowtie2_{index,align}.smk` 本地规则。
> 更新子模块清单的抓取命令：
> `curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/bowtie2 | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### nf-core 官方参考（Nextflow，说明层）

本模块未建 `nextflow/` 目录；nf-core 官方 `modules/nf-core/bowtie2/` 子模块（2026-09 抓取，以官方在线目录为准）：

| 子模块   | environment.yml 关键 pin                                        |
| ----- | ------------------------------------------------------------- |
| align | bioconda::bowtie2=2.5.4, htslib=1.21, samtools=1.21, pigz=2.8 |
| build | bioconda::bowtie2=2.5.4, htslib=1.21, samtools=1.21, pigz=2.8 |

组装 Nextflow DSL2 流程时执行 `nf modules install nf-core bowtie2 align build`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），随后：

```nextflow
include { BOWTIE2_ALIGN } from '../modules/nf-core/bowtie2/align/main'
include { BOWTIE2_BUILD } from '../modules/nf-core/bowtie2/build/main'
```

> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/bowtie2 | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

***

## 版本差异声明（native / snakemake-wrappers / nf-core）

| 实现                         | bowtie2 版本 | 来源                                                                                                            |
| -------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda）         | **2.5.4**  | official biocontainer：quay.io/biocontainers/bowtie2:2.5.4--he96a11b\_7 / bioconda bowtie2=2.5.4（riboseq 流程同款） |
| snakemake 本地规则 env         | 2.5.4      | bioconda（本模块 `snakemake/bowtie2.yaml`，与 riboseq 流程一致）                                                         |
| snakemake-wrappers v3.13.0 | 2.5.4      | bioconda（bio/bowtie2/align/environment.yaml）                                                                  |
| snakemake-wrappers master  | 2.5.5      | bioconda（autobump）                                                                                            |
| nf-core master             | 2.5.4      | bioconda（modules/nf-core/bowtie2/\*/environment.yml）                                                          |

> native 与 riboseq 流程统一 2.5.4（官方容器 quay.io/biocontainers/bowtie2:2.5.4--he96a11b\_7 / conda bowtie2=2.5.4）；原 apt 打包 2.5.0-3+b2 的历史差异已随本地容器移除。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bowtie2 native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 bowtie2-native.yml 后 mamba env create -f bowtie2-native.yml；在线推荐上方 mamba create 直装命令
name: bowtie2-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bowtie2=2.5.4     # 与 riboseq 流程一致；如需 apt 同款 2.5.0 请装二进制
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/bowtie2>

* **Docker**：`docker pull quay.io/biocontainers/bowtie2:2.5.4--he96a11b_7`（riboseq 流程同款）

* **Singularity**：<https://depot.galaxyproject.org/singularity/bowtie2%3A2.5.4--he96a11b_7>

* 安装方式（本地）：`mamba create -n bowtie2 -c conda-forge -c bioconda bowtie2=2.5.4`（官方镜像/conda 提供，本地不再自建容器）

* 上游 GitHub：<https://github.com/BenLangmead/bowtie2>

