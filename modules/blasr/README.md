# blasr 软件模块（BLASR — PacBio 旧长读比对器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **BLASR（Basic Local Alignment with Successive Refinement，5.3.5）** 是 PacBio
> 官方研发的**首个**面向 SMRT 单分子长读（CLR）的比对器（Chaisson & Tesler,
> *BMC Bioinformatics* 2012;13:238）：banded 比对 + 逐级精化（successive
> refinement），把高错误率长读比对到参考基因组。程序族：**sawriter**（参考 FASTA
> → `.sa` 后缀数组索引）与 **blasr**（reads + 参考 + `.sa` → SAM/BAM）。
>
> 官方仓库 **PacificBiosciences/blasr 2026-09-09 核实已不可达（GitHub 404）**；
> 官方继任者声明见 PacificBiosciences/pbmm2 README：*"pbmm2 … is the official
> replacement for BLASR"*（minimap2 的 SMRT 包装）。bioconda 停驻 blasr=5.3.5。
>
> **新项目请勿使用**——改用 **minimap2 / pbmm2**（本仓库另见 `minimap2` 模块）。
> 本模块只做「录入」：方法/命令/链接准确登记、不产出自建容器配方
> （Dockerfile/Apptainer.def），仅供复现 2012–2019 时代的 BLASR 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方用法构造 BLASR 命令行并打印，
**不实际执行**（软件 deprecated、官方仓库 404、无新用场景）。两个子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `sawriter` | `sawriter <reference.fasta> <out.sa>` | 参考 FASTA → `.sa` 后缀数组索引 |
| `blasr` | `blasr <reads> <reference.fasta> <reference.sa> [--out x.bam --bam] [--nproc N] [--bestn 10] [--minPctIdentity 70]` | PacBio 长读比对（SAM/BAM/原生格式） |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 blasr 5.3.5，见「环境安装」）
python main.py sawriter ref.fa ref.sa
python main.py blasr subreads.fasta ref.fa ref.sa --out aln.bam --bam \
    --nproc 8 --bestn 10

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`auto` 默认透传 `--nproc 4`，正整数透传 `--nproc`）与
`--tmpdir`。构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

## 实战示例：BLASR PacBio CLR 比对（历史流程；等价能力 = `native/main.py` 两子命令）

以下为 2015–2019 时代经典 PacBio 长读比对教程步骤，仅历史复现。原教程惯用
`/opt/biosoft/blasr` 等绝对安装前缀与 `/home/train` 数据目录，此处改写为**用户
前缀** `~/software/blasr`（免 root；原始路径见「历史留存」）：

```bash
# 0) 准备：conda 安装 blasr（见「环境安装」），参考 FASTA 在 ~/refs/
# 1) 建 .sa 索引（参考 FASTA → ref.fa.sa）
sawriter ref.fa ref.fa.sa
# 2) 比对（BAM 输出 + 线程 + bestn；subreads 为 PacBio reads）
blasr subreads.fasta ref.fa ref.fa.sa --out aln.bam --bam \
    --nproc 8 --bestn 10 --minPctIdentity 70
# 3) SAM 输出（可选）
blasr subreads.fasta ref.fa ref.fa.sa --out aln.sam --sam --nproc 4
```

> 历史流程中 BLASR BAM 输出直接喂 **pbalign / GenomicConsensus（Quiver）** 做
> 一致性抛光，或交 Falcon/Canu 组装流程；现代工具链请用 pbmm2/minimap2。

### 参数说明（录入；2026-09 对照官方 usage 与历史文档）

| 参数 | 适用 | 说明 |
| ---- | ---- | ---- |
| `sawriter <ref.fa> <out.sa>` | sawriter | 参考 FASTA → 后缀数组索引（blasr 第三位置参数） |
| `<reads>` | blasr | 输入 PacBio reads（FASTA/FASTQ；历史亦可 .bas.h5/BAM） |
| `<reference.fasta>` | blasr | 参考基因组 FASTA |
| `<reference.sa>` | blasr | sawriter 产出的 .sa 索引 |
| `--out FILE` | blasr | 输出文件（--bam 需 .bam 后缀） |
| `--bam` / `--sam` | blasr | 输出 BAM（PacBio 推荐）/ SAM（默认原生格式，二选一） |
| `--nproc N` | blasr | 线程数（默认 4） |
| `--bestn N` | blasr | 每 read 最多报告 hits 数（默认 10） |
| `--minPctIdentity F` | blasr | 最低比对一致率阈值（如 70；可选） |

**历史教程参数对照（旧版 blasr CLI 形态；5.x 用法见上表，勿混用）**：

早期版本（3.x 时代、SMRT Analysis 打包版）命令行形态与参数示例：

```bash
blasr subreads.fasta genome.fasta --sa genome.fasta.sa --header -m 5 \
      --out blasr.out5 --minPctAccuracy 70 --nproc 8 --stride 10
```

| 历史参数 | 说明 | 备注 |
| ---- | ---- | ---- |
| `--sa genome.fasta.sa` | 使用 suffix array 索引（旧式 flag 传入） | 5.x 改为位置参数 `<reference.sa>`（见上表） |
| `-m 5` | 输出格式 M5（tabular 格式，m4/m5/m8 属旧式输出族） | 5.x 用 `--out` + `--sam/--bam` |
| `--minPctAccuracy 70` | 最小比对准确率 70% | 5.x 对应 `--minPctIdentity 70` |
| `--stride 10` | 种子步长，影响比对速度与灵敏度 | 低层种子参数（5.x 调参见 `blasr --help`，不逐一映射） |
| `--header` | 输出头部信息 | 5.x 由输出格式/`--header` 体系决定 |

> 💡 **长读长比对要点**：PacBio 数据错误率较高（约 15%），比对需设较高容错
> （如 `--minPctAccuracy/--minPctIdentity 70`）。blasr 专为 PacBio 数据设计，
> 长读长比对表现优异（历史定位）；现代 PacBio 工具链请用 pbmm2 / minimap2。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-09 在线核实，如实记录）：**上游已停更且官方仓库 404**（源码
> 只能走 fork/归档，如 mchaisso/blasr，200）；bioconda 存在 **blasr=5.3.5** 历史包
> （license=BSD-3-Clause-Clear）→ quay.io/biocontainers 与 depot.galaxyproject.org
> 有自动构建镜像；软件 deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**
> （容器仅登记历史镜像）。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 blasr=5.3.5（linux-64/osx-64 等；license=BSD-3-Clause-Clear）
mamba create -n blasr-native -c conda-forge -c bioconda blasr=5.3.5
conda activate blasr-native
blasr --version 2>&1 | head -1 || blasr --help 2>&1 | head -3   # 断言命令可达
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/blasr.json）与 brewsci/bio
> （Formula/blasr.rb）均 404（2026-09-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；bioconda 5.3.5 自动构建历史镜像可作复现（tag 以
quay.io/biocontainers/blasr 在线目录为准）：

```bash
docker pull quay.io/biocontainers/blasr:5.3.5--0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/blasr:5.3.5--0 \
    blasr /data/subreads.fasta /data/ref.fa /data/ref.fa.sa \
          --out /data/aln.bam --bam --nproc 4
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（与 quay tag 互通；tag 以在线目录为准）：

```bash
apptainer pull blasr.sif docker://depot.galaxyproject.org/singularity/blasr:5.3.5--0
apptainer run -B $PWD:/data -H /data blasr.sif \
    blasr /data/subreads.fasta /data/ref.fa /data/ref.fa.sa \
          --out /data/aln.bam --bam --nproc 4
```

### 4. 二进制/源码安装（官方 release / 源码编译）

官方 GitHub release 随仓库 404 而不可见；源码可取自**社区 fork**（200，
2026-09-09 核实）：`github.com/mchaisso/blasr`（master，末次提交 2019-04；
需 HDF5 C++ 库等，见该 fork README）。**推荐优先走 bioconda blasr=5.3.5**
（免编译）；源码编译仅离线/特殊场景兜底。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **minimap2** | 通用长读/短读比对器，PacBio CLR/HiFi/ONT 均适用（本仓库另见 `minimap2` 模块） | <https://github.com/lh3/minimap2>（bioconda `minimap2`） |
| **pbmm2** | PacBio 官方继任者（minimap2 SMRT 包装；原生 PacBio BAM 输入输出，README 明示 official replacement for BLASR） | <https://github.com/PacificBiosciences/pbmm2>（bioconda `pbmm2`） |
| **NGMLR** | 长读结构变异比对（可选） | <https://github.com/philres/ngmlr> |

## 版本

* **5.3.5**（bioconda 最新版本号；2026-09-09 api.anaconda.org 核实 latest=5.3.5、
  历史版本 5.3.2/5.3.3 等在列）
* 上游源码时代：fork mchaisso/blasr 末次提交 2019-04-15（官方仓库已 404，无法
  直接核实官方最终 tag）
* License：**BSD-3-Clause-Clear**（bioconda 包元数据）
* 引用：Chaisson MJ, Tesler G. Mapping single molecule sequencing reads using
  basic local alignment with successive refinement (BLASR): application and
  theory. *BMC Bioinformatics* 2012;13:238. doi:10.1186/1471-2105-13-238
* nf-core / snakemake-wrappers：无官方子模块（2026-09-09 核实
  `modules/nf-core/blasr`、`bio/blasr` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装路径为 **`/opt/biosoft/blasr`**（root 全局前缀）或 conda 环境
  `blasr`（`/home/train` 系数据目录）；本 README 一律改写为**用户前缀**
  `~/software/blasr`（免 root）。
* 官方仓库 PacificBiosciences/blasr 历史上有过 wiki（含 sawriter/blasr 完整参数
  与教程）；2026-09-09 该仓库 404 → 上述参数表以 bioconda 包内二进制 usage 与
  历史文档/第三方教程为准（已尽量核对，个别长选项细节以本机 `blasr --help`
  输出为准）。
* 历史配套：BLASR 比对结果接 GenomicConsensus（Quiver/Arrow 抛光）、Falcon/
  Canu 组装、phylogenetic 分析等；现代流程建议整体迁移 minimap2/pbmm2 工具链。
* 旧版 BLASR（<5.0）依赖 PacBio .bas.h5 格式与旧 HDF5 库；5.x 移除了部分 HDF5
  依赖（fork 2019-04 提交 "Removed hdf5 from blasr"），历史复现注意版本配套。

## 容器与 Conda 链接

* **官方仓库（已 404）**：<https://github.com/PacificBiosciences/blasr>
* **社区 fork（源码，200）**：<https://github.com/mchaisso/blasr>
* **官方继任者（声明入口）**：<https://github.com/PacificBiosciences/pbmm2>
* **conda**：bioconda `blasr=5.3.5` → <https://anaconda.org/bioconda/blasr>
* **Docker / Singularity**：`quay.io/biocontainers/blasr:5.3.5--0`（历史镜像，
  tag 以在线目录为准）/ depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：<https://bmcbioinformatics.biomedcentral.com/articles/10.1186/1471-2105-13-238>
