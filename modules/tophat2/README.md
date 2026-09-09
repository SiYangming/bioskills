# tophat2 软件模块（TopHat2 — RNA-seq 剪接感知比对器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **TopHat2（2.1.1，CCB 约翰霍普金斯大学，Tuxedo 工具家族）** 是 RNA-seq 剪接感知
> 比对器：先用 **Bowtie/Bowtie2** 把 reads 比对到参考基因组，再分析比对结果识别
> 外显子间剪接位点（Kim D et al. *Genome Biol* 2013;14:R36）。单命令
> `tophat`：`tophat [options] <genome_index_base> <reads...>`。
>
> 官方 **CCB 页面（2026-09-09 核实 200）在 2.1.1 release note 中明示**：
> *"TopHat has entered a low maintenance, low support stage as it is now largely
> superseded by **HISAT2** which provides the same core functionality (i.e.
> spliced alignment of RNA-Seq reads), in a more accurate and much more
> efficient way."* 上游最终发布 **2.1.1（2016-02-23）**。
>
> **新项目请勿使用**——改用 **HISAT2**（官方指明继任者）或 **STAR**（本仓库另见
> `star` 模块）。本模块只做「录入」：方法/命令/链接准确登记、不产出自建容器配方
> （Dockerfile/Apptainer.def），仅供复现 2013–2016 时代的 TopHat2 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方 manual 构造 tophat 命令行并
打印，**不实际执行**（软件 deprecated、无新用场景）。单子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `tophat` | `tophat -o <out_dir> -p <N> [-G genes.gtf] [--transcriptome-index <idx>] [-N/-r/--max-multihits ...] <genome_index_base> <reads...>` | Bowtie2 索引 + reads → accepted_hits.bam / junctions.bed / align_summary.txt |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 tophat，见「环境安装」）
python main.py tophat genome_index reads_1.fq reads_2.fq \
    -o tophat_out -p 8 -G genes.gtf
python main.py tophat genome_index --transcriptome-index tx_idx \
    reads_1.fq reads_2.fq -p 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`auto` 默认给 `-p 4`，正整数透传 `-p`）与 `--tmpdir`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

## 实战示例：TopHat2 RNA-seq 剪接比对（历史流程；等价能力 = `native/main.py tophat`）

以下为 2013–2016 时代经典 TopHat2 双端 RNA-seq 教程步骤，仅历史复现。原教程惯用
`/opt/biosoft/tophat-2.1.1.Linux_x86_64` 等绝对安装前缀，此处改写为**用户前缀**
`~/software/tophat-2.1.1`（免 root；原始路径见「历史留存」）：

```bash
# 0) 准备：解压官方二进制到用户前缀，并确保 Bowtie2 已建好基因组索引
mkdir -p ~/software/tophat-2.1.1 && cd ~/software/tophat-2.1.1
export PATH="$HOME/software/tophat-2.1.1:$PATH"
# Bowtie2 建索引（参考 genome.fa → genome_index.1.bt2 等；bowtie2-build genome.fa genome_index）

# 1) 无注释 de novo 剪接位点发现（SE/PE reads；-p 线程）
tophat -o tophat_out -p 8 genome_index reads_1.fq reads_2.fq
# 2) 带注释（-G GTF 自动建 transcriptome index，比对更准；--transcriptome-index 可复用）
tophat -o tophat_out_gtf -p 8 -G genes.gtf genome_index reads_1.fq reads_2.fq
# 3) 双端 inner distance 指定（-r，文库 insert 已知时）
tophat -o tophat_out_r -p 8 -r 150 genome_index reads_1.fq reads_2.fq
```

> 主产物在 `-o` 输出目录：`accepted_hits.bam`（默认过滤多比对 read，保留
> `--max-multihits` 内）、`junctions.bed`（剪接位点）、`align_summary.txt`（计数
> 统计）、`insertions.bed` / `deletions.bed`（indel）。下游常接 cufflinks
> （本模块不覆盖）。

### 参数说明（录入；2026-09 对照官方 manual）

| 参数 | 说明 |
| ---- | ---- |
| `<genome_index_base>` | Bowtie2 基因组索引 basename（tophat2 默认 bowtie2；`<base>.1.bt2`） |
| `<reads...>` | reads 文件（FASTA/FASTQ；SE 1 个 / PE 2 个，每文件可为逗号列表） |
| `-o <dir>` | 输出目录（默认 tophat_out） |
| `-p <N>` | 线程数（默认 1，本驱动 auto 给 4） |
| `-G <gtf>` | 注释 GTF/GFF（自动建 transcriptome index） |
| `--transcriptome-index <idx>` | 复用预建 transcriptome 索引（免每次 -G 重建） |
| `-N <n>` | 每条 read 允许错配数（默认 2） |
| `--read-edit-dist <n>` | 最终比对 edit distance（默认 2） |
| `--max-multihits <n>` | 多比对 read 最大报告数（默认 20） |
| `-r <n>` | 双端 inner distance 期望均值（PE） |
| `-i <n>` | 最小内含子长度（默认 70；`--min-intron-length`） |
| `-I <n>` | 最大内含子长度（默认 500000；`--max-intron-length`） |
| `--coverage-search` | 启用覆盖度搜索（提高剪接位点检测灵敏度） |
| `--microexon-search` | 启用微小外显子搜索（检测短外显子；需先了解覆盖度） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-09 在线核实，如实记录）：上游已停更（2.1.1，2016-02-23；
> 官方 CCB 建议 HISAT2/STAR）；**CCB 官方二进制直链仍 200**（历史遗留）；
> bioconda 有 **tophat=2.1.2**（python>=3 兼容重建，依赖 bowtie2 等）→
> quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建镜像；软件
> deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**（容器仅登记官方自动
> 构建镜像）。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda tophat=2.1.2（python3 兼容重建；依赖自动带 bowtie2）
mamba create -n tophat2-native -c conda-forge -c bioconda tophat=2.1.2 bowtie2
conda activate tophat2-native
tophat --version 2>&1 | head -1 || tophat --help 2>&1 | head -2   # 断言命令可达
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/tophat.json）与 brewsci/bio
> （Formula/tophat.rb）均 404（2026-09-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；bioconda 2.1.2 自动构建镜像可作复现：

```bash
docker pull quay.io/biocontainers/tophat:2.1.2--h3e6c209_0
# 运行工具本体（产物归当前用户，避免 root 持有；tag 以 quay/depot 在线目录为准）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/tophat:2.1.2--h3e6c209_0 \
    tophat -o /data/tophat_out -p 4 /data/genome_index /data/reads_1.fq /data/reads_2.fq
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（与 quay tag 互通；tag 以在线目录为准）：

```bash
apptainer pull tophat.sif docker://depot.galaxyproject.org/singularity/tophat:2.1.2--h3e6c209_0
apptainer run -B $PWD:/data -H /data tophat.sif \
    tophat -o /data/tophat_out -p 4 /data/genome_index /data/reads_1.fq /data/reads_2.fq
```

### 4. 二进制包安装（官方 release / 源码编译）

CCB 官方下载页（2026-09-09 HEAD 核实均 200）提供 2.1.1 源码与 Linux/Mac 预编译：

```bash
mkdir -p ~/software && cd ~/software
curl -fL -O https://ccb.jhu.edu/software/tophat/downloads/tophat-2.1.1.Linux_x86_64.tar.gz
tar zxf tophat-2.1.1.Linux_x86_64.tar.gz        # 解压出 tophat-2.1.1.Linux_x86_64/
export PATH="$HOME/software/tophat-2.1.1.Linux_x86_64:$PATH"
# 源码编译路线：https://ccb.jhu.edu/software/tophat/downloads/tophat-2.1.1.tar.gz
#   （需 Boost + SeqAn（随包）；详见 CCB tutorial 的 boost 说明）
```

> 需 Bowtie2 及索引（bioconda `bowtie2` 或官网）；2016 时代二进制对现代 glibc 的
> 兼容性未逐一核实（推荐 bioconda tophat=2.1.2 路线）。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **HISAT2** | TopHat 官方指明继任者（同核心功能、更准更快；graph 基因组索引） | <https://daehwankimlab.github.io/hisat2/>（bioconda `hisat2`） |
| **STAR** | RNA-seq 剪接比对主流（超快；本仓库另见 `star` 模块） | <https://github.com/alexdobin/STAR>（bioconda `star`） |
| **RSEM** | 定量流程（本仓库另见 `rsem` 模块；比对内核可为 STAR/Bowtie2） | <https://github.com/bli25wisc/RSEM> |

## 版本

* **2.1.1**（官方 CCB 最终发布，2016-02-23；源码 `tophat-2.1.1.tar.gz` +
  Linux/Mac x86_64 预编译直链 2026-09-09 HEAD 均 **200**）
* GitHub **infphilo/tophat**：仓库存续（源码已迁移 GitHub，2015-03-31），tags 含
  v2.1.0/v2.1.1/v2.1.2（v2.1.2 为社区提交，无官方发布页）
* bioconda 版本号 **2.1.2**（python>=3 兼容重建 build -0，依赖 bowtie2/boost-cpp/
  ncurses/setuptools；另有 2.1.1-py27_0.._3 老构建；2026-09-09 api.anaconda.org 核实）
* License：bioconda 包元数据 **Boost Software License**；官方 CCB 页面未明示
  （以发行源码内 LICENSE 为准，2026-09 未逐一核对原文）
* 引用：Kim D, Pertea G, Trapnell C, Pimentel H, Kelley R, Salzberg SL. TopHat2:
  accurate alignment of transcriptomes in the presence of insertions, deletions
  and gene fusions. *Genome Biol* 2013;14(4):R36. doi:10.1186/gb-2013-14-4-r36
* nf-core / snakemake-wrappers：无官方子模块（2026-09-09 核实
  `modules/nf-core/tophat2`、`bio/tophat` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装路径为 **`/opt/biosoft/tophat-2.1.1.Linux_x86_64`**（root 全局
  前缀）与 `/home/train` 系；本 README 一律改写为**用户前缀**
  `~/software/tophat-2.1.1`（免 root）。原始发布包名
  `tophat-2.1.1.Linux_x86_64.tar.gz` / `tophat-2.1.1.tar.gz`（CCB downloads）。
* **版本提示**：官方 CCB 最终发布为 2.1.1；bioconda 2.1.2 为社区/配方维护的
  python3 兼容重建（对应 infphilo fork 的 v2.1.2 tag 后续提交），二者命令集一致。
* TopHat2 默认以 **Bowtie2** 为比对内核（也可 `--bowtie1`），需先建 BT2 索引
  （`bowtie2-build ref.fa idx`）；本模块假定用户已建好索引（见实战示例步骤 0）。
* 下游经典配套：TopHat2 输出接 **cufflinks/cuffdiff**（Tuxedo 流程）；现代流程
  建议整体迁移 HISAT2/STAR + StringTie（本仓库另见 `stringtie` 模块）。

## 容器与 Conda 链接

* **官方 CCB 页面**：<https://ccb.jhu.edu/software/tophat/index.shtml>
* **官方下载（2.1.1，200）**：<https://ccb.jhu.edu/software/tophat/downloads/>
* **GitHub（源码）**：<https://github.com/infphilo/tophat>
* **conda**：bioconda `tophat=2.1.2` → <https://anaconda.org/bioconda/tophat>
* **Docker / Singularity**：`quay.io/biocontainers/tophat:2.1.2--h3e6c209_0` /
  depot.galaxyproject.org 同名 sif（tag 以在线目录为准）
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **继任者（官方声明入口）**：<https://daehwankimlab.github.io/hisat2/>
