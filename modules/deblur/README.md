# deblur 软件模块

> 汇总说明：本 README 记录 Deblur（去噪 CLI）的 native 实现用法与容器/conda 环境信息；安装方式见「环境安装」节。

***

## native 实现

# deblur / native — 自包含扩增子去噪驱动（deblur CLI）

Deblur 的本地自包含实现（`source_type: custom`、`type: native`）。Deblur 以 Python CLI（命令 `deblur`）分发，本驱动封装其核心子命令；等价能力亦内置于 QIIME 2（`qiime deblur denoise-16S`）。

## 功能

| 子命令                | deblur 命令                          | 作用                                     |
| ------------------ | ---------------------------------- | -------------------------------------- |
| `workflow`         | `deblur workflow`                  | 完整流水线：demux fasta/fastq → 去噪 → BIOM 表    |
| `dereplicate`      | `deblur dereplicate`               | 序列去重并去除低丰度（--min-size）                 |
| `trim`             | `deblur trim`                      | 序列截短（--trim-length）                    |
| `build-biom-table` | `deblur build-biom-table`          | 由去嵌合 fasta 目录生成 BIOM 表                  |

## 用法

```bash
# 完整流水线（单端；默认内置 Greengenes 13_8 OTUs 88% identity 预过滤）
python main.py workflow --seqs-fp demux.fasta --output-dir out \
    --trim-length 120 --reference-fp 88_otus.fasta --threads 4

# 分段：去重 / 截短 / 建表
python main.py dereplicate demux.fasta derep.fasta --min-size 2
python main.py trim demux.fasta trimmed.fasta --trim-length 120
python main.py build-biom-table chimera_removed out_dir --min-reads 10

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`workflow` 将 `--threads` 映射到 `-O/--jobs-to-start`（并行作业数）。Deblur 去噪核心不支持多线程，`--threads-per-sample/-a` 需单独指定。

## 实战示例：单端 16S 去噪（Deblur）

Deblur 使用基于错误分布的子空间方法区分真实序列与测序错误，输出单核苷酸分辨率 ASVs；仅支持单端数据，可用内置/自定义 16S 参考数据库预过滤。以下为典型用法；等价能力由 `native/main.py` 的 `workflow` / `dereplicate` / `trim` / `build-biom-table` 子命令提供（见上「用法」）。

### 1. 完整流水线（单端去噪 → BIOM 表）

```bash
# 输入可为去多路复用的单个 fasta/fastq，或每样本一个文件的目录
python main.py workflow \
    --seqs-fp demux.fasta \
    --output-dir deblur_out \
    --trim-length 120 \
    --reference-fp 88_otus.fasta \
    --min-reads 10 --min-size 2 \
    --threads 4

# 输出：deblur_out/all.biom、reference-hit.biom、reference-non-hit.biom
```

### 2. 参考数据库说明

* **默认**：内置 Greengenes 13_8 OTUs 88% identity（`--pos-ref-fp` 缺省值），SortMeRNA e-value 阈值 10。

* **自定义**：`--reference-fp` 可指定 `85_otus.fasta` / `88_otus.fasta`（或 Greengenes）等参考 FASTA，可重复传入多个库；`--reference-db-fp` 指定已索引库目录以避免每次重复索引。

* **负向库**：`--neg-ref-fp` 默认 PhiX + 已知 Illumina 接头；可自定义。

### 3. 参数说明

| 参数                       | 说明                                     |
| ------------------------ | -------------------------------------- |
| `--trim-length`          | 序列截短长度（-1 表示跳过截短）                     |
| `--left-trim-length`     | 5' 端截短碱基数（0 表示不截短）                    |
| `--reference-fp`         | 正向参考库 FASTA（默认 Greengenes 88% OTUs，可重复） |
| `--min-reads`            | 研究范围最小读数（默认 10）                        |
| `--min-size`             | 每样本最小出现次数（默认 2）                        |
| `--mean-error`           | 平均每碱基错误率（默认 0.005）                     |
| `--threads`              | 并行作业数（映射到 `-O/--jobs-to-start`）         |
| `--threads-per-sample`   | 每样本线程数（`-a`；0=全部核）                    |

> ⚠️ 15.md 提示：QIIME 2 的 `--p-trim-length` 不能设置为 `-1`（会导致运行失败），必须指定具体截短长度。QIIME 2 等价调用：`qiime deblur denoise-16S`（见 15.md「4.2 使用 Deblur 去噪」与「### 7. Deblur」）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / pip（包管理器安装）

```bash
mamba create -n deblur-native -c conda-forge -c bioconda deblur=1.1.1
conda activate deblur-native
deblur --version   # 断言
```

```bash
# 或用 pip（用户级 venv，无需 conda）
python3 -m venv ~/software/deblur-1.1.1
~/software/deblur-1.1.1/bin/pip install deblur==1.1.1
export PATH="$HOME/software/deblur-1.1.1/bin:$PATH"
deblur --version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（有 conda 走 bioconda，否则建用户级 venv 用 pip 安装；版本默认 1.1.1，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。
>
> brew 无公式（2026-09 核实 homebrew-core 与 brewsci/bio 均无 deblur），故不提供 brew 小节。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/deblur:1.1.1--pyhdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/deblur:1.1.1--pyhdfd78af_0 \
    deblur workflow --seqs-fp /data/demux.fasta --output-dir /data/out \
    --trim-length 120 --reference-fp /data/88_otus.fasta -O 4
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull deblur.sif docker://depot.galaxyproject.org/singularity/deblur:1.1.1--pyhdfd78af_0
apptainer run -B $PWD:/data -H /data deblur.sif \
    deblur workflow --seqs-fp /data/demux.fasta --output-dir /data/out --trim-length 120 -O 4
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证为主；deblur 已安装时追加 --version 冒烟
```

## 容器与 Conda 链接

* **Github**：https://github.com/biocore/deblur

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/deblur/overview>

* **Docker**：`docker pull quay.io/biocontainers/deblur:1.1.1--pyhdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/deblur%3A1.1.1--pyhdfd78af_0>

* 安装方式（本地）：`mamba create -n deblur -c conda-forge -c bioconda deblur=1.1.1` 或 `pip install deblur==1.1.1`

## 版本

* deblur 1.1.1（bioconda::deblur=1.1.1）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/deblur / depot.galaxyproject.org；本地不再自建容器）

* nf-core（modules/nf-core/deblur 404）与 snakemake-wrappers（bio/deblur 404）均无官方模块（2026-09 核实），Nextflow/Snakemake 场景以本模块 native deblur CLI 驱动为兜底
