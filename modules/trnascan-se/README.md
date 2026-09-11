# trnascan-se 软件模块（tRNA 基因预测）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# trnascan-se / native — tRNA 基因预测驱动

tRNAscan-SE（上游 [UCSC-LoweLab/tRNAscan-SE](https://github.com/UCSC-LoweLab/tRNAscan-SE)，官网 <http://lowelab.ucsc.edu/tRNAscan-SE/>）是**预测基因组中 tRNA 基因的事实标准工具**：v2.0 以 **Infernal covariance models**（SCFG 随机上下文无关文法）为主搜索引擎，**默认真核模型**，`-B/--bacterial` 切原核模型、`-A` 切古菌模型，输出标准表格、二级结构（.ss）与统计（.stats）文件。**covariance model 与 Infernal 依赖随 bioconda 包自带**（模型文件在 conda 包内，装好即用，无需另配数据库）——这一点与 RepeatMasker 需另配重复库不同。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/trnascan-se / bioconda trnascan-se）提供；1 个子命令包装 tRNAscan-SE 2.0 主程序：

## 能力

| 子命令  | 包装命令                                                                                 | 作用                                        | 线程 |
| ---- | ------------------------------------------------------------------------------------ | ----------------------------------------- | -- |
| `scan` | `tRNAscan-SE [-B] -o <out> [-f <ss>] [-m <stats>] <genome.fasta>` | 预测 tRNA 基因：真核（默认）/原核（-B），产出表格/二级结构/统计 | 不强加（无 `-pa`；见下） |

## 用法

```bash
# CLI 直跑（教学典型链路；先在项目目录准备好 genome.fasta）
python main.py scan genome.fasta -o tRNA.out -f tRNA.ss -m tRNA.stats            # 真核默认
python main.py scan genome.ecoli.fasta -o Ecoli_tRNA.out -f Ecoli_tRNA.ss \
    -m Ecoli_tRNA.stats --prokaryote                                              # 原核 -B
python main.py scan genome.fasta -o tRNA.out --extra-args "-j tRNA.gff3"         # v2.0.9+ 直接出 GFF3

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。**线程说明**：tRNAscan-SE 主程序**无 `-pa`/`-p` 类线程开关**（v1/v2 均无），2.0 的搜索并行依赖「按序列切分 + 并发跑多个实例」（GNU parallel），或 **v2.0.13+ 新增的 `--thread <n>`**（转发给 Infernal cmsearch；仅默认 Infernal 模式可用、不可与 `-e/-t/-C/-L` 共存，v2.0.12 及更早不支持）。因此驱动**不强加线程参数**：`--threads` 仅作为运行期协议位被接受、**不注入命令行**；确需多线程时经 `--extra-args "--thread N"` 显式透传（仅 v2.0.13+）。`--tmpdir` 真实生效：tRNAscan-SE 读取 `$TMPDIR` 环境变量放置中间文件，驱动自动注入。

> ⚠️ 主程序执行名为 **`tRNAscan-SE`**（注意大小写与连字符）；本仓库 canonical 目录名/实现 ID 用全小写 `trnascan-se` / `trnascan_se_native`，仅指代软件本身。

## 实战示例：基因组 tRNA 基因预测（真核 + 原核，教学典型链路）

tRNAscan-SE 2.0 教学典型命令为 `tRNAscan-SE -o tRNA.out -f tRNA.ss -m tRNA.stats genome.fasta`（真核默认）与 `tRNAscan-SE -B -o Ecoli_tRNA.out -f Ecoli_tRNA.ss -m Ecoli_tRNA.stats genome.ecoli.fasta`（原核）；以下为原生 CLI 的典型用法，**等价能力由 `native/main.py` 的 `scan` 子命令提供**（见上「用法」）。

### 1. 真核基因组 tRNA 预测（默认模型）

```bash
mkdir -p trnascan_out && cd trnascan_out
cp ../genome.fasta .

# 真核默认模型：-o 表格 / -f 二级结构 / -m 统计（教学惯用三个输出）
tRNAscan-SE -o tRNA.out -f tRNA.ss -m tRNA.stats genome.fasta
# 产物：tRNA.out（逐 tRNA：序列名/坐标/反密码子/得分/内含子）、tRNA.ss（cloverleaf 二级结构）、
#       tRNA.stats（tRNA 总数/假基因/内含子/各 isotype 统计）
head tRNA.out        # 查看预测表
```

> 等价：`python main.py scan genome.fasta -o tRNA.out -f tRNA.ss -m tRNA.stats`

### 2. 原核基因组 tRNA 预测（-B 细菌模型）

原核（大肠杆菌等）建议切 **细菌模型**（`-B/--bacterial`），比默认真核模型更准。正式分析请用真实 E. coli 基因组序列（如 NCBI **NC_000913.3**，可改名 `genome.ecoli.fasta`）：

```bash
cd trnascan_out
cp ../genome.ecoli.fasta .

# 原核 -B：输出名按惯例加 Ecoli_ 前缀
tRNAscan-SE -B -o Ecoli_tRNA.out -f Ecoli_tRNA.ss -m Ecoli_tRNA.stats genome.ecoli.fasta
head Ecoli_tRNA.out
```

> 等价：`python main.py scan genome.ecoli.fasta -o Ecoli_tRNA.out -f Ecoli_tRNA.ss -m Ecoli_tRNA.stats --prokaryote`
>
> 想先空跑一遍 `-B` 命令链路（不追求生物学意义）时，也可把合成测试数据 `native/test/` 的 `genome.fa` 临时改名传入（内含经典酵母 tRNA-Phe，跨域亦大概率被细菌模型检出）。

### 3. 转 GFF3（基因组浏览器/下游比对用）——两条路

* **内置直出（推荐，v2.0.9+）**：主程序已内置 `-j/--gff`，无需任何外部脚本：
  ```bash
  tRNAscan-SE -o tRNA.out -j tRNA.gff3 -m tRNA.stats genome.fasta   # 等价 main.py --extra-args "-j tRNA.gff3"
  ```
* **老教程配套脚本 `tRNAscanSE2GFF3.pl`**：它是**独立的 perl 脚本，不属于 tRNAscan-SE 发行本体**，本模块**不作为子命令**登记；若手头是 1.x 旧版 `*.out` 或旧式表格需转 GFF3，可自行从课程/历史工具链获取该脚本后单独运行：
  ```bash
  perl tRNAscanSE2GFF3.pl < tRNA.out > tRNA.gff3   # 示意：把旧式 out（stdin）转 GFF3（stdout）
  ```

### 4. 大规模基因组并行（按序列切分 + GNU parallel）

tRNAscan-SE 主程序无 `-pa`；**全基因组/大片段批量预测**时按序列切分后并发（每任务一份输入 + 独立输出前缀），比单进程快得多：

```bash
# 先把多染色体 FASTA 按序列拆成单序列文件（或用 faSplit/seqkit）
mkdir -p split_runs && cd split_runs
# 对每个序列文件并发跑真核扫描（GNU parallel；v2.0.13+ 也可再加 --extra-args "--thread N"）
ls ../genome.chr*.fa | parallel -j 4 'tRNAscan-SE -o {.}.out -f {.}.ss -m {.}.stats {}'
# 合并结果：cat *.out > genome.all.tRNA.out（表头去重后合并）
```

> 注意：v2.0.13+ 的 `--thread <n>` 让**单条大序列内部**的 Infernal 搜索也并行，可与按序列切分叠加；2.0.12 及更早仅能靠切分并发。

### 5. 参数说明

| 参数                        | 说明                                                         |
| ------------------------- | ---------------------------------------------------------- |
| `<genome.fasta>`          | 输入 FASTA（位置参数；可一次给多个文件，此时各文件按序扫描）                         |
| `-B` / `--bacterial`      | 原核（细菌）模型模式；默认真核模型（`-A` 古菌、`-O/-M` 细胞器/线粒体等经 `--extra-args` 透传） |
| `-o <file>`               | 表格输出文件（默认 stdout；教学惯用 `tRNA.out` / `Ecoli_tRNA.out`）            |
| `-f <file>`               | 二级结构输出（.ss，cloverleaf 结构；教学惯用 `tRNA.ss`）                     |
| `-m <file>`               | 统计输出（.stats；教学惯用 `tRNA.stats`）                                |
| `-j <file>`               | GFF3 输出（v2.0.9+ 内置；经 `--extra-args` 透传）                       |
| `--extra-args "..."`      | 其它透传：`-A`（古菌）、`-a x.fa`、`-b x.bed`、`--thread N`（v2.0.13+）等       |
| `--threads N`（协议位）        | 驱动接受但不注入（无 `-pa`；并行见「实战示例 §4」，v2.0.13+ 用 `--extra-args "--thread N"`） |

## 依赖模块（安装见对应模块文档）

| 依赖       | 作用                                       | 安装文档                                    |
| -------- | ---------------------------------------- | --------------------------------------- |
| Infernal | 协方差模型搜索（tRNAscan-SE 2.x 内部调用 `cmsearch`） | [modules/infernal](../infernal/README.md) |

> bioconda `trnascan-se` 包已声明 infernal 依赖并自动装入；如需单独安装/核查版本见上表。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 tRNAscan-SE、Infernal 与全部 covariance model）；main.py 驱动在宿主机跑。**tRNAscan-SE 的模型文件随 conda 包/官方镜像自带，装好即用，无需另配数据库**。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n trnascan-se-native -c conda-forge -c bioconda trnascan-se=2.0.13
conda activate trnascan-se-native
tRNAscan-SE -h 2>&1 | head -n 1      # 断言：打印 "tRNAscan-SE 2.0.13 (Jul 2026)"
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# 注意公式名为 trnascan（非 trnascan-se），desc "Search for tRNA genes in genomic sequence"，
# 即本软件（当前构建 v2.0.13，与 meta 登记 2.0.13 一致，以 formula 为准）
brew tap brewsci/bio     # 首次使用需要
brew install trnascan    # 依赖 brewsci/bio/infernal 自动装入
tRNAscan-SE -h 2>&1 | head -n 1      # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/trnascan-se:2.0.13--pl5321hab16a5f_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/trnascan-se:2.0.13--pl5321hab16a5f_0 \
    tRNAscan-SE -o /data/tRNA.out -f /data/tRNA.ss -m /data/tRNA.stats /data/genome.fasta
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull trnascan-se.sif docker://depot.galaxyproject.org/singularity/trnascan-se:2.0.13--pl5321hab16a5f_0
apptainer run -B $PWD:/data -H /data trnascan-se.sif tRNAscan-SE \
    -o /data/tRNA.out -f /data/tRNA.ss -m /data/tRNA.stats /data/genome.fasta
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

tRNAscan-SE 官方**只发源码归档**（GitHub release 无预编译二进制），且需自行先装好 **Infernal 1.1+**（cmsearch）——因此一般**优先 conda / 官方容器路线**（依赖与模型全部自动配好）；确需源码安装时：

**官网下载页**：<http://lowelab.ucsc.edu/tRNAscan-SE/>

**GitHub**：<https://github.com/UCSC-LoweLab/tRNAscan-SE>（release 源码 tag 归档，与 `software_versions` 对齐 v2.0.13）

```bash
# 0) 前置：Infernal 1.1+（cmsearch 在 PATH；conda: mamba install -c bioconda infernal）与 perl
# 1) 下载源码归档到用户目录（无需 root）
wget https://github.com/UCSC-LoweLab/tRNAscan-SE/archive/refs/tags/v2.0.13.tar.gz -P ~/software/
tar zxf ~/software/v2.0.13.tar.gz -C ~/software/          # -> ~/software/tRNAscan-SE-2.0.13/
cd ~/software/tRNAscan-SE-2.0.13
# 2) configure/make 安装（--prefix 用户前缀，禁 /opt/biosoft、/home/train）
./configure --prefix=$HOME/software/tRNAscan-SE-2.0.13 && make && make install
# 3) 写 PATH（tRNAscan-SE 需能同时找到自身 bin/ 与 tRNAscan-SE.conf 等数据文件）
echo 'export PATH=$PATH:~/software/tRNAscan-SE-2.0.13/bin' >> ~/.bashrc && source ~/.bashrc
tRNAscan-SE -h 2>&1 | head -n 1        # 断言
```

## 测试

```bash
bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约必跑；
# PATH 含 tRNAscan-SE 时追加真核默认模式真实检测（conda 包内自带模型，无需另配）；
# 真实运行失败仅 [WARN] 提示不阻断（见脚本头注）。
```

## 版本

* trnascan-se **2.0.13**（上游 v2.0.13 于 2026-07-05 发布；bioconda::trnascan-se=2.0.13，build 2.0.13-0，quay tag `2.0.13--pl5321hab16a5f_0`；2026-09 核实）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/trnascan-se / depot.galaxyproject.org；本地不再自建容器）

* 依赖：infernal>=1.1.4、perl>=5.32.1（bioconda 随装）；模型文件在包内

* nf-core 官方子模块当前 pin trnascan-se=**2.0.12**（低于 native 的 2.0.13，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/trnascanse/` **存在**（2026-09 在线核实，按在线目录登记；以官方在线目录为准）。⚠️ **官方目录名是 `trnascanse`（无连字符）**，与本仓库 canonical `trnascan-se` 有拼写差异，安装/引用时以 nf-core 侧为准：

| 子模块                          | environment.yml 关键 pin                | 作用（据 nf-core meta）                |
| ---------------------------- | ------------------------------------ | --------------------------------- |
| `trnascanse`（扁平单模块，无子模块拆分） | bioconda::trnascan-se=2.0.12          | fasta → tRNA 表格/GFF3（covariance model 预测） |

> ⚠️ 执行请用 `nf modules install nf-core trnascanse`（安装到项目自身 `modules/nf-core/`，不要直接引用本仓库示例），随后：
>
> ```nextflow
> include { TRNASCANSE } from '../modules/nf-core/trnascanse/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/trnascanse | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/trnascan-se`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/trnascan-se` 返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `trnascan_se_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | trnascan-se 版本 | 来源                                                                                       |
| ------------------ | -------------- | ---------------------------------------------------------------------------------------- |
| native（官方容器/conda）  | **2.0.13**      | official biocontainer：quay.io/biocontainers/trnascan-se:2.0.13--pl5321hab16a5f\_0 / bioconda trnascan-se=2.0.13 |
| nf-core master     | 2.0.12          | bioconda::trnascan-se=2.0.12（modules/nf-core/trnascanse/environment.yml，扁平单模块）             |
| snakemake-wrappers | 官方无 wrapper       | bio/trnascan-se 404（2026-09）                                                           |

> nf-core 子模块 pin 2.0.12 略低于 bioconda 现行 2.0.13（2.0.13 新增 GCC v15 兼容修复与 `--thread`）：两者可共存（不同环境），用 Nextflow 时以 nf-core 子模块 pin 为准、待 nf-core bump 后同步刷新；用 native（Agent/CLI）时以 2.0.13 为准。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# trnascan-se native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 trnascan-se-native.yml 后 mamba env create -f trnascan-se-native.yml；
# 在线推荐上方 mamba create 直装命令。trnascan-se=2.0.13 会把 infernal/perl 及模型文件一并装入。
name: trnascan-se-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - trnascan-se=2.0.13
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/trnascan-se>

* **Docker**：`docker pull quay.io/biocontainers/trnascan-se:2.0.13--pl5321hab16a5f_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/trnascan-se%3A2.0.13--pl5321hab16a5f_0>

* 安装方式（本地）：`mamba create -n trnascan-se-native -c conda-forge -c bioconda trnascan-se=2.0.13`

* 上游 GitHub：<https://github.com/UCSC-LoweLab/tRNAscan-SE>（release 源码归档 v2.0.13）· 官网：<http://lowelab.ucsc.edu/tRNAscan-SE/> / 帮助 <http://lowelab.ucsc.edu/tRNAscan-SE/help.html>
