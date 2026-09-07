# cutadapt 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方实现（snakemake-wrappers / nf-core）在本仓库不建源码目录，其链接、submodules、版本差异记录在本 README 与软件级 `meta.yaml.software_versions`。

---

## native 实现

# cutadapt / native 自包含实现

cutadapt 从高通量测序 reads 中去除接头（adapter）、引物、poly-A 等不需要的序列：二代测序建库时若插入片段短于读长，read 末端会读入 adapter 序列，需在下游分析前修剪；支持 SE/PE、5'/3'/anywhere 接头定位、质量修剪（-q）、长度过滤（-m/-M）、NextSeq 特殊质量修剪（--nextseq-trim），并支持 gz/bz2/xz 压缩格式（按扩展名自动识别），是 RNA-seq / 小 RNA / riboseq 等流程最常用的 read 预处理工具。官网：<https://cutadapt.readthedocs.io/>

基于 cutadapt CLI 的 Python 驱动包装（`source_type: custom`）。按 **cutadapt 实际 CLI** 暴露参数（`-a/-g/-b/-q/-m/-M/-o/-p/--cores/--nextseq-trim`），自动注入线程与临时目录：

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `trim` | 通用 reads 裁剪：3'/5'/anywhere 接头（SE/PE）+ 质量修剪 + 长度过滤 | ✅（--cores） |
| `adapter-removal` | 纯接头去除快捷入口（只给接头序列即可） | ✅（--cores） |

- 运行时需本地安装 `cutadapt` 二进制：推荐 `mamba create -n cutadapt-native -c conda-forge -c bioconda cutadapt=5.2`
- 容器/conda 由**官方镜像**提供（quay.io/biocontainers/cutadapt / bioconda cutadapt=5.2；本地不再自建容器，native=5.2，与 nf-core / snakemake-wrappers 官方 pin 一致；历史 apt 4.2-1 说明见 `meta.yaml.software_versions.cutadapt_native.note`）

## CLI 用法示例

```bash
# SE：去 3' adapter
python main.py trim -a AACCGGTT -o out.fastq in.fastq --threads 4

# PE：R1/R2 各自去 3' adapter
python main.py trim -a AGATCGGAAGAGC -A AGATCGGAAGAGC \
    -o out_R1.fastq.gz -p out_R2.fastq.gz in_R1.fastq.gz in_R2.fastq.gz --threads 8

# 5' adapter（锚定起始）+ 质量修剪 + 最短长度
python main.py trim -g '^ACACTCTTTCCCTACACG' -q 20 -m 30 \
    -o out.fastq in.fastq

# 纯接头去除（adapter-removal）
python main.py adapter-removal -a AACCGGTT -o out.fastq in.fastq

# Agent / Schema 自省
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n cutadapt -c conda-forge -c bioconda cutadapt=5.2
conda activate cutadapt
cutadapt --version
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install cutadapt
cutadapt --version   # 断言
```

> 宿主机直跑 `python main.py`（trim / adapter-removal 子命令）亦可使用文末「Conda 环境」节配方建环境（`name: cutadapt-native`，含 python/pyyaml，cutadapt 同为 5.2）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2 \
    cutadapt -a AACCGGTT -o /data/out.fastq /data/in.fastq
```

> 容器内为原生工具入口（cutadapt）；需要 Schema/自省/参数注入（trim / adapter-removal 子命令）时在**宿主机**（conda 装 cutadapt）运行 `python main.py <subcommand> ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull cutadapt.sif docker://depot.galaxyproject.org/singularity/cutadapt:5.2--py312hfabe715_2
apptainer run -B $PWD:/data -H /data cutadapt.sif \
    cutadapt -a AACCGGTT -o /data/out.fastq /data/in.fastq
```

### 4. 二进制包安装（pip / PyPI 官方分发，无容器依赖）

cutadapt 是纯 Python 工具（依赖 Python 3.9+），官方分发以 PyPI 为主：

```bash
python -m pip install cutadapt==5.2

# 验证安装
cutadapt --version
```

## 运行测试

```bash
bash test/run_test.sh
```

> 本机未装 cutadapt 时只跑驱动自省（`--list-commands` / `--schema`），脚本结尾 `ALL TESTS PASSED`。

## 实战示例：接头去除的参数体系与典型用法

cutadapt 支持 FASTA/FASTQ 及 gz/bz2/xz 压缩格式（按扩展名自动识别），SE/PE 均可修剪；运行统计报告输出到 stderr。以下为原生 cutadapt CLI 的参数体系；等价能力由 `native/main.py` 的 `trim` / `adapter-removal` 子命令提供（见上「CLI 用法示例」）。

### 1. 接头定位语法（作用于 R1 / SE；R2 用对应大写参数）

| 参数 | 说明 |
|------|------|
| `-a ADAPTER` | 3' 端接头：搜索 read 3' 端及其下游的接头并切除（默认至少 3 bp 重合即识别） |
| `-a ADAPTER$` | 锚定 3'：仅当接头位于 read 最末端时才修剪 |
| `-g ADAPTER` | 5' 端接头：接头出现在 5' 端即切除（常见于接头降解） |
| `-g ^ADAPTER` | 锚定 5'：仅当接头位于 read 开头才修剪（可容忍开头少量插入错配） |
| `-b ADAPTER` | anywhere：read 任意位置出现即修剪 |
| `-a FWD...REV` | 联合接头：两接头及其之间序列一并切除 |
| `-e ERR` | 接头匹配错误率上限；`--no-indels` 关闭插入/缺失错误容许 |

对应 R2（reverse）的大小写参数：`-A`（同 `-a`）、`-G`（同 `-g`）、`-B`（同 `-b`）；`-U` 对应 `-u`。一条 read 同时出现多个接头时，以最左侧的接头为准修剪。

### 2. Read 修饰与长度 / 质量过滤（trim 子命令）

| 参数 | 说明 |
|------|------|
| `-u N`（`--cut`） | 无条件切除 5' 端 N bp（`-u -5` 切 3' 端 5 bp） |
| `-q [5'cutoff,]3'cutoff` | 质量修剪（算法同 BWA）：单值作用于 3' 端；`-q 15,0` 表示 5' 端阈值 15、3' 端不修剪 |
| `-l N`（`--length`） | 从 3' 端将 read 截短至 N bp |
| `-m N` / `-M N` | 丢弃修剪后短于 N / 长于 N bp 的 read |
| `--too-short-output F` / `--too-long-output F` | 过短 / 过长 read 不丢弃，单独输出到 F |
| `--untrimmed-output F` | 未找到接头的 read 单独输出到 F |
| `--discard-trimmed` / `--discard-untrimmed` | 分别丢弃找到接头 / 未找到接头的 read |

同一条命令中多类操作按固定顺序执行：`--cut` → `-q` → 接头修剪（`-a/-g/-b` 等）→ `--length`；`-m/-M` 等过滤作用于上述处理完成后。

### 3. 双端配对修剪与统计报告

```bash
# 小写参数作用于 R1（forward），大写作用于 R2（reverse）；-o/-p 为两个配对输出
cutadapt -a ADAPTER_FWD -A ADAPTER_REV \
    -o out.1.fastq -p out.2.fastq reads.1.fastq reads.2.fastq \
    2> cutadapt.report.txt

# 不使用 -o 时：修剪结果写 stdout，统计报告写 stderr，可分别重定向 / 管道
cutadapt -a AACCGGTT input.fastq > output.fastq 2> report.txt
```

使用 `-p` 时 cutadapt 会校验两个文件是否配对（read 数不一致或文件名不匹配即报错）；read 名中的 `/1`、`/2` 后缀在配对检查中被忽略。

---

## snakemake 实现

本模块 `snakemake/` 目录同时承担两件事，使用前请区分：

### 1) 官方 snakemake-wrappers（说明层登记，不写源码）

> ⚠️ **强提示**：官方 `bio/cutadapt` wrapper 仅在本仓库做**说明 + 版本登记**（见软件级 `meta.yaml.software_versions.cutadapt_snakemake_wrappers`），**没有**把官方 wrapper 源码复制到本目录。真正执行靠 Snakemake 运行时解析 `wrapper:` 句柄（自动从中央 wrapper 缓存解析）：
>
> ```snakefile
> rule cutadapt_se:
>     input: "reads/{sample}.fastq.gz"
>     output: "trimmed/{sample}.fastq.gz", "qc/{sample}.txt"
>     params: adapters="-a AACCGGTT", extra=""
>     threads: 4
>     wrapper: "v9.17.0/bio/cutadapt/se"
> ```
>
> 请**不要**将本目录 `scripts/cutadapt.py` 作为 `wrapper_path` 传给 Snakemake——它是 riboseq 流程拆分的本地规则脚本（见下节）。

**官方子模块清单**（2026-09 抓取 https://github.com/snakemake/snakemake-wrappers/tree/master/bio/cutadapt ）：

| 子模块 | 用途 | 官方 conda pin |
|--------|------|----------------|
| `se` | single-end reads 接头裁剪 | `cutadapt =5.2` |
| `pe` | paired-end reads 接头裁剪（-o/-p/-A） | `cutadapt =5.2` |

- 官方仓库：https://github.com/snakemake/snakemake-wrappers/tree/master/bio/cutadapt
- wrapper 无 `snakemake-wrapper-utils` 依赖（仅 `snakemake.shell`）；官方最新 tag **v9.17.0**（2026-09 核实；本仓库全局登记 v3.13.0）
- 刷新子模块清单的命令样例：
  ```bash
  curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/cutadapt | python3 -c 'import json,sys; print("\n".join(sorted(x["name"] for x in json.load(sys.stdin))))'
  ```

### 2) 本地自定义规则（td2 式）

cutadapt 只有 trim 一个子命令；SE/PE 为同一 wrapper（`cutadapt.py`）的两种输入形态 → `snakemake/cutadapt_se.smk`（rule `cutadapt_se`）/ `snakemake/cutadapt_pe.smk`（rule `cutadapt_pe`），每文件一规则、config 驱动、可独立 dry-run：

- 配套文件（均平铺 `snakemake/`，`.smk` 同目录相对引用）：`cutadapt.yaml`（`bioconda::cutadapt==5.2`）、`cutadapt.py`（docker/native/conda 分支由共享 `modules/docker_wrapper.py` 提供）。
- config 契约与独立运行示例见各 `.smk` 头注；不依赖流程 `config["paths"]`/`containers`/`common.smk` 的 `samples`/`is_pe`。
  ```snakefile
  include: "modules/cutadapt/snakemake/cutadapt_se.smk"
  include: "modules/cutadapt/snakemake/cutadapt_pe.smk"
  ```

---

## nextflow / nf-core（说明层登记，不建目录）

官方 **nf-core 单模块 `CUTADAPT`**（modules/nf-core/cutadapt：`main.nf` + `meta.yml` + `environment.yml` + `tests/`，无按工具版本的子目录）：

> ⚠️ **强提示**：真正执行需在项目内执行 `nf-core modules install cutadapt`（安装到项目自身 `modules/nf-core/cutadapt/`），再 `include { CUTADAPT }`；本仓库不提供可 include 的 nf-core 代码。

- 官方目录：https://github.com/nf-core/modules/tree/master/modules/nf-core/cutadapt
- `environment.yml` pin：`bioconda::cutadapt=5.2`（与 snakemake-wrappers 一致）
- 模块维护：`environment.yml`/`meta.yml` 更新于 2025-12（PR #9551），`main.nf` 更新于 2026-04（PR #11260，apptainer 支持）
- 刷新信息：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/cutadapt`

---

## Conda 环境

```yaml
# snakemake 规则 conda 环境（modules/cutadapt/snakemake/cutadapt.yaml）
name: cutadapt
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - bioconda::cutadapt==5.2
```

```yaml
# native 本地 Conda 环境配方（可选；创建：mamba env create -n cutadapt-native ...）
name: cutadapt-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - cutadapt=5.2
  - pyyaml>=6.0
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/bioconda/cutadapt（`cutadapt=5.2`，2026-03 _1 / 2026-07 _2 重建）
- **Docker（quay.io / biocontainers）**：`docker pull quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2`（tag 示例，以 quay.io 实际列表为准；国内加速 `docker.1ms.run/biocontainers/cutadapt:5.2--py312hfabe715_2`）
- **Singularity**：https://depot.galaxyproject.org/singularity/cutadapt%3A5.2--py312hfabe715_2
- **本模块容器**：官方镜像优先，本地不再维护 Dockerfile/Apptainer.def（见 native 节）
- 安装方式（本地）：`mamba create -n cutadapt -c conda-forge -c bioconda cutadapt=5.2`
