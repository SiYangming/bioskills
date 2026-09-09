# wgs-assembler 软件模块（Celera Assembler — OLC 组装 + PBcR/PacBioToCA 纠错）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **Celera Assembler（wgs-assembler，wgs-8.3rc2）** 是经典 Overlap-Layout-Consensus
> （OLC）组装器（Celera Genomics 开发、人类基因组计划时期；Myers et al. *Science*
> 2000），支持 Sanger / 454 / Illumina 等多平台测序组装；**PacBioToCA / PBcR** 是其
> PacBio 长读纠错/组装扩展（属同一软件，**不单独成模块**，2026-09 并入本模块）。
> 上游 **2015-05-24 发布 wgs-8.3rc2 后停止发布**；官方 wiki 声明：
> *"Celera Assembler is no longer being maintained … please use **Canu** instead."*
>
> **新项目请勿使用**——改用 Canu（PBcR 的官方继任者）/ Flye /
> hifiasm（HiFi 工具链 ccs/lima 预处理）。本模块只做「录入」：方法/命令/链接
> 准确登记、无官方当前维护镜像推荐、不产出自建容器配方（Dockerfile/Apptainer.def），
> 仅供复现 2012–2015 时代的 Celera/PacBio 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按历史教程构造 Celera 命令行并
打印，**不实际执行**（软件 deprecated、无新用场景；且二进制无 `--version` 旗标）。
三个子命令对应 Celera 两条主线用法：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `fastqtoca` | `fastqToCA -insertsize <mean> <stddev> -libraryname <name> -mates f1,f2`（或 `-reads`） | 双端/单端 FASTQ → Celera `.frg` 库文件（stdout；组装与 PBcR 的公共输入） |
| `pbcr` | `PBcR -libraryname X -s spec [-fastq pacbio.fasta] [-genomeSize N] [-maxCoverage 40] [-length L] [-partitions P] illumina.frg` | **PacBioToCA/PBcR 混合纠错/组装**；spec 内 `assemble=0` 时仅纠错；省略位置 frg → 自纠错模式 |
| `runca` | `runCA -d <out_dir> -p <prefix> -s celera.spec <input.frg...>` | **runCA OLC 组装**：frg + spec → Contig/Scaffold（`.ctg/.scf`） |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 wgs-8.3rc2，见「环境安装」）
python main.py fastqtoca --library-name pe150 --mate1 f1.fastq.gz \
    --mate2 f2.fastq.gz --frg-out illumina.frg   # insertsize 默认 177/25
python main.py pbcr --library-name X --spec pacbio.spec \
    --fastq pacbio.fasta --genome-size 5000000 --max-coverage 40 illumina.frg
python main.py runca --out-dir celera_assembly --prefix E_coli \
    --spec celera.spec pe180.frg

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`auto` 或正整数；正整数透传 PBcR 8.3 `-t`）与
`--tmpdir`。构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

## 实战示例 1：runCA OLC 组装（历史流程；等价能力 = `native/main.py runca`）

以下为经典 E. coli Illumina PE 组装教程（2012–2015 时代）的典型步骤，仅历史复现：

```bash
mkdir -p celera_assembly && cd celera_assembly
# 0) 准备数据（示例：BLESS 纠错后的双端 reads → 符号链接）
ln -s ~/.../fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/.../fragment.2.corrected.fastq fragment.2.fastq

# 1) FASTQ → Celera frg（-insertsize 均值/标准差；-technology illumina）
fastqToCA -libraryname=pe180 -insertsize=177 -insertstdev=25 \
  -reads=pe -technology=illumina \
  fragment.1.fastq fragment.2.fastq > pe180.frg

# 2) spec 配置文件（完整参数模板见 native/celera.spec.example；核心几项：）
echo "unitigger = bogart
utgErrorRate = 0.03
merSize = 22
doFragmentCorrection = 1
cnsErrorRate = 0.03
ovlErrorRate = 0.03
cnsMaxCoverage = 40
merylMemory = 65536
merylThreads = 4" > celera.spec

# 3) 运行组装（-d 输出目录；-p 前缀；-s spec；frg 为位置参数）
runCA -d celera_assembly -p E_coli -s celera.spec pe180.frg
# 产物在 <out_dir>/<prefix>/<stage>/ 下分层；最终在 9-terminator/ 目录

# 4) 格式化最终序列（可选；去内部 gap 标记）
genome_seq_clear.pl --seq_prefix celera \
  celera_assembly/E_coli/9-terminator/E_coli.ctg.fasta > Celera_Assembler.fasta
```

> 组装按阶段推进（gatekeeper → overlap → unitiger → scaffolder → consensus），
> 各阶段在 `<out_dir>/<prefix>/` 下生成中间目录；某步失败可从对应步骤重跑。

### 主要结果文件

| 文件 | 说明 |
| ---- | ---- |
| `*.ctg.fasta` | Contig 序列（FASTA） |
| `*.scf.fasta` | Scaffold 序列（FASTA） |
| `*.ctg.fastq` / `*.scf.fastq` | Contig / Scaffold 序列（FASTQ，含质量） |
| `*.ctgStore` / `*.scfStore` | Contig / Scaffold 存储（二进制中间文件） |

***

## 实战示例 2：PacBioToCA / PBcR 混合纠错（历史流程；等价能力 = `native/main.py pbcr`）

PacBioToCA（PBcR）用 Illumina 高保真短读把 PacBio CLR 长读纠错（hybrid
correction），首个 hybrid 纠错组装流程（Koren et al. *Nat Biotechnol* 2012）：

```bash
# 1) Illumina 双端 → frg（insertsize 期望 177 bp ± 25）
fastqToCA -insertsize 177 25 -libraryname pe150 -mates f1.fastq,f2.fastq > illumina.frg
# 2) PBcR 混合纠错（-genomeSize 为期望基因组大小 bp；-maxCoverage 截断覆盖度）
PBcR -libraryname X -s pacbio.spec -fastq pacbio.fasta \
     -genomeSize 5000000 -maxCoverage 40 illumina.frg
#    产物：X.frg（单 LIB 消息，可喂 runCA）、X.fasta/.qual/.fastq（校正 reads）、X.log
# 3) 仅纠错不组装：spec 写 assemble=0（如：genomeSize=… / maxCoverage=… / assemble=0）
```

参数说明（**录入**；2026-09 对照官方 wiki PBcR 页与 release README）：

| 参数 | 说明 |
| ---- | ---- |
| `-libraryname`（`-l`） | 文库 UID 名，无空格/逗号，必填（8.3 wiki usage 写作 `-l libraryname`） |
| `-s <spec>` | CA spec 文件，必填；`assemble=0` 仅纠错不组装 |
| `-fastq <pacbio.fasta>` | 待纠错 PacBio 长读（历史 hybrid 教程写法；8.3 wiki 现写为 `fastqFile=...` 位置参数） |
| `-genomeSize` | 期望基因组大小 bp（可写于 spec / 命令行） |
| `-maxCoverage` | 截断覆盖度（默认最长 40X） |
| `-length` / `-partitions` | 保留的 PacBio 片段最小长度 / consensus 分区数（可选） |
| `-t` | 线程数（8.3 wiki；可选） |
| 位置参数 `.frg` | 高保真（Illumina/454/CCS）frg，作为纠错 trusted 序列；省略 → 自纠错（需 PacBio C2+ 化学、约 50X） |

> 命令行参数存在**版本形态差异**（如实记录）：本文采用历史 hybrid 教程写法
> （`-libraryname/-fastq/-genomeSize/-maxCoverage` + 位置 frg，对应 8.2-era）；
> 官方 8.3 wiki 现用 usage 为 `PBcR [options] -s spec.file fastqFile=... [frg]`。
> 复现时以所对应教程/文档版本为准。

***

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # 本机已装 wgs-8.3rc2 时追加 fastqtoca 真实冒烟（.frg 非空）
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-08 在线核实，如实记录）：**上游已停更（2015-05-24 后无发布）**；
> bioconda 存在 **wgs-assembler=8.3** 历史包（最后更新 2017-02-22、perl 5.22 老构建
> `pl5.22.0_0`、仅 linux-64、依赖 2017 时代 blasr/falcon/pbdagcon 等）→ quay.io/
> biocontainers 与 depot.galaxyproject.org 有自动构建镜像（tag `8.3--pl5.22.0_0`，
> 2026-09 仍在、可拉取）；但**多年未随上游维护** → 判定「官方渠道存在但属历史遗留，
> 不建议新项目依赖」；软件 deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**
> （容器仅登记历史镜像，见 §2/§3）。宿主机安装推荐官方源码编译路线（§4 /
> `native/install.sh`）。**新项目请直接用 Canu/Flye/hifiasm。**

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 wgs-assembler=8.3（linux-64；2017-02 后未维护，
#        老 perl 5.22 构建 + 2017 时代依赖，仅历史复现；main.py 同环境见
#        native/environment.yml，或 --method conda 一键）
mamba create -n wgs-assembler-native -c conda-forge -c bioconda wgs-assembler=8.3
# 或一键：bash native/install.sh --method conda（自动建独立 env 并断言二进制）

# Homebrew：无公式（2026-09 核实 homebrew-core 404、brewsci/bio 404）→ 不登记 brew 块
```

> brew 判定记录：homebrew-core `formulae.brew.sh/api/formula/wgs-assembler.json`
> 404；brewsci/homebrew-bio `Formula/wgs-assembler.rb` 404 → 两源均无公式，
> README 不写 brew 安装块（符合 AGENT §7 登记规则）。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 8.3 老包自动构建，
版本号 8.3 对应上游 8.3rc2 时代源码）：

```bash
docker pull quay.io/biocontainers/wgs-assembler:8.3--pl5.22.0_0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/wgs-assembler:8.3--pl5.22.0_0 \
    fastqToCA -insertsize 177 25 -libraryname pe150 -mates f1.fastq,f2.fastq
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09-08 HEAD 核实存在，与 quay tag 互通）：

```bash
apptainer pull wgs-assembler.sif docker://depot.galaxyproject.org/singularity/wgs-assembler:8.3--pl5.22.0_0
apptainer run -B $PWD:/data -H /data wgs-assembler.sif \
    PBcR -libraryname X -s /data/pacbio.spec -genomeSize 5000000 -maxCoverage 40 /data/illumina.frg
```

### 4. 二进制包安装（官方 release / 源码编译）

官方无 GitHub release；资产在 sourceforge 文件区
`wgs-assembler/wgs-8.3/`（2015）：源码 `wgs-8.3rc2.tar.bz2`（24.6 MB）与
预编译 `wgs-8.3rc2-Linux_amd64.tar.bz2`（34.6 MB）、`wgs-8.3rc2-Darwin_amd64.tar.bz2`
（22.5 MB，2015-12-22）。一键（推荐，默认官方源码编译路线，命令与官方 README
一致，免 root）：

```bash
bash native/install.sh                      # auto → source：源码编译
bash native/install.sh --method source --prefix ~/software/wgs-8.3rc2
# 底层即官方 README 编译步骤：
#   bzip2 -dc wgs-8.3rc2.tar.bz2 | tar -xf - && cd wgs-8.3rc2
#   cd kmer && make install && cd .. && cd src && make
# 产物在 wgs-8.3rc2/Linux-amd64/bin（runCA / fastqToCA / PBcR / meryl …）；
# install.sh 会写 PATH 并断言三个核心二进制存在（无 --version 可判）
```

手动（预编译包，免编译；2015 二进制对现代 glibc/macOS 兼容性未核实）：

```bash
mkdir -p ~/software && cd ~/software
curl -fL -O https://downloads.sourceforge.net/project/wgs-assembler/wgs-assembler/wgs-8.3/wgs-8.3rc2-Linux_amd64.tar.bz2
bzip2 -dc wgs-8.3rc2-Linux_amd64.tar.bz2 | tar -xf -
export PATH="$HOME/software/wgs-8.3rc2/Linux-amd64/bin:$PATH"
```

**Perl 依赖**：PBcR 等驱动脚本需 `Statistics::Descriptive`（conda 渠道无该模块包，
2026-09 核实）→ `cpanm Statistics::Descriptive`（或 Debian/Ubuntu
`apt-get install libstatistics-descriptive-perl`；install.sh 已做探测提示）。
完整依赖见 release README（源码包内嵌 kmer r1994、SAMtools、Jellyfish 2.0、
BLASR、PBDAGCON、部分 FALCON）。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **Canu** | PBcR 的官方继任者（wgs 团队，2016–2021 维护；支持自纠错 + 组装 + 网格） | <https://github.com/marbl/canu>（bioconda `canu`） |
| **Flye** | 长读 de novo 组装（PacBio CLR/ONT），无短读依赖 | <https://github.com/fenderglass/Flye>（bioconda `flye`） |
| **ccs + lima + hifiasm** | 新版 HiFi 工具链：`pbccs` 产 HiFi → `lima` 去 barcode → `hifiasm` 组装（本仓库另见 `pbccs` / `lima` 模块） | <https://github.com/chhylp123/hifiasm>（bioconda `hifiasm`） |

## 版本

* **wgs-8.3rc2**（2015-05-24 发布，sourceforge 文件区最新；2015-12-22 追加
  Darwin_amd64 预编译；**上游无正式 8.3**，2026-09 在线核实文件区无更新）
* bioconda 版本号 **8.3**（2017-02-22 最后更新；对应上游 8.3rc2 时代源码——
  推断未逐一核对 recipe）
* License：**GPL-2.0**（官方 release README：「…open-source … subject to the
  GNU General Public License, version 2」；Copyright 1999–2004 Applera Corp. /
  2005–2013 J. Craig Venter Institute）
* 引用：Berlin K. et al. *Nat Biotechnol* 2015（MHAP/PBcR 非 hybrid，CA ≥8.2）；
  Koren S. et al. *Nat Biotechnol* 2012（PBcR hybrid 纠错原论文）；Myers EW. et al.
  *Science* 2000（Celera Assembler 本体）
* nf-core / snakemake-wrappers：无官方子模块（2026-09-08 核实
  `modules/nf-core/wgs-assembler`、`bio/wgs-assembler` 均 404）→ 不登记官方说明层

## 历史留存

* **模块归并**：2026-09 按「PacBioToCA 属 Celera Assembler (wgs) 软件、不应单独列
  模块」把原 `modules/pacbiotoca/`（fastqtoca/pbcr 两子命令）并入本模块并补 runca
  组装子命令；旧工作流 A（`.bas.h5` SMRT 导出，未核实）、工作流 B（新版 BAM → 现代
  工具链 hifiasm/Flye，勿回 PBcR）细节见 git 历史 `modules/pacbiotoca/README.md`。
* **spec 模板**：完整 runCA/PBcR spec 参数集（unitigger/scf 容差/meryl/ovl/frgCorr/
  cns 全段）归档于 `native/celera.spec.example`。

## 容器与 Conda 链接

* **sourceforge 项目 / wiki**：<http://wgs-assembler.sourceforge.net/>（wiki
  首页与 PBcR 页顶部即 deprecated 声明；部分页面触发 Cloudflare 人机验证，浏览器可看）
* **继任者（官方声明入口）**：<https://github.com/marbl/canu>
* **文件区**：<https://sourceforge.net/projects/wgs-assembler/files/wgs-assembler/wgs-8.3/>
  （源码 + Linux/Darwin 预编译；**官方未提供 sha256 摘要页 → 下载校验值未核实**）
* **conda**：bioconda `wgs-assembler=8.3`（历史包，2017 后未维护）→
  <https://anaconda.org/bioconda/wgs-assembler>
* **Docker / Singularity**：`quay.io/biocontainers/wgs-assembler:8.3--pl5.22.0_0`（历史镜像）
  / depot.galaxyproject.org 同名 sif
* **brew**：无公式（两源 404 核实）
* 安装方式（本地）：`bash native/install.sh`（默认官方源码编译路线），详见
  「环境安装」§4
