# gapfiller 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方「环境安装」，容器与 conda
> 环境信息见文末「容器与 Conda 链接」。
>
> GapFiller（Boetzer & Pirovano，BaseClear）是使用测序文库对 scaffold 水平基因组**补洞**
> （gap closing）的工具：Perl 单文件脚本 `GapFiller.pl` 读取文库表（`-l`：文库名/比对器/双端 reads/
> 插入长度/误差/方向），以 `-s` 指定 scaffold FASTA，借助 `bowtie`/`bwa` 比对后局部延伸填补 gap。
> 本模块 native 对齐教学文档所用的**三代修改版（lufuhao fork，v1.11）**。
>
> ⚠️ **重要：同名不同物**——官方渠道 bioconda/quay.io/biocontainers/depot.galaxyproject.org 的
> **同名 `gapfiller`** 实为 **C++ v2.1.2 系列**（bioconda recipe 源码 `gapfiller-2.1.2.tar.gz`，
> 测试命令 `GapFiller --help`，CLI 为 `GapFiller --seed1 … --seed-ins …`），与本模块的 Perl
> `GapFiller.pl`（`-l library.txt -s genome.fa -T N`）**不是同一工具**（2026-09 逐渠道核实）。
> 因此本文档目标 Perl v1.11 无官方镜像/conda 包 → native 提供自建 Dockerfile / Apptainer.def。
> 官方登记：**nf-core `modules/nf-core/gapfiller` 404、snakemake-wrappers `bio/gapfiller` 404**
> （2026-09 核实）→ 不建 nextflow/、snakemake/ 目录。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/gapfiller/` **不存在**（2026-09 抓取返回 404）。
* **snakemake-wrappers**：`bio/gapfiller` **不存在**（2026-09 抓取返回 404）。

***

## native 实现

# gapfiller / native — scaffold 补洞驱动（Perl GapFiller.pl v1.11）

GapFiller.pl（三代修改版）的本地自包含实现（`source_type: custom`、`type: native`）。上游为单文件
Perl 脚本，CLI 形如（`GapFiller.pl <version>` 自带 USAGE）：

```
GapFiller.pl -l <library.txt> -s <genome.fa> [-b standard_output] [-m 29] [-o 2] [-r 0.7]
             [-d 50] [-n 10] [-t 10] [-i 10] [-g 1] [-T 4]
```

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `fill` | `GapFiller.pl -l library.txt -s genome.fa -T N …` | 以文库表对 scaffold 补洞；`--threads` 自动注入 `-T` |

> ⚠️ **依赖与 $Bin 约定**：GapFiller.pl 按**自身目录**查找比对器——`$Bin/bowtie/bowtie`
> 与 `$Bin/bwa/bwa`（原版预编译包即捆绑 `bowtie/`、`bwa/` 子目录）。`native/install.sh` 会据 PATH
> 自动建软链接；Docker/Apptainer 同理。库文件所用的比对器由文库表第 2 列指定（`bowtie`/`bwa`/`bwasw`）。

## 用法

```bash
# CLI 直跑（教学文档形态：-l library.txt -s genome.fa -T 4）
python main.py fill -l library.txt -s genome.fa --threads 4
# 覆盖参数 + 自定义输出前缀
python main.py fill -l library.txt -s genome.fa -b GF_out -m 29 -o 2 -r 0.7 -d 50 -T 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 优先级：用户显式 >
`optimization.per_subcommand_threads.fill` > `default_cpus`。

## 实战示例：scaffold 补洞

> 教学场景（doc 04 基因组组装 §22 GapFiller）典型用法如下；**等价能力由 `native/main.py` 的
> `fill` 子命令提供**（reads 校正见 BLESS，组装见 ALLPATHS-LG，见各自模块）。

```bash
# 1) 准备输入：scaffold 基因组 + 校正后的双端/大片段 reads
ln -s ../ALLPATHS-LG/allpathslg.fasta genome.fa
ln -s ../BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ../BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ../BLESS/jumping.1.corrected.fastq  jumping.1.fastq
ln -s ../BLESS/jumping.2.corrected.fastq  jumping.2.fastq

# 2) 创建文库表（每行：文库名 比对器 reads1 reads2 插入长度 误差 方向）
#    Lib1: 双端 fragment 文库（177 bp，误差 0.43，FR 方向）
#    Lib2: mate-pair jumping 文库（3014 bp，误差 0.67，RF 方向）
cat > library.txt <<'EOF'
Lib1 bwa fragment.1.fastq fragment.2.fastq 177 0.43 FR
Lib2 bwa jumping.1.fastq  jumping.2.fastq  3014 0.67 RF
EOF

# 3) 运行 GapFiller 补洞（等价能力由 native/main.py 的 fill 子命令提供）
GapFiller.pl -l library.txt -s genome.fa -T 4
#   python main.py fill -l library.txt -s genome.fa --threads 4
```

### 参数说明

| 参数（main.py / GapFiller.pl） | 说明 | 默认 |
| --- | --- | --- |
| `-l` / `--library` | 文库表文件（必需） | — |
| `-s` / `--scaffold` | 待补洞的 scaffold FASTA（必需） | — |
| `-b` / `--base-name` | 输出目录/文件名前缀 | `standard_output` |
| `-m` / `--min-overlap` | 与 gap 边缘最小重叠碱基数 | 29 |
| `-o` / `--min-reads-per-base` | 调用一个碱基所需最小 reads 数 | 2 |
| `-r` / `--min-base-ratio` | 单碱基延伸 reads 百分比阈值 | 0.7 |
| `-d` / `--max-diff` | gapsize 与已填补碱基数的最大差异 | 50 |
| `-n` / `--min-tig-overlap` | 合并相邻序列所需最小 contig 重叠 | 10 |
| `-t` / `--trim` | 序列首尾裁剪的 reads 数 | 10 |
| `-i` / `--iterations` | 补洞迭代次数 | 10 |
| `-g` / `--bowtie-gaps` | bowtie 比对允许的最大 gap 数 | 1 |
| `-T` / `--threads` | 线程数（驱动自动注入） | 4 |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

本文档目标为 **Perl GapFiller.pl v1.11（三代修改版）**：官方渠道（bioconda/quay/depot）的同名
`gapfiller` 为 C++ v2.1.2 系列、CLI 不同（见顶部说明），故 Perl v1.11 走**预编译 tar / 源码**两条官方
（上游）路线，二者均保留。

### 1. 官方预编译二进制包（上游预编译 tar，首选）

教学文档给出的三代修改版预编译 tar `GapFiller_v1-11_linux-x86_64.tar.gz`（捆绑 `GapFiller.pl` +
`bowtie/` + `bwa/` 子目录）：

```bash
tar zxf ~/software/GapFiller_v1-11_linux-x86_64.tar.gz -C ~/software/
chmod 0755 ~/software/GapFiller_v1-11_linux-x86_64/GapFiller.pl
echo 'export PATH=$HOME/software/GapFiller_v1-11_linux-x86_64:$PATH' >> ~/.bashrc
source ~/.bashrc
GapFiller.pl        # 无参打印 USAGE（含版本 v1.11）
```

> ⚠️ 该预编译 tar 的**官方下载直链未核实**（SourceForge `gapfiller` 项目文件区仅列
> v1.0 / v1.1 / v1.1.1 / v2.0 / v2.1.1 / v2.1.2，未见 v1-11；教学文档仅给出本地文件
> `~/software/GapFiller_v1-11_linux-x86_64.tar.gz`）。请以上游仓库（下节）源码部署为准，或自行
> 获取该 tar 并在本地核对来源。

### 2. 官方源码（上游仓库，并列保留）

```bash
# 一键：取 GapFiller.pl -> ~/software/GapFiller_v1-11 -> 建 bowtie/bwa 软链接 -> 写 PATH
bash native/install.sh
GapFiller.pl        # 断言：无参输出 USAGE（脚本内 my $version = "v1.11"）

# 等价手工路线
git clone https://github.com/lufuhao/gapfiller.git ~/software/GapFiller_v1-11-src
install -m 0755 ~/software/GapFiller_v1-11-src/GapFiller.pl ~/software/GapFiller_v1-11/
# 依赖比对器：apt-get install -y --no-install-recommends bowtie bwa（或 mamba install -c bioconda bowtie bwa）
```

### 3. Conda / brew（备选；注意同名不同物）

```bash
# ⚠️ bioconda 的 gapfiller 为 C++ v2.1.2 系列，CLI 为 `GapFiller --seed1 … --seed-ins …`，
#    与本模块 Perl GapFiller.pl（-l/-s/-T）不同；如需 C++ v2 请直接按上游文档使用。
mamba create -n gapfiller-cpp -c conda-forge -c bioconda gapfiller=2.1.2
```

> homebrew 两源均无 gapfiller（homebrew-core `gapfiller.json` 404、brewsci/bio `Formula/gapfiller.rb`
> 404，2026-09 核实）→ 不提供 brew 块。

### 4. Docker（自建镜像；Perl v1.11 无官方镜像）

```bash
# 自建（context 必须是 modules/ 层以携带驱动代码）
docker build -t bioskills/gapfiller:1.11 -f modules/gapfiller/native/Dockerfile modules/
# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/gapfiller:1.11 \
    -l /data/library.txt -s /data/genome.fa -T 4
# 驱动 main.py（镜像内 base.py + 软件级 meta 已就位）：
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/gapfiller:1.11 \
    /opt/skill/main.py fill -l /data/library.txt -s /data/genome.fa --threads 4
```

### 5. Apptainer / Singularity

Perl v1.11 无 depot.galaxyproject.org 预构建 sif，本地构建：

```bash
# 构建（%files 源路径相对 apptainer build 时的 cwd=modules/）
cd modules && apptainer build gapfiller-1.11.sif gapfiller/native/Apptainer.def
apptainer run -B $PWD:/data -H /data gapfiller-1.11.sif -l library.txt -s genome.fa -T 4
```

## 测试

```bash
bash modules/gapfiller/native/test/run_test.sh   # 自省 + argv 构造断言恒跑；GapFiller.pl 已部署时做版本标记冒烟
```

## 容器与 Conda 链接

* **上游源码（Perl v1.11 三代修改版）**：<https://github.com/lufuhao/gapfiller>
* **SourceForge 项目页（C++ v2 系列）**：<https://sourceforge.net/projects/gapfiller/>
* **Bioconda**：<https://anaconda.org/channels/bioconda/packages/gapfiller/overview>
  （⚠️ 为 C++ v2.1.2 系列，非本文档 Perl GapFiller.pl）
* **Docker（自建）**：`docker build -t bioskills/gapfiller:1.11 -f modules/gapfiller/native/Dockerfile modules/`
* **Apptainer（自建）**：`cd modules && apptainer build gapfiller-1.11.sif gapfiller/native/Apptainer.def`
* **Homebrew**：两源均无（2026-09 核实）

## 版本

* GapFiller **Perl v1.11**（三代修改版，lufuhao fork；脚本内 `my $version = "v1.11"`）
* 官方渠道同名 `gapfiller` 为 **C++ v2.1.2** 系列（bioconda latest 2.1.2；quay tag
  `2.1.2--h7ff8a90_4`；depot sif 200），CLI 与本模块不同
* 构建路线：Perl v1.11 无官方镜像/conda → native 自建配方（debian:bookworm-slim + apt
  perl/bowtie/bwa + 上游 GapFiller.pl）
