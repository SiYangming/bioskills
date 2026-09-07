# ultra 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# ultra / native

自包含的 uLTRA 驱动实现（`source_type: custom`），命令逻辑对应 `native/ULTRA_align.py`（历史实现，见下）与正式入口 `native/main.py`；Snakemake 规则见下方独立章节。

uLTRA 是长读长转录组 reads（PacBio Iso-Seq / ONT）的剪接比对工具：以 GTF 外显子注释为引导，基于 minimap2 预过滤 + NAM（maximal exact matches）外显子连接搜索完成 splice alignment，对小外显子比对尤其准确；核心能力为 index（GTF 转录组索引）与 align（reads → SAM），运行时依赖 minimap2 / namfinder / samtools（bioconda 包名 `ultra_bioinformatics`，二进制 `uLTRA`）。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `gunzip` | 解压 .gz 文件（`gzip -cd <in.gz> > <out>`） | — |
| `index` | `uLTRA index <fasta> <gtf> <outdir> [--disable_infer]`，产出 `*.pickle` / `*.db` | 8（调度提示） |
| `align` | `uLTRA align <genome> <reads> <outdir> --t N --prefix <p> --index <dir>` 后接 `samtools sort` → BAM | ✅ |
| `sort` | GTF 排序 `sort -k1,1 -k4,4n`（index 前置步骤） | — |

运行前提：`uLTRA`、`samtools`、`minimap2`、`namfinder` 需在 PATH（align 子命令会预检依赖）。

## 快速开始

### 1. CLI 调用

```bash
# 解压参考/reads
python main.py gunzip genome.fa.gz -o genome.fa
# GTF 排序（index 前置）
python main.py sort genes.gtf --outdir . --prefix genes
# 建索引（默认 --disable_infer）
python main.py index genome.fa genes.sorted.gtf idx_dir
# 比对 + samtools sort -> BAM
python main.py align genome.fa reads.fa aln_dir --index idx_dir --prefix sample --threads 8
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

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda（宿主机直跑 main.py / HPC 无 root）

```bash
mamba create -n ultra-native -c conda-forge -c bioconda python=3.11 ultra_bioinformatics=0.1 minimap2 namfinder samtools pyyaml   # 配方见文末「Conda 环境」节
conda activate ultra-native
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ultra_bioinformatics:0.1--pyh7cba7a3_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
# 镜像入口为原生 uLTRA（仅工具，无 main.py）；align 产物 SAM 的 sort 由宿主机 samtools 完成
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ultra_bioinformatics:0.1--pyh7cba7a3_0 index \
    /data/genome.fa /data/genes.sorted.gtf /data/idx_dir --disable_infer
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ultra_bioinformatics:0.1--pyh7cba7a3_0 align \
    /data/genome.fa /data/reads.fa /data/aln --index /data/idx_dir --t 8 --prefix sample
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull ultra.sif docker://depot.galaxyproject.org/singularity/ultra_bioinformatics:0.1--pyh7cba7a3_0
apptainer run -B $PWD:/data -H /data ultra.sif index \
    /data/genome.fa /data/genes.sorted.gtf /data/idx_dir --disable_infer
apptainer run -B $PWD:/data -H /data ultra.sif align \
    /data/genome.fa /data/reads.fa /data/aln --index /data/idx_dir --t 8 --prefix sample
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

uLTRA 以 Python 包形式分发（bioconda `ultra_bioinformatics` / PyPI `ultra-bioinformatics`），官方 GitHub 仓库提供 INSTALL.sh 一键安装（自动建 conda env）；GitHub release 不附预编译二进制，源码安装需另取 namfinder、minimap2 并置于 PATH：

* **官方 GitHub**：<https://github.com/ksahlin/uLTRA>（含 INSTALL.sh 安装脚本与使用文档）

* **Bioconda 页面**：<https://bioconda.github.io/recipes/ultra_bioinformatics/README.html>

* **PyPI**：`pip install ultra-bioinformatics`

```bash
# 方式一：conda（官方推荐；minimap2/namfinder/samtools 同环境安装）
mamba create -n ultra -c conda-forge -c bioconda ultra_bioinformatics=0.1 minimap2 namfinder samtools
conda activate ultra

# 方式二：官方 INSTALL.sh 源码安装（克隆仓库后运行）
git clone https://github.com/ksahlin/uLTRA.git --depth 1 && cd uLTRA
./INSTALL.sh ~/software/ultra_install

# 验证安装
uLTRA --help
```

> 官方镜像/conda 包内为原生 uLTRA 入口（仅工具，无 main.py）；需要 Schema/自省/参数注入时在**宿主机**（conda env，见上）运行 `python main.py <subcommand> ...`（见上「快速开始」）。

## 性能优化约定

- **线程**：`index` / `align` 默认 8 线程（CPU 密集）；`align` 会把 `--t` 同时注入 uLTRA 与
  `samtools sort --threads`；用户显式 `--threads` 永远优先。
- **临时目录**：中间文件统一落在 `outdir` / `$TMPDIR`（`--tmpdir` 可覆盖），避免污染工作目录。
- **依赖路径**：`align` 自动把 minimap2 / namfinder / samtools 所在目录并入 PATH（镜像内为 /opt/conda/bin）。

## 子命令与实现来源的对应关系

| 本技能子命令 | 实现来源 |
|--------------|----------|
| `gunzip` | `ULTRA_align.py:subcmd_gunzip`（Snakemake 侧复用 `modules/gunzip`，无专属 smk） |
| `index` | `ULTRA_align.py:subcmd_index` + `snakemake/ultra_index.smk` |
| `align` | `ULTRA_align.py:subcmd_align` + `snakemake/ultra_align.smk` |
| `sort` | `ULTRA_align.py:subcmd_sort` + `snakemake/ultra_sort_gtf.smk` |

## 历史留存

供追溯对照的原始实现脚本与 `main.py` 同存于 `native/`，**正式入口为 `main.py`**。

- `ULTRA_align.py`


---

## snakemake 实现

# ultra / snakemake / local — 自定义 Snakemake 实现（td2 式）

> 本目录为 snakemake-wrappers 官方缺失（bio/ultra 404）时的 **Snakemake 自维护规则**。
> 按 td2 式规范组织为**每 rule 一个 config 驱动 `.smk`**，不依赖 `workflow/lib/helpers.py`
> 与 `SAMPLES / {species} / {sample}` 层级：`.gz` 参考/reads 由 wrapper 内联自动解压，
> GTF 排序独立成前置规则；无物种级 `prepare_genome / prepare_gtf` 单独规则。

## 文件与规则清单

| 文件 | 规则 | 作用 | 环境 |
|------|------|------|------|
| `ultra_sort_gtf.smk` | `ultra_sort_gtf` | `sort -k1,1 -k4,4n` → `<in>.sorted.gtf`（index 前置） | 系统 PATH（无 conda env） |
| `ultra_index.smk` + `ultra_index.py` | `ultra_index` | `uLTRA index <fa> <gtf> <outdir> [--disable_infer]` → `*.pickle/*.db` + `done` | `ultra.yaml` |
| `ultra_align.smk` + `ultra_align.py` | `ultra_align` | `uLTRA align ... --index ./` + `samtools sort` → BAM | `ultra.yaml` |

- `ultra.yaml`：同目录 conda 环境（`bioconda::ultra_bioinformatics=0.1` + `samtools`；minimap2 /
  namfinder 为 ultra_bioinformatics 的运行时依赖，随包自动安装）。
- 执行指令：`sort_gtf` 为纯单条命令用 `shell:` 一行；index / align 含 `.gz` 解压、索引复制、
  排序清理等多步逻辑，用 `script:` + 同目录 wrapper `.py`（内部再以 `shell()` 执行子命令）。
- `gunzip` 子命令在 Snakemake 场景复用 `modules/gunzip`（gzip 系统工具），不设专属 smk。

## 使用方式

```python
# Snakefile 中分别 include（可按需 use rule 重命名避免规则冲突）
include: "modules/ultra/snakemake/ultra_sort_gtf.smk"
include: "modules/ultra/snakemake/ultra_index.smk"
include: "modules/ultra/snakemake/ultra_align.smk"

rule all:
    input:
        os.path.join(config["ultra_index_dir"], "done"),
        os.path.join(config["ultra_align_dir"], config["ultra_prefix"] + ".bam")
```

config 契约与独立运行示例见各 `.smk` 头部（软件级 `meta.yaml` 的
`execution.snakemake_include_hint` 亦汇总）。

### 独立运行示例

```bash
# 1) GTF 排序（index 前置；sort 走系统 PATH，无需 --use-conda）
snakemake -s modules/ultra/snakemake/ultra_sort_gtf.smk \
    --config ultra_gtf=refs/genes.gtf ultra_gtf_sorted=refs/genes.sorted.gtf --cores 1
# 2) 建索引（.gz 参考自动解压）
snakemake -s modules/ultra/snakemake/ultra_index.smk \
    --config ultra_index_fasta=refs/genome.fa.gz ultra_gtf=refs/genes.sorted.gtf \
    ultra_index_dir=results/ULTRA/INDEX --cores 8 --use-conda
# 3) 比对 + samtools sort -> BAM
snakemake -s modules/ultra/snakemake/ultra_align.smk \
    --config ultra_genome=refs/genome.fa ultra_reads=reads/sample.fa \
    ultra_index_dir=results/ULTRA/INDEX ultra_prefix=sample --cores 8 --use-conda
```

## 需要的配置（在 Snakefile 中先声明，或用 --config 顶层覆盖）

```python
config.setdefault("exec_mode", "conda")            # conda | docker | native
config.setdefault("ultra", {})
config["ultra"].setdefault("docker_image", "")     # exec_mode=docker 时必填
config["ultra"].setdefault("ultra_bin", "uLTRA")   # exec_mode=native 时走该路径
config["ultra"].setdefault("index_args", "--disable_infer")
config["ultra"].setdefault("align_args", "")
config.setdefault("samtools", {})
config["samtools"].setdefault("samtools_bin", "samtools")
config["samtools"].setdefault("sort_args", "")
# 文件键（亦可用 --config 覆盖；见各 .smk 头注）
config.setdefault("ultra_index_fasta", "refs/genome.fa.gz")   # index：参考 FASTA（可 .gz）
config.setdefault("ultra_gtf", "refs/genes.sorted.gtf")       # index：已排序明文 GTF
config.setdefault("ultra_index_dir", "results/ULTRA/INDEX")
config.setdefault("ultra_genome", "refs/genome.fa")           # align：参考 FASTA（可 .gz）
config.setdefault("ultra_reads", "reads/sample.fa")           # align：reads（可 .gz）
config.setdefault("ultra_align_dir", "results/ULTRA")
config.setdefault("ultra_prefix", "sample")                   # align：BAM 前缀
```

## Snakemake 规则拆分说明

- 规则拆为 `ultra_sort_gtf.smk` / `ultra_index.smk` / `ultra_align.smk` 三个单规则文件
  （td2 式 config 驱动）。
- 无独立 `prepare_genome` / `prepare_gtf` 规则：`.gz` 参考 FASTA 由 index/align wrapper
  内联自动解压（与 `native/main.py` 行为一致）；GTF 去注释/解压由调用方准备
  （`sort_gtf` 只接收明文已去注释 GTF，`.gz` 先用 `modules/gunzip`）。
- `ultra_align` 的 reads 与索引依赖使用显式 config 键：索引依赖 `ultra_index_dir/done`
  （`ultra_index` 规则产物）。
- 条件分支与多步逻辑（`.gz` 解压 / 索引复制 / sort / 清理）放在同目录 wrapper `.py` 中；
  `sort_gtf` 为纯 `shell:` 一行（stderr 进 log）。
- 规则统一声明 `conda: "ultra.yaml"`（同目录相对名）；docker/native 由 `exec_mode` +
  `docker_wrapper_binary` 在 wrapper 内解析。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# ultra native Conda 环境配方（兜底：HPC 无 root / 非容器场景）
# 离线兜底：可另存为 ultra-native.yml 后 mamba env create -f ultra-native.yml；在线推荐上方 mamba create 直装命令
# 注意：Debian apt 无 ultra 包，uLTRA 仅由 bioconda 提供；minimap2 / namfinder /
#       samtools 为 uLTRA 运行时依赖（align 子命令按 PATH 查找），必须同环境安装。
name: ultra-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - ultra_bioinformatics=0.1
  - minimap2
  - namfinder
  - samtools
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://bioconda.github.io/recipes/ultra_bioinformatics/README.html（uLTRA 的 bioconda 包名为 `ultra_bioinformatics`，二进制 `uLTRA`）
- **Docker**：`docker pull quay.io/biocontainers/ultra_bioinformatics:0.1--pyh7cba7a3_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/ultra_bioinformatics%3A0.1--pyh7cba7a3_0（与 quay 同 build tag）
- 安装方式（本地）：`mamba create -n ultra -c conda-forge -c bioconda ultra_bioinformatics=0.1 minimap2 namfinder samtools`
