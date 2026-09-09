# gmap 软件模块（GMAP/GSNAP — 剪接感知基因组比对套件）

> GMAP/GSNAP 套件（Thomas Wu, Genentech）：**GMAP**（Wu & Watanabe,
> *Bioinformatics* 2005;21:1859-75）把 mRNA/EST/全长转录本比对到基因组（剪接
> 感知、容忍长 indel）；**GSNAP**（Wu & Nacu, *Bioinformatics* 2010;26:873-81）
> 做短读 SNP/indel 容忍比对（含双端、bisulfite、fusion）。**非 deprecated
> （2026-09 登记）**：官方 research-pub.gene.com 持续维护分发源码包
> （2026-09-09 核实 gmap-gsnap-2025-07-31.v2.tar.gz 直链 **200**）；bioconda 有
> gmap（最新 2025.07.31）。

***

## native 实现（真实命令构造 + 执行，`source_type: custom` / `type: native`）

本实现为「真实命令构造 + 执行」：`native/main.py` 按官方 manual 构造并运行
gmap_build / gmap / gsnap（本地已装 gmap 时真实运行）。三个子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `gmap_build` | `gmap_build -D <dir> -d <dbname> [--gunzip] <genome.fasta>` | 基因组 FASTA → GMAP 数据库（`<dir>/<dbname>/`） |
| `gmap` | `gmap -D <dir> -d <dbname> -t <N> [-f samse\|sampe\|bed...] <reads...>` | mRNA/EST/长读剪接感知比对 |
| `gsnap` | `gsnap -D <dir> -d <dbname> -t <N> [-A sam] <reads...>` | 短读 SNP/indel 容忍比对 |

```bash
# CLI 直跑（需本机已装 gmap，见「环境安装」）
python main.py gmap_build -d genome genome.fa
python main.py gmap -D . -d genome -t 8 -f samse mrna.fa
python main.py gsnap -D . -d genome -t 8 -A sam reads_1.fq reads_2.fq

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

***

## 实战示例：GMAP 建库 + mRNA 定位、GSNAP 短读比对（等价能力 = `native/main.py` 三子命令）

以下为官方 manual/FAQ 经典流程。历史教程常见把 gmap 装到 `/opt/biosoft/gmap`
或 `/usr/local` 并在 `/home/train` 数据目录跑；此处统一**用户前缀**
`~/software/gmap`（免 root；原始路径见「历史留存」）：

```bash
# 0) 准备：安装 gmap 到用户前缀（见「环境安装」）
export PATH="$HOME/software/gmap/bin:$PATH"

# 1) 建 GMAP 数据库（-D 目录 -d 库名；基因组 FASTA；大基因组建议 8 线程并行）
mkdir -p dbs
gmap_build -D dbs -d genome genome.fa
#    产物 dbs/genome/（2021-12-17 后新格式：含 genome/ 与 version/ 子目录）
# 2) GMAP：mRNA/EST 剪接定位（单端 -f samse；双端两个文件 -f sampe）
gmap -D dbs -d genome -t 8 -f samse mrna.fa > mrna.sam
gmap -D dbs -d genome -t 8 -f sampe reads_1.fq reads_2.fq > pe.sam
# 3) GSNAP：短读比对（SNP 容忍；-A sam 输出 SAM；双端给两个文件）
gsnap -D dbs -d genome -t 8 -A sam reads_1.fq reads_2.fq > gsnap.sam
```

> GMAP/GSNAP 数据库索引**与版本强相关**（2021-12-17 起新索引格式）：换 gmap
> 版本后需重新 `gmap_build`。基因组 FASTA 需规范（染色体命名一致）；人/小鼠等
> 常用物种也可直接用官方预建数据库（research-pub.gene.com 提供）。

### 参数说明（录入；2026-09 对照官方 manual/FAQ）

| 参数 | 适用 | 说明 |
| ---- | ---- | ---- |
| `-D <dir>` | 三者 | 数据库目录（默认当前目录；建库/比对需一致） |
| `-d <name>` | 三者 | 数据库名（gmap_build 建库名；比对时 -d 同名） |
| `--gunzip` | gmap_build | 参考 FASTA 为 .gz（自动解压建库） |
| `-t <N>` | gmap/gsnap | 线程数（本驱动 auto 给 4） |
| `-f <fmt>` | gmap | 输出格式 samse/sampe/bed/gff3_gene 等（默认 gmap 原生坐标输出） |
| `-A sam` | gsnap | 输出 SAM（gsnap 亦默认 SAM 相关输出，-A 显式指定格式） |
| `-n <N>` | gmap/gsnap | 每 read 报告比对路径数（默认 5） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省恒跑；stub 假二进制 CLI 冒烟
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（官方源码包直链 200 + bioconda `gmap` → quay.io/biocontainers /
depot.galaxyproject.org，2026-09-09 核实），直接拉取官方渠道运行工具本体；本地
不维护 Dockerfile/Apptainer.def。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda gmap=2025.07.31（linux-64/osx-64/osx-arm64；perl-threaded 依赖）
mamba create -n gmap-native -c conda-forge -c bioconda gmap=2025.07.31
conda activate gmap-native
gmap --version 2>&1 | head -1            # 断言（GMAP 支持 --version）
gsnap --version 2>&1 | head -1
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/gmap.json）与 brewsci/bio
> （Formula/gmap.rb）均 404（2026-09-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/gmap:2025.07.31--pl5321ha904f4b_1
# 运行工具本体（注意 -u $(id -u):$(id -g)，否则产物归 root；tag 以 quay 在线目录为准）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/gmap:2025.07.31--pl5321ha904f4b_1 \
    gmap_build -D /data/dbs -d genome /data/genome.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（与 quay tag 互通）：

```bash
apptainer pull gmap.sif docker://depot.galaxyproject.org/singularity/gmap:2025.07.31--pl5321ha904f4b_1
apptainer run -B $PWD:/data -H /data gmap.sif \
    gmap -D /data/dbs -d genome -f samse /data/mrna.fa
```

### 4. 源码编译安装（官方源码包）

官方发布源码包（无需 git，免登录直链 200）：

```bash
mkdir -p ~/software && cd ~/software
curl -fL -O http://research-pub.gene.com/gmap/src/gmap-gsnap-2025-07-31.v2.tar.gz
tar zxf gmap-gsnap-2025-07-31.v2.tar.gz && cd gmap-gsnap-2025-07-31
./configure --prefix="$HOME/software/gmap" && make -j8 && make install
export PATH="$HOME/software/gmap/bin:$PATH"
gmap --version    # 断言
```

> 依赖 gcc/g++ 与 make；macOS/ARM（M1/M2）官方声明可编译（2021-12-17 起支持
> Apple ARM）。官网首页展示版本为 2025-04-19；`gmap-gsnap-2025-07-31.v2.tar.gz`
> 为渠道可下载的最新源码包（2026-09-09 核实 200、无更新版本）。

## 替代建议（使用定位）

| 工具 | 定位 | 说明 |
| ---- | ---- | ---- |
| **GMAP**（本模块） | mRNA/EST/全长转录本剪接定位、iso-seq 比对 | 剪接感知 + 长 indel 容忍；官方持续维护 |
| **GSNAP**（本模块） | SNP/indel 容忍短读比对、bisulfite | 与 GMAP 同库 |
| **STAR** | RNA-seq 短读剪接比对主流（本仓库另见 `star` 模块） | 定量流程（RSEM/StringTie）常用更高效 |
| **HISAT2** | RNA-seq 剪接比对（graph 索引） | nf-core 生态常用 |
| **minimap2** | 三代/长读通用比对（本仓库另见 `minimap2` 模块） | iso-seq 流程（本仓库 `isoseq3`/`flair` 等）亦可配 minimap2 |

## 版本

* **2025-07-31**（官方 gene.com 源码包 gmap-gsnap-2025-07-31.v2.tar.gz，直链 200；
  官网主页展示版本 2025-04-19；2026-09-09 探测无更新版本）
* bioconda：**gmap=2025.07.31**（latest；2026-09-09 api.anaconda.org 核实；
  历史版本 2024.x/2023.x 等 42 个版本在列）
* License：学术/非商业免费（官方长期政策；商用需授权）；bioconda 元数据 top-level
  license=Apache-2.0、具体 build attrs=Non-commercial（2026-09-09 核实，以官方
  源码包内 LICENSE 为准）
* 引用：Wu TD, Watanabe CK. GMAP: a genomic mapping and alignment program for
  mRNA and EST sequences. *Bioinformatics* 2005;21(9):1859-75；Wu TD, Nacu S.
  Fast and SNP-tolerant detection of complex variants and splicing in short
  reads. *Bioinformatics* 2010;26(7):873-81
* nf-core / snakemake-wrappers：无官方子模块（2026-09-09 核实
  `modules/nf-core/gmap`、`bio/gmap` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装路径为 **`/opt/biosoft/gmap`**（root 全局前缀）或 configure
  `--prefix=/usr/local`，数据目录常用 `/home/train` 系；本 README 一律改写为
  **用户前缀** `~/software/gmap`（免 root）。
* 官方旧下载入口 `research-pub.gene.com/gmap/src/` 自 2000 年代延续至今；早期
  版本号形如 `2010-07-30`、`2021-12-17`（格式为日期）——GMAP/GSNAP 一直以
  **发布日期**为版本号（本模块登记 2025-07-31 同理）。
* **索引格式变更**：2021-12-17 版起使用新基因组/转录组索引格式（要求重新
  gmap_build；README 官网 changelog 有 "Uses a new genome/transcriptome index
  format, so it requires re-running gmap_build"）。历史项目若沿用旧库升级 gmap
  需重建，属预期行为。

## 容器与 Conda 链接

* **官方页面**：<http://research-pub.gene.com/gmap/>
* **官方源码包（2025-07-31，200）**：<http://research-pub.gene.com/gmap/src/gmap-gsnap-2025-07-31.v2.tar.gz>
* **官方 GitHub 仓库**：<https://github.com/Genentech/gmap-gsnap>（Genentech 托管源码镜像 / 提交追踪；正式发布仍走上方 gene.com 源码包）
* **conda**：bioconda `gmap=2025.07.31` → <https://anaconda.org/bioconda/gmap>
* **Docker / Singularity**：`quay.io/biocontainers/gmap:2025.07.31--pl5321ha904f4b_1`
  （tag 以在线目录为准）/ depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：<https://academic.oup.com/bioinformatics/article/21/9/1859/202851>
