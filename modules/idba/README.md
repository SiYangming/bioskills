# idba 软件模块

> 汇总说明：本 README 说明 idba（IDBA 1.1.3：idba_ud + fq2fa）的唯一本地实现（native）；
> 安装方式见下方各节，容器与 conda 信息记录于此。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/idba` **不存在**（2026-09 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/idba> 返回 404）。
* **snakemake-wrappers**：`bio/idba` **不存在**（2026-09 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/idba> 返回 404）
  → Snakemake 场景用 native/main.py 兜底。
* **Homebrew**：homebrew-core 无 idba（`formulae.brew.sh/api/formula/idba.json` 404）；brewsci/bio
  有公式（`Formula/idba.rb`，2026-09 核实 200，GPL-2.0-or-later）→ 见「环境安装 §1」。

> 官方渠道已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉官方镜像
> 运行工具；`native/` 不维护 Dockerfile/Apptainer.def。

***

## native 实现

# idba / native — 迭代 de Bruijn 图短读组装驱动（1.1.3）

IDBA 1.1.3 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对照官方文档。

## 功能

| 子命令       | 命令                                                                                            | 作用                                |
| --------- | --------------------------------------------------------------------------------------------- | --------------------------------- |
| `idba_ud` | `idba_ud -r <reads.fa> [-o <outdir>] --mink 20 --maxk 100 --step 20 [--num_threads N] [--no_local] ...` | 迭代 de Bruijn 图短读组装（低深度/宏基因组尤佳） |
| `fq2fa`   | `fq2fa [--merge] [--filter] [--paired] <in1.fq> [in2.fq] <out.fa>`                            | FASTQ → FASTA（过滤 / 合并双端 / paired）  |

## 用法

```bash
# CLI 直跑
python main.py fq2fa --filter --merge illumina.1.fastq illumina.2.fastq illumina.fasta
python main.py idba_ud -r illumina.fasta --mink 20 --maxk 100 --step 20 -o out --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 在 idba_ud 注入 `--num_threads`）。

## 实战示例：Illumina 双端组装

IDBA-UD 面向 paired-end / single-end 短读，利用配对信息组装低深度区域并按 contig 深度渐进降错，
适合单细胞与宏基因组数据。以下为文档给出的典型用法；等价能力由 `native/main.py` 的 `fq2fa` /
`idba_ud` 子命令提供（见上「用法」）。

```bash
mkdir -p IDBA && cd IDBA

# 1. fastq → fasta（--filter 过滤低质量 reads；--merge 合并双端，pair 两行相邻）
fq2fa --filter --merge illumina.1.fastq illumina.2.fastq illumina.fasta

# 2. IDBA-UD 组装（--mink 20 / --maxk 100 / --step 20；输出到 out/）
idba_ud -r illumina.fasta --mink 20 --maxk 100 --step 20

# 3. 格式化结果（genome_seq_clear.pl 为随包历史脚本，按需使用）
# genome_seq_clear.pl --seq_prefix idba out/contig.fa > IDBA.fasta
```

### 参数说明

| 参数            | 说明              |
| ------------- | --------------- |
| `--mink 20`   | 最小 k-mer 长度     |
| `--maxk 100`  | 最大 k-mer 长度     |
| `--step 20`   | 每次迭代 k-mer 增量   |
| `-r`          | 输入序列文件（FASTA）   |
| `--num_threads` | 线程数（main.py 自动注入） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行
工具；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n idba -c conda-forge -c bioconda idba=1.1.3
conda activate idba
idba_ud --help    # 断言（无参运行打印 manual）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install idba
idba_ud --help           # 断言
```

> ⚠️ **conda 版默认 kMaxShortSequence=128**（`src/sequence/short_sequence.h`）；处理更长 reads
> （>128 bp）需源码编译并改该常量（文档示例改为 160），见 §4。conda / brew 版无法改。
>
> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 `idba` 环境，无 conda 时走官方源码
> 编译，可加 `--patch-max-short-seq 160` 打补丁）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/idba:1.1.3--h9948957_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/idba:1.1.3--h9948957_5 \
    idba_ud -r /data/illumina.fasta --mink 20 --maxk 100 --step 20 -o /data/out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull idba.sif docker://depot.galaxyproject.org/singularity/idba:1.1.3--h9948957_5
apptainer run -B $PWD:/data -H /data idba.sif idba_ud -r /data/illumina.fasta \
    --mink 20 --maxk 100 --step 20 -o /data/out
```

### 4. 官方源码编译（处理长 reads 需打补丁）

```bash
curl -fSL -o idba-1.1.3.tar.gz \
    https://github.com/loneknightpy/idba/releases/download/1.1.3/idba-1.1.3.tar.gz
tar zxf idba-1.1.3.tar.gz && cd idba-1.1.3
./configure --prefix=$HOME/software/idba-1.1.3
# 修复最大序列长度限制（128 → 160；文档示例）
perl -p -i -e 's/kMaxShortSequence = 128/kMaxShortSequence = 160/' src/sequence/short_sequence.h
make -j 4 && make install
export PATH="$HOME/software/idba-1.1.3/bin:$PATH"
idba_ud --help
```

## 测试

```bash
bash test/run_test.sh   # 合成数据 + argv 构造验证；idba 未安装时跳过真实冒烟
```

## 版本

* idba 1.1.3（bioconda::idba=1.1.3；GitHub release 1.1.3）
* 构建路线：官方镜像 / conda 提供（quay.io/biocontainers/idba / depot.galaxyproject.org）；
  brew brewsci/bio 亦有公式
* ⚠️ conda / brew 版 kMaxShortSequence=128，长 reads（>128 bp）需源码编译改常量（§4）

***

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/idba/overview>
* **官方仓库**：<https://github.com/loneknightpy/idba>（release 1.1.3）
* **Docker**：`docker pull quay.io/biocontainers/idba:1.1.3--h9948957_5`
* **Singularity**：<https://depot.galaxyproject.org/singularity/idba%3A1.1.3--h9948957_5>
* 安装方式（本地）：`mamba create -n idba -c conda-forge -c bioconda idba=1.1.3`
  （或 `bash native/install.sh`）
