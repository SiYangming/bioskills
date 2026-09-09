# stampy 软件模块（Stampy — 牛津高灵敏短读比对器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **Stampy（1.0.32）** 是牛津 Wellcome Trust Centre for Human Genetics 开发的
> 高灵敏 Illumina 短读比对器（Lunter & Goodson, *Genome Res* 2011;21:936-9）：
> 15-mer hash 定位候选 + 快速 gapped aligner + 全概率 realigner（容忍至 ~30 bp
> indel），在样本与参考有变异/分歧时比对产出率与准确性优于同时代工具；经典用法是
> 与 **BWA** 组成 hybrid 管线（BWA 快筛 + Stampy 精比对）。CLI 三个动作：
> `-G` 建基因组索引（.stidx）→ `-H` 建 hash（.sthash）→ `-M` 比对（SAM 输出）。
>
> 上游在 **1.0.32 之后基本停更**（官方发行 stampy-1.0.32r3761.tgz，时间戳
> 2017-11-06），强依赖 **Python 2.7**。2026-09-09 在线核实：官方下载点
> www.well.ox.ac.uk/stampy 302 → www.chg.ox.ac.uk（页面 404，文件库直链被
> CloudFront 403 拦截）；GitHub najoshi/stampy（历史常用镜像）404；bioconda
> 无 stampy 包。
>
> **新项目请勿使用**——改用 **BWA-MEM / Bowtie2 / Novoalign** 等现代比对器。
> 本模块只做「录入」：方法/命令/链接准确登记、无官方当前维护镜像推荐、不产出自建
> 容器配方（Dockerfile/Apptainer.def），仅供复现 2011–2017 时代的 Stampy 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方 help 构造 stampy.py 命令行并
打印，**不实际执行**（软件 deprecated、依赖 Python2 环境）。三个子命令对应
Stampy 三条主线动作：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `genome` | `stampy.py -G <prefix> <ref.fa> [--species=S --assembly=S]` | 参考 FASTA → 基因组索引 `<prefix>.stidx` |
| `hash` | `stampy.py -g <prefix> -H <prefix> [--maxcount=N]` | → hash 索引 `<prefix>.sthash`（依赖 .stidx） |
| `map` | `stampy.py -g <prefix> -h <prefix> -M reads.fq[-o out.sam] [-f sam] [-t N] [--sensitive]` | reads → SAM 比对 |

```bash
# CLI 直跑（构造历史命令，仅供复现；先部署 Stampy 1.0.32，见「环境安装」）
python main.py genome genome --species human --assembly hg19 ref.fa
python main.py hash genome --maxcount 200
python main.py map --genome-prefix genome --hash-prefix genome \
    -M reads_1.fq,reads_2.fq -o out.sam --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`auto` 或正整数；正整数透传 map `-t`）与 `--tmpdir`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。stampy.py 实际
运行需 **Python 2.7**（见「历史留存」说明）。

***

### 参数说明（录入；2026-09 对照官方 help 文本）

| 参数 | 适用动作 | 说明 |
| ---- | ---- | ---- |
| `-G PREFIX` | genome | 建基因组索引 PREFIX.stidx（必填；读入命令行 FASTA，可多个 .fa[.gz]） |
| `-g PREFIX` | hash / map | 使用基因组索引 PREFIX.stidx |
| `-H PREFIX` | hash | 建 hash PREFIX.sthash |
| `-h PREFIX` | map | 使用 hash PREFIX.sthash |
| `-M FILE[,FILE]` | map | 输入 reads（FASTQ/FASTA/BAM；双端逗号两文件） |
| `-o FILE` | map | 输出文件（默认 stdout） |
| `-f FMT` | map | 输出格式 sam/maqtxt/maqmap/maqmapN（默认 sam） |
| `-t N` | map | 线程数（默认 1） |
| `--sensitive` | map | 更敏感（约慢 25-50%）；`--fast` 反之 |
| `--substitutionrate=F` | map | 替换率（默认 0.001） |
| `--species / --assembly` | genome | SAM @SQ 的 SP / AS tag |
| `--maxcount=N` | hash | 重复 word 最大拷贝数（默认 200） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-09 在线核实，如实记录）：**上游停更（2017-11-06 后无发布）**；
> **无 conda 包**（bioconda 无 stampy）、无官方容器镜像；官方下载点
> www.well.ox.ac.uk/stampy → www.chg.ox.ac.uk 已不可直连（files-library 被
> CloudFront 403 拦截，~gerton/software/Stampy/ 目录 404）。**软件 deprecated →
> 不维护本地 Dockerfile/Apptainer.def 配方**；历史复现走「源码手工部署」路线
> （§4），驱动运行环境见 `native/environment.yml`（python=3.11 + pyyaml）。

### 1. Conda / brew（包管理器安装）

```bash
# conda：仅驱动运行环境（不含 stampy——bioconda 渠道无该包）
mamba env create -f native/environment.yml
conda activate stampy-native
# stampy 本体无 conda 包 → 见下方 §4 手工部署（Python 2.7 时代软件）
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/stampy.json）404、
> brewsci/bio（Formula/stampy.rb）404（2026-09-09 核实），无公式 → 不登记
> brew 安装块。

### 2. Docker（官方镜像）

无官方镜像（无 bioconda 包 → quay.io/biocontainers 无自动构建）。历史复现如需
容器，可自行构建「python2.7 + stampy」镜像，或使用社区遗留镜像（未核实、不推荐
新项目依赖）。

### 3. Apptainer / Singularity

depot.galaxyproject.org 无 stampy 预构建 sif（无 bioconda 包）→ 无官方渠道可登记。

### 4. 二进制/源码安装（官方 release / 源码手工部署）

官方发行包 `stampy-1.0.32r3761.tgz`（= `stampy-latest.tgz`，517K，2017-11-06）
历史上在 `www.well.ox.ac.uk` / `www.chg.ox.ac.uk/~gerton/software/Stampy/` 分发；
2026-09-09 该两处直链**均不可达**（404/403）。可用的**源码镜像**（raw 200，
2026-09-09 核实）：`github.com/uwb-linux/stampy`（社区镜像，含 stampy.py 与
maptools 源码）：

```bash
# 1) 取镜像源码到用户前缀（免 root）
mkdir -p ~/software/stampy-1.0.32 && cd ~/software/stampy-1.0.32
curl -fL -o stampy.py \
    https://raw.githubusercontent.com/uwb-linux/stampy/master/stampy.py
# 2) Python 2.7 + 编译 maptools（Python2 时代 make；需 python2.7-dev/编译器）
#    历史 make 步骤（以镜像仓库内 Makefile 为准）：make  → 生成 build/pyx/maptools*.so
# 3) 运行断言（python2.7 不可用时历史复现受限）
python2 stampy.py -? 2>&1 | head -5   # 打印 help（stampy 无 --version）
```

> ⚠️ stampy.py 开头硬检查 Python 2.7（`sys.version`），Python3 直接报错；编译
> maptools 需 Python2 时代工具链。若历史数据非必需，**新项目请直接用 BWA-MEM /
> Bowtie2 / Novoalign**。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **BWA-MEM** | BWA 家族通用比对（短读/长读均可用），高分歧样本鲁棒 | <https://github.com/lh3/bwa>（bioconda `bwa`） |
| **Bowtie2** | 端到端/局部短读比对，支持 indel 与双端 | <https://github.com/BenLangmead/bowtie2>（bioconda `bowtie2`） |
| **Novoalign** | 高灵敏商用比对器（Stampy 时代同定位） | <https://www.novocraft.com/products/novoalign/> |
| **NextGenMap** | 高多态基因组短读比对（学术免费） | <https://github.com/cibiv/NextGenMap> |

## 版本

* **1.0.32**（官方最终版；发行名 stampy-1.0.32r3761.tgz / stampy-latest.tgz，
  2017-11-06；BEAR 等机构软件页均以 1.0.32 为最新，2026-09 在线核实）
* bioconda：**无 stampy 包**（2026-09-09 api.anaconda.org 搜索核实）
* License：**未核实**（官方发行版内含许可声明，但下载点不可直连；GitHub 镜像无
  LICENSE 文件——学术工具，以官方声明为准，不做臆断）
* 引用：Lunter G, Goodson M. Stampy: a statistical algorithm for sensitive and
  fast mapping of Illumina sequence reads. *Genome Res* 2011;21(6):936-9.
  doi:10.1101/gr.111120.110
* nf-core / snakemake-wrappers：无官方子模块（2026-09-09 核实
  `modules/nf-core/stampy`、`bio/stampy` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装路径为 **`/home/train/stampy-1.0.32`**（培训环境绝对路径）与
  `/opt/biosoft` 系前缀；本 README 一律改写为**用户前缀**
  `~/software/stampy-1.0.32`（免 root）。原始发行包名
  `stampy-1.0.32r3761.tgz`（2017-11-06，~517K）。
* **Python2 依赖**：stampy.py 第 5-6 行硬检查 `sys.version`（要求 2.7），否则
  stderr 报 "Stampy requires Python version 2.7" 退出；历史教程所有命令均以
  `python2 stampy.py` 形式运行（本 README 已统一改写）。
* **maptools 编译**：stampy 本体包含需编译的 Cython 扩展（maptools）；历史安装 =
  `make` 生成 build/pyx/maptools*.so + `python2 stampy.py`。现代系统（macOS 新版 /
  新 Linux）与 Python2 工具链兼容性未核实。
* 历史常见下游：Stampy 比对后接 SAMtools 排序去重、GATK 等 SNP/indel 检出；
  现代流程建议整体迁移至 BWA-MEM/Bowtie2 工具链。

## 容器与 Conda 链接

* **官方页面（已迁移/不可直连）**：<http://www.well.ox.ac.uk/stampy>
  （302 → www.chg.ox.ac.uk；文件库直链被 CloudFront 拦截，2026-09-09 核实）
* **历史发行索引（搜索引擎留存）**：`www.chg.ox.ac.uk/~gerton/software/Stampy/`
  （列有 stampy-1.0.32r3761.tgz 与 stampy-latest.tgz，2017-11-06；当前 404）
* **社区源码镜像**：<https://github.com/uwb-linux/stampy>（raw 200）
* **conda**：无（bioconda 无 stampy 包）
* **Docker / Singularity**：无官方镜像（无 bioconda 包 → 无自动构建）
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：<https://genome.cshlp.org/content/21/6/936.full>
