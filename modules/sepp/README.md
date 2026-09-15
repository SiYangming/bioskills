# sepp 软件模块

> 汇总说明：本 README 记录 sepp native 实现的用法、环境安装（官方镜像优先）与容器/Conda 链接。
> 官方 nf-core / snakemake-wrappers 均无 sepp，信息仅登记于 `meta.yaml software_versions` 与本文档。

***

## native 实现

# sepp / native — 自包含系统发育放置驱动

SEPP（SATé-enabled Phylogenetic Placement）的本地自包含实现（`source_type: custom`、`type: native`）；
同仓库附带 UPP 比对脚本，本驱动一并承载。

## 功能

SEPP 是一个用于系统发育分析的工具，BUSCO 使用它进行谱系分配。

两个子命令（可执行脚本来自 SEPP 官方 `setup.py` 安装的 console scripts）：

| 子命令   | 命令                                                                                              | 作用                                   |
| ----- | ----------------------------------------------------------------------------------------------- | ------------------------------------ |
| `run` | `run_sepp.py -t <tree> -a <aln> -f <frag> [-r <RAxML_info>] [-A N] [-P N] -o <prefix> -d <outdir> -x N -p <tmp>` | SEPP 系统发育放置（BUSCO 谱系分配依赖）             |
| `upp` | `run_upp.py -s <seqs> [-t <tree>] [-a <aln>] [-A N] -o <prefix> -d <outdir> -x N -p <tmp>`         | UPP 超大规模（query 片段）比对扩展                |

> `-x` 为 SEPP 的 CPU 线程选项（等价 `--cpu`），`-p` 为临时目录选项；驱动自动注入 `-x <threads>` 与 `-p <tmpdir>`。

## 用法

```bash
# SEPP 放置：参考树 + 比对 + 片段 -> placement.json / alignment.fasta
python main.py run -t ref.tree -a ref_aln.fasta -f fragments.fasta -r ref.RAxML_info \
    -o placements -d $PWD/out --threads 8

# UPP 比对：未比对序列 -> 扩展比对
python main.py upp -s seqs.fasta -o upp_out -d $PWD/upp --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：BUSCO 谱系分配依赖的系统发育放置

SEPP 是 BUSCO 在谱系分配（lineage assignment）阶段调用的系统发育放置工具：把基因组/转录组中的保守基因
片段放置到 BUSCO 谱系参考树上，从而判定待测样本所属谱系。典型批处理用法（等价能力由 `native/main.py`
的 `run` 子命令提供，见上「用法」）：

```bash
# 1. 准备参考树 / 参考比对 / 待放置片段（均为 FASTA/Newick）
#    参考树与比对常来自 BUSCO 谱系数据集；RAxML_info 由 RAxML 对参考比对生成（可选）
# 2. 批量放置
for f in fragments/*.fasta; do
    sample=$(basename "$f" .fasta)
    python main.py run \
        -t ref.tree -a ref_aln.fasta -f "$f" -r ref.RAxML_info \
        -o "$sample" -d "$PWD/placements" --threads 8
done
# 3. 结果：placements/<sample>_placement.json（放置位置/似然）、placements/<sample>_alignment.fasta
```

### 参数说明

| 参数     | 说明                                     |
| ------ | -------------------------------------- |
| `-t`   | 参考系统发育树（Newick）                        |
| `-a`   | 参考比对（FASTA）                            |
| `-f`   | 待放置片段（FASTA；`run` 必填）                  |
| `-r`   | RAxML_info 文件（含模型参数，可选）                |
| `-A`   | 最大比对子集大小（默认 10）                        |
| `-P`   | 最大放置子集大小（默认总 taxa 数的 10%）              |
| `-o`   | 输出文件前缀（默认 output）                      |
| `-d`   | 输出目录（要求完整路径）                           |
| `-x`   | CPU 线程数（驱动自动注入）                        |
| `-p`   | 临时目录（驱动自动注入）                           |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n sepp-native -c conda-forge -c bioconda sepp=4.3.10
conda activate sepp-native
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install sepp
run_sepp.py -v           # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `sepp`，无 conda 时
> 自动下载官方 GitHub 源码归档 `4.3.10.tar.gz` 并 `python setup.py config && install` 到
> `~/software/sepp-<ver>` 写 PATH；版本默认 4.3.10，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/sepp:4.3.10--py38h9ee0642_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/sepp:4.3.10--py38h9ee0642_3 \
    run_sepp.py -t /data/ref.tree -a /data/ref_aln.fasta -f /data/fragments.fasta \
        -o placements -d /data/out --cpu 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull sepp.sif docker://depot.galaxyproject.org/singularity/sepp:4.3.10--py38h9ee0642_3
apptainer run -B $PWD:/data -H /data sepp.sif \
    run_sepp.py -t /data/ref.tree -a /data/ref_aln.fasta -f /data/fragments.fasta \
        -o placements -d /data/out --cpu 8
```

### 4. 官方源码编译（并列保留；SEPP 官方无预编译二进制）

官方仅发布源码（GitHub tag archive），安装方式为 `python setup.py config && python setup.py install`，
依赖 `dendropy`（本仓库 `native/install.sh --method source` 即自动化此路线）：

```bash
# 依赖
python3 -m pip install --user dendropy
# 下载并安装（用户级前缀，无需 root）
wget https://github.com/smirarab/sepp/archive/refs/tags/4.3.10.tar.gz -P ~/software/
tar zxf ~/software/4.3.10.tar.gz -C ~/software/
cd ~/software/sepp-4.3.10
python3 setup.py config
python3 setup.py install --prefix=$HOME/software/sepp-4.3.10
export PATH=$HOME/software/sepp-4.3.10/bin:$PATH
run_sepp.py -v   # 断言
```

> 说明（已核实）：SEPP 官方发布页只提供源码归档（GitHub tags / `python setup.py`），**无官方预编译二进制资产**；
> 官方容器/conda 与源码编译两条路线均保留。

## 测试

```bash
bash test/run_test.sh   # run/upp 为 argv 构造验证；已安装 sepp 时额外做 run_sepp.py -v 冒烟
```

## 版本

* sepp 4.3.10（bioconda::sepp=4.3.10；bioconda 另有 4.5.6 等更新版本，本模块默认 pin 4.3.10）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/sepp / depot.galaxyproject.org；本地不再自建容器）
* 官方无 nf-core 子模块、无 snakemake-wrappers（2026-09 核实 404）

## 官方实现登记（不建目录）

* **nf-core**：`modules/nf-core/sepp` 不存在（2026-09 核实 `meta.yml` 404），Nextflow 场景请直接使用本模块 `native/` 或官方容器。
* **snakemake-wrappers**：`bio/sepp` 不存在（2026-09 核实 `environment.yaml` / `wrapper.py` 均 404），Snakemake 场景请在容器/PATH 内直调 `run_sepp.py`。

## 容器与 Conda 链接

* **GitHub**：https://github.com/smirarab/sepp
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/sepp/overview>
* **Docker**：`docker pull quay.io/biocontainers/sepp:4.3.10--py38h9ee0642_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/sepp%3A4.3.10--py38h9ee0642_3>
* **Homebrew**：`brew tap brewsci/bio && brew install sepp`（brewsci/bio `sepp.rb`，url 指向 4.3.10）
* 安装方式（本地）：`mamba create -n sepp -c conda-forge -c bioconda sepp=4.3.10`
