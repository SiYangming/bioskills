# longreadsum 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09-07 逐渠道核实）。

***

## native 实现

# longreadsum / native — 长读测序 QC 驱动（v1.6.0）

LongReadSum（WGLab）的长读 QC 本地驱动实现（`source_type: custom`、`type: native`），命令逻辑对齐
官方 v1.6.0 CLI：`longreadsum <FILETYPE> -i <input> -o <outdir>`。

## 能力

| 子命令    | 说明                                                        | 关键参数                                                                 |
| ------ | --------------------------------------------------------- | -------------------------------------------------------------------- |
| `bam`  | BAM/CRAM 比对 QC（WGS）                                        | `--mod`（碱基修饰 MM/ML）、`--genebed`（RNA-seq TIN 分数）                      |
| `rrms` | RRMS BAM 按 CSV 拆分 accepted/rejected reads                | `-c/--csv`（read_id + decision 列）                                      |
| `pod5` | ONT POD5 信号 QC                                           | `-b/--basecalls`（带 move 表的 BAM）、`-r/--read-ids`、`-R/--read-count`     |
| `f5s`  | ONT FAST5 信号统计 QC                                        | `-r/--read-ids`、`-R/--read-count`                                     |
| `f5`   | ONT FAST5 序列 QC                                           | —                                                                    |
| `seqtxt` | ONT basecall summary（sequencing_summary.txt）QC           | —                                                                    |
| `fq`   | FASTQ QC                                                   | `-u/--udqual`（质量偏移，默认 33）                                            |
| `fa`   | FASTA QC                                                   | —                                                                    |

输入三选一：`-i` 单文件 / `-I` 逗号多文件 / `-P` 通配符模式；公共输出参数 `-o/--output`（默认官方 `output_LongReadSum`）、
`-Q/--prefix`（默认 `QC_`）、`-s/--sample`。输出 HTML 报告 + JSON summary（v1.6.0 起 JSON 输出，MultiQC
`--module longreadsum` 兼容）。

## 快速开始

### 1. 安装环境

```bash
# Conda（wglab 频道含 1.6.0；bioconda 官方仅 1.3.1 —— 见「版本与来源」）
mamba create -n longreadsum -c wglab -c conda-forge -c jannessp -c bioconda longreadsum=1.6.0
conda activate longreadsum
# 或源码编译（native/install.sh --method source），或 Docker/Apptainer 自建镜像（见「环境安装」）
```

### 2. CLI 调用

```bash
# BAM QC（WGS）
python main.py bam -i aln.sorted.bam -o qc_out --threads 8
# RNA-seq BAM：TIN 分数（转录本完整性）
python main.py bam -i rna.bam --genebed genes.bed12 -o qc_tin
# 碱基修饰分析
python main.py bam -i mod.bam --mod --modprob 0.8 --ref ref.fa -o qc_mod
# FASTQ / FASTA / 多文件通配
python main.py fq -i reads.fastq -o qc_fq
python main.py fa -P "reads/*.fasta" -o qc_fa
# RRMS / POD5 / FAST5 信号 / sequencing_summary
python main.py rrms -i rrms.bam -c decisions.csv -o qc_rrms
python main.py pod5 -i reads.pod5 --basecalls basecalls.bam -o qc_pod5
python main.py f5s -i reads.fast5 -R 5 -o qc_f5s
python main.py seqtxt -i sequencing_summary.txt -o qc_summary
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py bam -i x.bam -o out --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
# 先构建自建镜像（context=modules/ 层，需携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/longreadsum:1.6.0 -f modules/longreadsum/native/Dockerfile modules/
# 运行（ENTRYPOINT 即 longreadsum 本体；必须 -u 避免产物归 root）
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data bioskills/longreadsum:1.6.0 \
    bam -i /data/aln.bam -o /data/qc
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    --entrypoint /opt/lrs-venv/bin/python bioskills/longreadsum:1.6.0 /opt/skill/main.py fq -i /data/reads.fastq -o /data/qc
```

Apptainer：

```bash
cd modules && apptainer build ../longreadsum.sif longreadsum/native/Apptainer.def && cd ..
apptainer run -B "$PWD":/data -H /data longreadsum.sif fa -i /data/reads.fa -o /data/qc
```

### 5. 测试

```bash
bash test/run_test.sh
```

`--schema` / `--list-commands` / argv 构造验证不依赖 longreadsum 二进制（未安装自动降级）；
已安装时 `fa` 子命令真跑合成 FASTA 并断言 HTML 产物。

## 实战示例：长读数据批量 QC（bash 循环 → MultiQC 聚合）

以下为 ONT / PacBio 长读测序的典型批量 QC 用法；等价能力由 `native/main.py` 的
`fa` / `fq` / `bam` / `seqtxt` 等子命令提供（见上「快速开始」）。

### 1. 多样本 FASTQ 批量 QC

```bash
mkdir -p qc_results
for f in fastq_pass/*.fastq; do
    s=$(basename "$f" .fastq)
    longreadsum fq -i "$f" -o "qc_results/${s}_fq" -Q "${s}_" -s "$s" -t 8
done
```

### 2. BAM 批量 QC + 汇总

```bash
for b in bam/*.bam; do
    s=$(basename "$b" .bam)
    longreadsum bam -i "$b" -o "qc_results/${s}_bam" -Q "${s}_" -s "$s" -t 8
done

# MultiQC 聚合（v1.6.0 JSON summary 已兼容，注意报告目录层级）
multiqc qc_results --module longreadsum --outdir qc_results/multiqc
```

### 3. 参数说明（公共）

| 参数 | 说明 |
| --- | --- |
| `-i/--input` | 单输入文件（FASTA/FASTQ/BAM/FAST5/POD5/summary.txt） |
| `-I/--inputs` | 逗号分隔多输入文件 |
| `-P/--pattern` | 通配符匹配多输入（引号包裹） |
| `-o/--outputfolder` | 输出目录（默认 `output_LongReadSum`） |
| `-Q/--outprefix` | 输出前缀（默认 `QC_`） |
| `-s/--sample` | 样本名（默认 `Sample`） |
| `-t/--threads` | 线程数（默认 1；驱动默认注入 4） |

***

## 环境安装（自建兜底：1.6.0 无官方镜像，apt 最小化源码编译 / conda wglab 频道）

> ⚠️ **版本现状（2026-09-07 核实）**：bioconda → quay.io/biocontainers → depot.galaxyproject.org 官方渠道
> **仅维护到 longreadsum 1.3.1**；1.6.0（2025-09-11 发布，GitHub tag v1.6.0，无 release 二进制资产）只存在于
> GitHub tag 源码、wglab conda 频道与 bioinfortools 社区镜像。因此 1.6.0 走**自建兜底**（Dockerfile/Apptainer.def：
> debian:bookworm-slim + apt 构建依赖 + SWIG 源码编译，禁 miniconda）；官方 1.3.1 渠道见文末「版本与来源」供降级选用。

### 1. Conda（包管理器安装）

```bash
# wglab（作者）频道含 1.6.0；官方 README 推荐 python=3.9 + wglab 在前
mamba create -n longreadsum -c wglab -c conda-forge -c jannessp -c bioconda longreadsum=1.6.0
conda activate longreadsum
longreadsum --help   # 断言（LongReadSum 无 --version 子命令）
```

Homebrew：homebrew-core 与 brewsci/bio 两源均无 longreadsum 公式（2026-09-07 API 核实 404），故不提供 brew 安装方式。

> 一键安装可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 wglab 频道环境 `longreadsum`；
> 无 conda 时自动转源码编译到 `~/software/longreadsum-<ver>`；用法 `bash native/install.sh --help`）。

### 2. Docker（自建镜像 / 社区镜像）

自建（1.6.0，仓库 native/Dockerfile）：

```bash
docker build -t bioskills/longreadsum:1.6.0 -f modules/longreadsum/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/longreadsum:1.6.0 fa -i /data/reads.fa -o /data/qc
```

社区镜像（1.6.0，bioinfortools 频道；由 wglab conda 环境构建）：

```bash
docker pull quay.io/bioinfortools/longreadsum:1.6.0
# 该镜像为 conda 环境包装：需显式传 CONDA_PREFIX 并用环境内全路径调用（不设置会报命令不存在）
docker run --rm -e CONDA_PREFIX=/opt/conda/envs/longreadsum \
    -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/bioinfortools/longreadsum:1.6.0 \
    /opt/conda/envs/longreadsum/bin/longreadsum --help
```

官方 Docker Hub（旧 miniconda 配方，pin 1.5.0，仅作参考）：`docker pull genomicslab/longreadsum`。

### 3. Apptainer / Singularity

1.6.0 无 depot 预构建 sif（官方仅 1.3.1 档）→ 本地自建：

```bash
cd modules && apptainer build ../longreadsum.sif longreadsum/native/Apptainer.def && cd ..
apptainer run -B "$PWD":/data -H /data longreadsum.sif fa -i /data/reads.fa -o /data/qc
```

降级官方 1.3.1（depot 直拉 sif，tag 与 quay.io/biocontainers 互通）：

```bash
apptainer pull longreadsum.sif docker://depot.galaxyproject.org/singularity/longreadsum:1.3.1--py312h4a3f6ec_3
```

### 4. 源码安装（官方无预编译资产 → tag 源码归档自编译）

官方 release 无二进制资产（assets 为空），GitHub 提供 tag 源码归档：
<https://github.com/WGLab/LongReadSum/archive/refs/tags/v1.6.0.tar.gz>。

一键走 `native/install.sh --method source`（用户前缀 `~/software/longreadsum-1.6.0`，免 root）或手动：

```bash
cd ~/software
curl -fsSL -o LongReadSum-1.6.0.tar.gz \
    https://github.com/WGLab/LongReadSum/archive/refs/tags/v1.6.0.tar.gz
tar -xzf LongReadSum-1.6.0.tar.gz
# 依赖：g++/make/swig/python3(>=3.9, venv) + htslib/HDF5 开发库
# Debian/Ubuntu：sudo apt-get install -y --no-install-recommends build-essential g++ make swig \
#   git python3 python3-venv libhts-dev libhdf5-dev libhdf5-cpp-dev zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev
# macOS：brew install htslib hdf5 swig
python3 -m venv venv && ./venv/bin/pip install numpy plotly pyarrow pod5
cd LongReadSum-1.6.0
make swig_build    # SWIG 生成 Python 绑定（lib/lrst.py）
CXXFLAGS="-I/usr/include/hdf5/serial" ../venv/bin/python setup.py build_ext --build-lib lib
mkdir -p ~/software/longreadsum-1.6.0/{lib,src}
cp lib/*.py lib/_lrst*.so ~/software/longreadsum-1.6.0/lib/
cp src/*.py ~/software/longreadsum-1.6.0/src/
```

> 💡 运行期需把 `lib/`（SWIG 模块）与 `src/`（cli 与报告 Python 源码）同时放入 `PYTHONPATH` 后
> 调 `cli.main()`；`native/install.sh` 已封装为 `~/software/longreadsum-1.6.0/bin/longreadsum` wrapper。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；longreadsum 已装时 fa 真跑
```

## 版本与来源（2026-09-07 逐渠道核实，禁止再默认旧版 miniconda 配方）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| GitHub release | ✅ v1.6.0（tag v1.6.0，commit 4221fece，2025-09-11） | **无二进制资产**（assets 空）→ 源码 tag 归档 |
| bioconda | ⚠️ 官方仅到 **1.3.1** | linux-64/osx-64/linux-aarch64/osx-arm64 全平台；无 1.6.0 |
| wglab conda 频道 | ✅ **1.6.0**（作者频道，含 1.3.0–1.6.0） | `-c wglab`，官方 README 推荐源 |
| quay.io/biocontainers | ⚠️ 官方仅到 **1.3.1**（py38–py312 多 build） | 如 `1.3.1--py312h4a3f6ec_3` |
| depot.galaxyproject.org | ⚠️ 官方仅 1.3.1 档 sif | 与 quay biocontainers tag 互通 |
| quay.io/bioinfortools | ✅ **1.6.0**（社区；另有 latest） | 1.6.0 可用容器 |
| Docker Hub genomicslab/longreadsum | ✅ 官方 Docker Hub | 旧 miniconda 配方、pin 1.5.0（仅参考） |
| nf-core modules | ❌ 404（modules/nf-core/longreadsum） | 无官方 Nextflow module |
| snakemake-wrappers | ❌ 404（bio/longreadsum） | 无官方 Snakemake wrapper |
| Homebrew（core / brewsci/bio） | ❌ 两源均 404 | 无公式 |
| PyPI | ❌ longreadsum 404；`pod5` ✅ 0.3.47 | Python 运行依赖 pod5 走 PyPI/conda jannessp |

* 官方渠道（bioconda → quay biocontainers → depot）**存在但停驻 1.3.1**；1.6.0 判定为「无官方渠道」→ 自建配方（版本差异在 `meta.yaml software_versions` 中声明）。
* 源码工程形态：C++/SWIG（`src/*.cpp` + `lrst.i`，链接 htslib + HDF5）；构建 `make swig_build` → `python setup.py build_ext`（仿官方 conda/build.sh，见 `conda/` 上游目录）。
* 运行期 Python 依赖（官方 conda run deps）：numpy、plotly、pyarrow、pod5（jannessp 频道 / PyPI 0.3.47）、vbz 插件（apt `libvbz-hdf-plugin` 等价 `ont_vbz_hdf_plugin`）。

## 历史留存

原 `modules/longreadsum/Dockerfile`（旧式 `continuumio/miniconda3:main` 多架构构建：
conda config 加 wglab/conda-forge/bioconda/jannessp 频道建 env 装 longreadsum，失败则源码编译）已删除——
旧版默认 miniconda 违反现行「apt 最小化优先、禁默认 miniconda」规范；其 conda 频道信息已并入本文档与
`native/`（install.sh / environment.yml / Dockerfile 重写为 apt 最小化 + SWIG 源码编译路线），历史命令语义由
`native/main.py` 子命令承接。

## 性能优化约定

* 线程：驱动默认注入 `-t 4`（`optimization.default_cpus`）；用户显式 `--threads` 优先（透传 `-t`）。

* `--tmpdir` 覆盖 `$TMPDIR`；LongReadSum 输出目录由 `-o` 指定（默认官方 `output_LongReadSum`）。

* 中间文件与报告均落在 `-o` 目录内，无额外临时落盘；MultiQC 聚合建议直接指向输出根目录。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# longreadsum native Conda 环境配方（native/environment.yml）
# 离线兜底：mamba env create -f native/environment.yml；在线推荐上方 mamba create 直装命令
# 说明：1.6.0 需 wglab（作者）频道；官方 bioconda 仅 1.3.1（降级可 -c conda-forge -c bioconda longreadsum=1.3.1）
name: longreadsum-native
channels:
  - wglab
  - conda-forge
  - jannessp
  - bioconda
dependencies:
  - python=3.9
  - longreadsum=1.6.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **GitHub**：<https://github.com/WGLab/LongReadSum>（v1.6.0：<https://github.com/WGLab/LongReadSum/releases/tag/v1.6.0>）
* **wglab Conda**：<https://anaconda.org/wglab/longreadsum>（1.6.0）
* **Bioconda 页面（官方，仅 1.3.1）**：<https://anaconda.org/bioconda/longreadsum>
* **官方容器（1.3.1）**：`docker pull quay.io/biocontainers/longreadsum:1.3.1--py312h4a3f6ec_3`；sif 直拉 <https://depot.galaxyproject.org/singularity/longreadsum%3A1.3.1--py312h4a3f6ec_3>
* **社区容器（1.6.0）**：`docker pull quay.io/bioinfortools/longreadsum:1.6.0`
* **官方 Docker Hub**：`docker pull genomicslab/longreadsum`（旧 miniconda 配方，pin 1.5.0，仅参考）
* **自建配方**：`modules/longreadsum/native/Dockerfile` + `Apptainer.def`（apt 最小化 + SWIG 源码编译 v1.6.0；Python 依赖 venv+pip）
* **引用**：Perdomo, J. E. et al. LongReadSum. Comput Struct Biotechnol J 27, 556-563 (2025).
