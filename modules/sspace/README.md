# sspace 软件模块

> 汇总说明：本 README 合并各实现（native 等）的用法；安装方式见「环境安装」，容器与 conda 信息记录于「容器与 Conda 链接」。

***

## native 实现

# sspace / native — 自包含 scaffold 连接驱动

SSPACE STANDARD v3.0（Scaffolding Pre-Assemblies After Contig Extension，BaseClear，2011）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

SSPACE 是一个使用测序数据进行 scaffold 连接的工具，能够将 contigs 连接成更长的 scaffolds。

| 子命令        | 命令                                                                                                                  | 作用                                       |
| ---------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `scaffold` | `perl SSPACE_Standard_v3.0.pl -l <library> -s <contigs> -x <0\|1> -T <threads> -b <base> [-k <n>]`                      | contigs + 配对文库 → 更长的 scaffolds（主流程）      |
| `sam2tab`  | `perl sam_bam2tab.pl <in.sam> <postfix1> <postfix2> <out.tab>`                                                        | SAM/BAM（按 read name 排序）→ TAB 配对信息        |

参数取自官方脚本内建 usage（2026-09 从官方发行 tar 核实）：`-l` 文库文件 · `-s` contigs FASTA · `-x` 是否延伸（1/0）· `-T` 线程 · `-b` 输出前缀 · `-k` 最小连接数 · `-g` bowtie gap · `-z` 最小 contig 长度等。

## 用法

```bash
# CLI 直跑
python main.py scaffold -l library.txt -s genome.fasta -x 0 -T 4 -b SSPACE_OUT
python main.py sam2tab -i reads.sorted.sam -o fragment.tab

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（scaffold 注入 `-T`）与 `--tmpdir` 运行期覆盖。

## 实战示例：contigs → scaffolds（三种方式）

SSPACE 有三种使用方式：直接输入 fastq、先比对生成 TAB、去重后再用 TAB（推荐，效果最佳）。以下为文档示例；等价能力由 `native/main.py` 的 `scaffold` / `sam2tab` 子命令提供（见上「用法」）。

```bash
mkdir -p 04.genome_assembling/SSPACE
cd 04.genome_assembling/SSPACE

# 格式化 contigs（来自 SOAPdenovo 产出的 contig）
genome_seq_clear.pl --seq_prefix contig ../SOAPdenovo/out_K51/E_coli.contig > genome.fasta

# 建立数据符号链接
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.?.fastq .
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.?.fastq .
```

### 方式一：直接输入 fastq 文件（最简单）

```bash
echo "Lib1 bwa fragment.1.fastq fragment.2.fastq 177 0.43 FR
Lib2 bwa jumping.1.fastq jumping.2.fastq 3014 0.67 RF" > library.txt
SSPACE_Standard_v3.0.pl -l library.txt -s genome.fasta -x 0 -T 4 -b SSPACE_1
```

### 方式二：先比对生成 TAB 文件，再进行 SSPACE

```bash
bowtie2-build genome.fasta genome
bowtie2 -x genome -p 4 -1 fragment.1.fastq -2 fragment.2.fastq --score-min L,-0.3,-0.3 -S fragment.sam 2> fragment.bowtie2.log
bowtie2 -x genome -p 4 -1 jumping.1.fastq  -2 jumping.2.fastq  --score-min L,-0.3,-0.3 -S jumping.sam  2> jumping.bowtie2.log
# SAM -> TAB（本模块 sam2tab 子命令；官方 tar 内脚本为 tools/sam_bam2tab.pl）
perl sam_bam2tab.pl fragment.sam /1 /2 fragment.tab > fragment.unpaired_match.readsID.list 2> fragment.sspace_sam2tab.log
perl sam_bam2tab.pl jumping.sam  /1 /2 jumping.tab  > jumping.unpaired_match.readsID.list  2> jumping.sspace_sam2tab.log

printf 'LIB1\tTAB\tfragment.tab\t177\t0.43\tFR\nLIB2\tTAB\tjumping.tab\t3014\t0.67\tRF\n' > library2.txt
SSPACE_Standard_v3.0.pl -l library2.txt -s genome.fasta -x 0 -T 4 -b SSPACE_2
```

### 方式三：去重后的 TAB 文件（推荐，效果最佳）

```bash
perl -e 'while (<>) { chomp; @_ = split /\t/; @aa = ("$_[0]\t$_[1]\t$_[2]", $two = "$_[3]\t$_[4]\t$_[5]"); @aa = sort {$a cmp $b} @aa; $aa = join "\t", @aa; $hash{$aa} = 1; } foreach (keys %hash) { print "$_\n"; }' fragment.tab > fragment.rmDup.tab
perl -e 'while (<>) { chomp; @_ = split /\t/; @aa = ("$_[0]\t$_[1]\t$_[2]", $two = "$_[3]\t$_[4]\t$_[5]"); @aa = sort {$a cmp $b} @aa; $aa = join "\t", @aa; $hash{$aa} = 1; } foreach (keys %hash) { print "$_\n"; }' jumping.tab > jumping.rmDup.tab

printf 'LIB1\tTAB\tfragment.rmDup.tab\t177\t0.43\tFR\nLIB2\tTAB\tjumping.rmDup.tab\t3014\t0.67\tRF\n' > library3.txt

#   -l library3.txt: 配置文件   -s genome.fasta: 输入序列
#   -x 0: 不延伸序列           -T 4: 使用 4 个线程
#   -b SSPACE_OUT: 输出前缀
SSPACE_Standard_v3.0.pl -l library3.txt -s genome.fasta -x 0 -T 4 -b SSPACE_OUT
```

### 文库文件（`-l`）列格式

`LibName  Aligner  R1  R2  insert  error  orientation`（制表符或空格分隔）。`Aligner` ∈ {bowtie, bwa, bwasw, TAB}；`orientation` ∈ {FR, FF, RF, RR}。当 `Aligner=TAB` 时，第 3 列是 TAB 配对信息文件（本模块 `sam2tab` 的产物）。

## 环境安装（无官方渠道，自建容器配方）

> 渠道核实（2026-09）：**官方渠道全无** —— bioconda `sspace` 404（仅 `sspace_basic`=2.1.1，为另一工具 SSPACE-Basic，勿混用）；quay.io/biocontainers/sspace 无；depot.galaxyproject.org 无；nf-core / snakemake-wrappers / brew 两源均 404。故按仓库规范提供**自建兜底配方**（`native/Dockerfile` + `native/Apptainer.def`，debian:bookworm-slim + apt 最小化 + 清理四连），软件本体取自**官方发行 tar**（BaseClear 原下载 URL 已 404，取自社区归档并内嵌 sha256 校验）。

### 1. Docker（自建镜像）

```bash
# 构建（配方在模块 native/ 下）
docker build -t sspace:3.0 modules/sspace/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    sspace:3.0 -l library.txt -s genome.fasta -x 0 -T 4 -b SSPACE_OUT
# sam2tab 子命令（脚本在镜像 PATH）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data --entrypoint /usr/local/bin/sam_bam2tab.pl \
    sspace:3.0 reads.sorted.sam /1 /2 fragment.tab
```

### 2. Apptainer / Singularity（自建镜像）

```bash
apptainer build sspace.sif modules/sspace/native/Apptainer.def
apptainer run -B $PWD:/data -H /data sspace.sif \
    -l /data/library.txt -s /data/genome.fasta -x 0 -T 4 -b SSPACE_OUT
```

### 3. 宿主机安装（`native/install.sh`，仅 linux-x64）

无官方 conda 包，故 `--method conda` 会明确报错；`install.sh` 走 binary 路线，从官方发行 tar（社区归档）部署到用户前缀（免 root，禁 `/opt`）：

```bash
bash native/install.sh                      # auto → binary（仅 linux-x64）
bash native/install.sh --prefix ~/opt/sspace-3.0
# 运行依赖：perl + Debian 包 libperl4-corelibs-perl（提供 SSPACE require 的 getopts.pl）
sudo apt-get install -y --no-install-recommends perl libperl4-corelibs-perl
```

### 4. Conda / brew

* **conda**：无官方包（bioconda `sspace` 404；`sspace_basic`=2.1.1 为 SSPACE-Basic，非本工具）→ 不登记 conda 块。
* **brew**：homebrew-core（`formulae.brew.sh/api/formula/sspace.json`）与 brewsci/bio（`Formula/sspace.rb`）均 404（2026-09 核实）→ 无公式，不登记 brew 块。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省（不下载/不编译）；
                        # 已装 SSPACE 时附 sam2tab 真实冒烟
```

## 容器与 Conda 链接

* **官网（页面已 404）**：<https://www.baseclear.com/services/bioinformatics/basetools/sspace-standard>
* **官方发行 tar 社区归档**：<https://github.com/yexianingyue/SSPACE-STANDARD-3.0>
* **Docker / Apptainer**：无官方镜像 → 本模块自建（`native/Dockerfile` / `native/Apptainer.def`）
* **conda**：无官方包（bioconda `sspace` 404）
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：Boetzer M, Henkel CV, Jansen HJ, Butler D, Pirovano W. Scaffolding pre-assembled contigs using SSPACE. *Bioinformatics* 2011;27(4):578-9

## 版本

* SSPACE STANDARD **v3.0**（内部版本串 `[SSPACE_Standard_v3.0_linux]`；2011-08 BaseClear 发布）
* License：**GPL-2.0-or-later**（脚本头声明 GPL v2 or later；SSAKE 部分另署 Canada's Michael Smith Genome Science Centre）
* 渠道：无官方 conda / 镜像（2026-09 核实 bioconda `sspace` 404、quay 无、depot 无）；官方 BaseClear 下载 URL 404
* 捆绑组件：bowtie **0.12.5** 与 bwa（linux-x86_64 ELF，随官方发行 tar 分发）
* 构建路线：**自建** debian:bookworm-slim + `libperl4-corelibs-perl`（本地兜底；本地维护配方）
