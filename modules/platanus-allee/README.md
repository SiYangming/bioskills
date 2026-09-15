# platanus-allee 软件模块

> 汇总说明：本 README 合并 native 实现用法；安装方式见下方各节，容器与 conda 信息记录于此。
>
> **命名说明**：本模块 canonical 目录名为 `platanus-allee`（二进制 `platanus_allee`，即文档中
> 「Platanus / Platanus-allee」的升级版）。经典 **Platanus**（`platanus`，github.com/rkajitani/Platanus，
> v1.2.6）为同作者旧工具；2026-09 核实 bioconda `platanus` 与 `platanus-allee` **均无包**（404），
> 二者均未建独立模块，本模块只覆盖文档实际安装/使用的 Platanus-allee。

***

## native 实现

# platanus-allee / native — 自包含单倍型组装驱动

Platanus-allee 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

Platanus 是一个基于 de Bruijn Graph 的基因组组装工具，适用于二代测序数据的基因组组装。Platanus-allee 是其升级版本，支持二倍体基因组的等位基因分型组装，能够区分等位基因序列，适用于杂合基因组的组装。

三个子命令对应 Platanus-allee 的单倍型组装三段链路：

| 子命令         | 命令                                                                                                                    | 作用                                    |
| ----------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `assemble`  | `platanus_allee assemble -t N [-o out] -f <reads...> [-k 32] [-m 16] -tmp <dir>`                                       | Illumina 短读 contig 组装                  |
| `phase`     | `platanus_allee phase -t N -c <contigs...> [-IP1 FWD REV] [-p <long reads...>] [-x <linked...>] [-o out] [-i 2] -tmp <dir>` | 结合长读/连锁读做单倍型 phasing                   |
| `consensus` | `platanus_allee consensus -t N -c <contigs...> [-IP1 FWD REV] [-p <long reads...>] [-o out] -tmp <dir>`                 | 拟单倍体 consensus（镶嵌式 draft）构建            |

> 依赖：GCC >= 4.4（OpenMP）；长读 phasing/consensus 需 minimap2；10X linked-reads 需 Long Ranger
> 预处理为 barcoded.fastq（`-x`）。

## 用法

```bash
# CLI 直跑
python main.py assemble -t 8 -f illumina.1.fastq illumina.2.fastq -o out
python main.py phase -t 8 -c out_contig.fa out_junctionKmer.fa -IP1 illumina.1.fastq illumina.2.fastq -p subreads.fasta
python main.py consensus -t 8 -c out_primaryBubble.fa out_nonBubbleHomoCandidate.fa -IP1 illumina.1.fastq illumina.2.fastq -p subreads.fasta

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（注入 `-t`）/ `--tmpdir`（注入 `-tmp`）运行期覆盖。

## 实战示例：Platanus-allee 单倍型组装（来自文档 04.md「17. Platanus / Platanus-allee」）

```bash
mkdir -p Platanus_allee && cd Platanus_allee
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq .
ln -s /home/train/04.genome_assembling/Canu/Malassezia_sympodialis/subreads.fasta ./

# 第一步：Illumina 短读 contigs 组装
platanus_allee assemble -t 8 -f illumina.1.fastq illumina.2.fastq 2>assemble.log

# 第二步：结合三代长读做 phasing（获得单倍基因组序列）
platanus_allee phase -t 8 \
  -c out_contig.fa out_junctionKmer.fa \
  -IP1 illumina.1.fastq illumina.2.fastq \
  -p subreads.fasta 2> phase.log

# 第三步：对基因组序列进行校正（consensus）
platanus_allee consensus -t 8 \
  -c out_primaryBubble.fa out_nonBubbleHomoCandidate.fa \
  -IP1 illumina.1.fastq illumina.2.fastq \
  -p subreads.fasta 2> consensus.log

# 格式化结果
genome_seq_clear.pl --seq_prefix platanus out_consensusScaffold.fa > Platanus.fasta
```

等价能力由 `native/main.py` 的 `assemble` / `phase` / `consensus` 子命令提供（见上「用法」），
线程与临时目录分别自动注入 `-t` / `-tmp`。

### 参数说明

| 参数                       | 子命令                | 说明                          |
| ------------------------ | ------------------ | --------------------------- |
| `-f`                     | assemble           | 输入 read 文件（fasta/fastq，可多个） |
| `-c`                     | phase / consensus  | contig/scaffold FASTA（可多个）   |
| `-IP1 FWD REV`           | phase / consensus  | inward-pair 文库（双端分文件）       |
| `-p`                     | phase / consensus  | PacBio/ONT 长读（需 minimap2）    |
| `-x`                     | phase / consensus  | 10X linked-reads（barcoded fastq） |
| `-o`                     | 全部                 | 输出前缀（默认 out，不得含 `/`）         |
| `-k`                     | assemble           | 初始 k-mer 长度（默认 32）           |
| `-m`                     | assemble           | k-mer 分布内存上限 GB（默认 16）       |
| `-t`                     | 全部                 | 线程数（<=100）                  |
| `-tmp`                   | 全部                 | 临时目录（默认 .）                  |
| `-mapper`                | phase / consensus  | minimap2 可执行路径              |
| `-minimap2_sensitive`    | phase / consensus  | minimap2 敏感模式               |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）2026-09 逐渠道核实**均无**
Platanus-allee 包/镜像（bioconda 404、quay 401=仓库不存在、depot 404），因此本地保留自建容器配方
（`native/Dockerfile` + `native/Apptainer.def`）。官方站点另提供**预编译二进制包**与官方 GitHub
**源码编译**两条官方路线，两条均保留（预编译优先）。

### 1. 官方预编译二进制包（官方站点，首选）

官方站点 <http://platanus.bio.titech.ac.jp/platanus2> 提供 Linux x86_64 预编译二进制：

```bash
# 官方站点下载页（v2.2.2 预编译 / v2.0.2 预编译；文件名为官方分发名）
#   v2.2.2 binary: http://platanus.bio.titech.ac.jp/?ddownload=431
#   v2.0.2 binary: http://platanus.bio.titech.ac.jp/?ddownload=347
tar zxf ~/software/Platanus_allee_v2.0.2_Linux_x86_64.tgz -C ~/software/
echo 'export PATH=$PATH:~/software/Platanus_allee_v2.0.2_Linux_x86_64' >> ~/.bashrc && source ~/.bashrc
platanus_allee -v   # 断言
```

> 一键安装：`bash native/install.sh --method binary --url <tgz下载地址>`（官方直链在本机网络不可达，
> 脚本不内置默认 URL，需显式提供）。
>
> ⚠️ 说明：官方下载页链接由官方站点 HTML 核实存在，但直链在不同网络下可达性不同；若下载失败请改用
> 下方源码编译路线（v2.4.0 为最新）。

### 2. 官方源码编译（并列保留）

```bash
# 官方 GitHub 源码 tag v2.4.0（最新）
wget https://github.com/rkajitani/Platanus-allee/archive/refs/tags/v2.4.0.tar.gz -O ~/software/Platanus-allee-2.4.0.tar.gz
tar zxf ~/software/Platanus-allee-2.4.0.tar.gz -C ~/software/
cd ~/software/Platanus-allee-2.4.0
make                       # 需要 GCC >= 4.4（支持 OpenMP）
mkdir -p ~/software/platanus-allee-2.4.0/bin
cp platanus_allee ~/software/platanus-allee-2.4.0/bin/
echo 'export PATH=$PATH:~/software/platanus-allee-2.4.0/bin' >> ~/.bashrc && source ~/.bashrc
platanus_allee -v          # 断言：platanus_allee version: 2.4.0
```

> 一键安装：`bash native/install.sh`（默认 source 路线：下载 v2.4.0 源码 → `make` → 安装到
> `~/software/platanus-allee-2.4.0/bin` 并写 PATH；版本断言 `platanus_allee -v`）。

### 3. Conda / brew（已核实无官方包）

2026-09 核实：bioconda `platanus` / `platanus-allee` 均 404、homebrew-core `formula/platanus.json` 404、
brewsci-bio `Formula/platanus.rb` 404 → **无 conda / brew 安装方式**，请走上方预编译或源码编译路线。

### 4. Docker（本地自建镜像）

官方无镜像，使用本模块自建配方（context 必须是 `modules/` 层）：

```bash
docker build -t bioskills/platanus-allee:2.4.0 -f modules/platanus-allee/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/platanus-allee:2.4.0 assemble -t 8 -f /data/illumina.1.fastq /data/illumina.2.fastq
```

### 5. Apptainer / Singularity（本地构建）

官方无 depot 预构建 sif，使用本模块自建配方：

```bash
cd modules && apptainer build platanus-allee-2.4.0.sif platanus-allee/native/Apptainer.def
apptainer run -B $PWD:/data -H /data platanus-allee-2.4.0.sif \
    assemble -t 8 -f /data/illumina.1.fastq /data/illumina.2.fastq
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（三段链路）+ 自省；二分制未安装时跳过真实组装
```

## 容器与 Conda 链接

* **官方镜像**：无（bioconda 404 / quay.io/biocontainers/platanus-allee 401 / depot 404，2026-09 核实）→ 本地自建 `native/Dockerfile` + `native/Apptainer.def`

* **官方站点**：<http://platanus.bio.titech.ac.jp/platanus2>（预编译二进制 v2.2.2 / v2.0.2）

* **官方源码**：<https://github.com/rkajitani/Platanus-allee>（tag v2.4.0）

* Platanus：https://github.com/rkajitani/Platanus

## 版本

* Platanus-allee **2.4.0**（GitHub 源码 tag v2.4.0；`common.cpp` 内 `VERSION="2.4.0"`）

* 构建路线：本地自建容器（debian:bookworm-slim + build-essential + 官方源码 make）；官方无 conda/镜像

* 2026-09 核实：nf-core `modules/nf-core/platanus-allee` 404、snakemake-wrappers `bio/platanus` 404、homebrew-core / brewsci-bio 均无公式
