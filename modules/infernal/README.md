# infernal 软件模块（Rfam/ncRNA 同源搜索）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# infernal / native — cmsearch + cmpress 驱动

Infernal（[EddyRivasLab/infernal](https://github.com/EddyRivasLab/infernal)，INFERence of RNA ALignment）是**基于协方差模型（CM）搜索 RNA 序列/结构同源**的工具：CM 是「profile + RNA 二级结构一致性」的随机上下文无关文法（profile-SCFG），比纯序列 profile 更能识别**结构保守而序列趋异**的 RNA 家族（rRNA/tRNA/其它 ncRNA）。它是 **Rfam 数据库的官方搜索工具**；生物信息教学课件中常用它做「用 Rfam 的 CM 库给基因组做 ncRNA 注释/质检」（`barrnap` 等工具内部也依赖 infernal 的 CM 搜索）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/infernal / bioconda infernal）提供：

## 能力

| 子命令      | 包装命令                                                                              | 作用                                        | 线程            |
| -------- | --------------------------------------------------------------------------------- | ----------------------------------------- | ------------- |
| `cmpress` | `cmpress <Rfam.cm>`（`-f` 经 `--extra-args` 强制重建）                                        | 压缩/索引 CM 数据库 → 同目录 `.cm.i1f/.i1m/.i1p/.i1i` 索引族 | ⚙ 快跑（单线程，不注入 --cpu） |
| `cmsearch` | `cmsearch [--cut_ga] [--nohmmonly] [--rfam] [--noali] --cpu N [--tblout F] [-o F] <cm> <seqdb>` | 用 CM 集合搜索基因组/序列库 → 主输出 + `--tblout` 表格        | ✅ 默认 8（注入 `--cpu`） |

## 用法

```bash
# CLI 直跑（Rfam 教学流程；先压缩/索引 Rfam.cm，再用它搜索基因组）
python main.py cmpress Rfam.cm
python main.py cmpress Rfam.cm --extra-args "-f"     # 索引已存在时强制重建

python main.py cmsearch Rfam.cm genome.fasta --cut_ga --nohmmonly --rfam --noali \
    --threads 8 --tblout rfam_out.tab -o rfam_out.txt
python main.py cmsearch Rfam.cm genome.fasta --cut_ga --rfam --noali --threads 8 \
    > rfam_out.txt                                    # 主输出缺省 stdout（> 重定向）

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。

> 💡 **提示**：Infernal 工具族没有 `--version` 参数——版本号打印在 `cmsearch -h` / `cmpress -h` 帮助头首行（如 `# cmsearch 1.1.5`）。

## 实战示例：用 Rfam CM 库对基因组做 ncRNA 同源搜索（cmsearch 教学流程）

以下为生物信息教学课件中 Infernal 的**典型用法**（先下载/已有 Rfam.cm → cmpress 索引 → cmsearch 搜索 → tblout 统计）；**等价能力由 `native/main.py` 的 `cmpress` / `cmsearch` 子命令提供**（见上「用法」）。

### 1. 下载并压缩/索引 Rfam CM 数据库（cmpress）

Rfam 的协方差模型库（`Rfam.cm`）由 Rfam 官方维护（官网 <https://rfam.org/>；下载页 <https://ftp.ebi.ac.uk/pub/databases/Rfam/CURRENT/>）需先经 `cmpress` 压缩并索引，生成四个二进制索引文件，供 cmsearch 高效读取：

```bash
# 1) 下载 Rfam 协方差模型库（gz 压缩包，解压到用户目录）
wget ftp://ftp.ebi.ac.uk/pub/databases/Rfam/CURRENT/Rfam.cm.gz -P ~/software/
gzip -dc ~/software/Rfam.cm.gz > ~/software/Rfam.cm

# 2) 压缩/索引（生成 .i1f/.i1m/.i1p/.i1i 索引族）
cmpress ~/software/Rfam.cm
# 生成：Rfam.cm.i1f / Rfam.cm.i1m / Rfam.cm.i1p / Rfam.cm.i1i（与 Rfam.cm 同目录）
```

> 已存在索引族时重跑会提示需 `-f` 强制覆盖；`cmpress` 本身很快（单线程即可）。

### 2. 用 CM 库搜索基因组（cmsearch）

```bash
# 教学典型参数：--cut_ga 用 GA 收集阈值（Rfam 官方推荐、无需先 cmcalibrate 的 E-value）
# --nohmmonly 关闭 HMM-only 快速模式（完整 CM 流程更准）、--rfam 用 Rfam 专属选项、
# --noali 不打印比对（省空间）、--cpu 8 并行、--tblout 输出易解析表格、主输出 > 到文件
cmsearch --cut_ga --nohmmonly --rfam --noali --cpu 8 \
         --tblout rfam_out.tab Rfam.cm genome.fasta > rfam_out.txt
```

### 3. 查看结果与批量统计（tblout 表格）

```bash
# 主输出 rfam_out.txt 是人工可读的命中报告（含每个命中的 CM 家族/得分/坐标/比对）；
# rfam_out.tab 每命中一行（# 开头为注释），适合 awk/脚本统计：
head -n 20 rfam_out.tab
awk '!/^#/{print $1}' rfam_out.tab | sort | uniq -c | sort -rn   # 按 RNA 家族统计命中数
```

> 💡 课件自带的 `Rfam_rRNA_stats.pl` 等结果统计脚本为**课件自制 Perl 脚本**（不属于 Infernal 官方模块），本模块不实现；需要时按课件路径自行获取（其输入即上面 `--tblout` 的 `rfam_out.tab` 或 `-o` 的主输出文本）。

### 4. 参数说明

| 参数             | 说明                                                            |
| -------------- | ------------------------------------------------------------- |
| `Rfam.cm`      | CM 数据库（cmpress 后同目录生成 `.i1f/.i1m/.i1p/.i1i` 索引族）                |
| `genome.fasta` | 搜索目标序列库（基因组/转录组 FASTA 或 FASTQ，可 `.gz`）                          |
| `--cut_ga`     | 用模型 GA 收集阈值（gathering cutoff）作报告/包含阈值（Rfam 教学默认，免 E-value 校准）    |
| `--nohmmonly`  | 关闭 HMM-only 快速模式，强制完整 CM 流程（慢但更准）                              |
| `--rfam`       | Rfam 专属搜索选项（仅当用 Rfam.cm 库时使用）                                   |
| `--noali`      | 主输出中不显示比对（省空间/加快）                                               |
| `--cpu N`      | 并行线程数（驱动层 `--threads` 自动注入；cmsearch 默认 8）                        |
| `--tblout F`   | 表格输出（每命中一行、易解析；教学统计下游直接解析此文件）                                 |
| `-o F`         | 主输出写文件（缺省 stdout）                                               |
| `-E <x>`       | 报告阈值 E-value（与 `--cut_ga` 二选一风格；用阈值打分需模型已 cmcalibrate）            |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n infernal-native -c conda-forge -c bioconda infernal=1.1.5
conda activate infernal-native
cmsearch -h | head -n 1   # 断言（打印 # cmsearch 1.1.5 ...）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio infernal 1.1.5，与 meta 登记一致
brew tap brewsci/bio     # 首次使用需要
brew install infernal
cmsearch -h | head -n 1  # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/infernal:1.1.5--pl5321h7b50bb2_4
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/infernal:1.1.5--pl5321h7b50bb2_4 \
    cmsearch --cut_ga --rfam --noali --cpu 8 --tblout /data/rfam_out.tab \
        /data/Rfam.cm /data/genome.fasta -o /data/rfam_out.txt
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull infernal.sif docker://depot.galaxyproject.org/singularity/infernal:1.1.5--pl5321h7b50bb2_4
apptainer run -B $PWD:/data -H /data infernal.sif cmsearch --cut_ga --rfam --noali \
    --cpu 8 --tblout /data/rfam_out.tab /data/Rfam.cm /data/genome.fasta -o /data/rfam_out.txt
```

### 4. 二进制包安装（官方 release 源码编译，无预编译资产）

Infernal 官方（eddylab.org）**只分发源码归档**（`infernal-1.1.5.tar.gz`，无预编译二进制资产），Linux/macOS 需本机编译（需 gcc/make，POSIX threads 默认开启）：

```bash
# 官网下载页：http://eddylab.org/infernal/ （或 GitHub release tag）
wget http://eddylab.org/infernal/infernal-1.1.5.tar.gz -P ~/software/
tar zxf ~/software/infernal-1.1.5.tar.gz -C ~/software/    # -> ~/software/infernal-1.1.5/
cd ~/software/infernal-1.1.5
./configure --prefix=$HOME/software/infernal-1.1.5
make -j4 && make install                                   # 可执行文件装入 --prefix/bin

# 写 PATH 后验证
export PATH=$PATH:~/software/infernal-1.1.5/bin
cmsearch -h | head -n 1
```

> 💡 教学/常规使用推荐优先走上方 **Conda 或官方容器**（免编译）；源码编译仅作无 conda/docker 环境的备选。

## 测试

```bash
cd modules/infernal/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/子命令 --help 契约）必跑；
# PATH 含 cmsearch/cmpress 时追加二进制 -h 自检；设 RFAM_CM=<真实 Rfam.cm 路径> 时追加
#   cmpress→cmsearch 真跑最小链路（断言 .i1f/.i1i 与 rfam_out.tab 非空；真跑失败仅 [WARN] 不阻断）；
# 无二进制 / 无 RFAM_CM 时 [SKIP]。
```

## 版本

* infernal **1.1.5**（bioconda::infernal=1.1.5，perl 5.32 build `pl5321h7b50bb2_4`；官方容器 tag `1.1.5--pl5321h7b50bb2_4`，2026-09 在线核实，以 quay / depot.galaxyproject.org 页面为准）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/infernal / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方模块当前 pin infernal=**1.1.5**（与 native 一致，见下「官方实现登记」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/infernal/` **存在**——目前仅 **`cmsearch`** 一个子模块（`cmsearch/` 下含 `environment.yml` + `main.nf` + `meta.yml` + tests；2026-09 在线核实，以官方在线目录为准；environment.yml pin `bioconda::infernal=1.1.5`）：

| 子模块           | environment.yml 关键 pin | 作用（据 nf-core meta）                                |
| ------------- | ---------------------- | ------------------------------------------------ |
| `cmsearch`    | bioconda::infernal=1.1.5 | 输入 cm/模型 + fasta → cmsearch 主输出 + 可选 `--tblout` |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core infernal/cmsearch`（安装到项目自身 `modules/nf-core/`，
> 不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { CMSEARCH } from '../modules/nf-core/infernal/cmsearch/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/infernal | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方存在，cmpress + cmscan 两个子 wrapper）

官方 snakemake-wrappers **有** `bio/infernal`，含 **`cmpress`** 与 **`cmscan`** 两个子目录（**无 cmsearch wrapper**；`bio/infernal/{cmpress,cmscan}/` 各为 `wrapper.py` + `environment.yaml` + `meta.yaml` + `test/`；2026-09 在线核实，**v9.17.1** tag 含该 wrapper；environment.yaml pin `infernal=1.1.5`）。注意官方只覆盖 **cmscan 方向**（用序列搜 CM 库），Rfam 教学常用的 **cmsearch 方向（用 CM 搜序列库）在 Snakemake 场景请走本模块 `native/main.py` 或 nf-core cmsearch**。可直接粘贴的规则示例（cmscan 按官方 wrapper params 契约）：

```python
rule cmscan_rfam:
    input:
        fasta="genome.fasta",            # 查询序列
        profile="Rfam.cm.i1i",           # 已 cmpress 的 CM 库索引（先跑 cmpress wrapper）
    output:
        tblout="rfam_out.tab",
        # outfile="rfam_out.txt",        # 可选：主输出
    params:
        evalue_threshold=10,             # 报告 E-value <= x（默认 10）
        extra="",                        # 如 "--cut_ga --rfam"（cmscan 侧教学参数经此透传）
    threads: 8
    wrapper: "v9.17.1/bio/infernal/cmscan"
```

```python
rule cmpress_rfam:
    input:
        cm="Rfam.cm",
    output:
        idx="Rfam.cm.i1i",               # 触发 cmpress（官方 wrapper 自动生成 .i1f/.i1m/.i1p/.i1i）
    params:
        extra="",
    wrapper: "v9.17.1/bio/infernal/cmpress"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/infernal/cmscan`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | infernal 版本 | 来源                                                                                                        |
| ------------------ | ----------- | --------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.1.5**    | official biocontainer：quay.io/biocontainers/infernal:1.1.5--pl5321h7b50bb2\_4 / bioconda infernal=1.1.5            |
| nf-core master     | 1.1.5       | bioconda::infernal=1.1.5（modules/nf-core/infernal/cmsearch/environment.yml，单子模块）                                |
| snakemake-wrappers | 1.1.5       | bioconda infernal=1.1.5（bio/infernal/{cmpress,cmscan}/environment.yaml；v9.17.1 tag；无 cmsearch wrapper）          |

> 三方版本**一致**（均为 1.1.5），无 CLI 代际差异；差异只在「官方覆盖的子命令面」：nf-core 仅 `cmsearch`，snakemake-wrappers 仅 `cmpress`+`cmscan`，native 驱动覆盖 `cmpress`+`cmsearch`（教学 Rfam 流程所需的两个方向）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# infernal native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 infernal-native.yml 后 mamba env create -f infernal-native.yml；
# 在线推荐上方 mamba create 直装命令。infernal=1.1.5 会把 cmsearch/cmpress/cmscan 等一并装入。
name: infernal-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - infernal=1.1.5
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/infernal>

* **Docker**：`docker pull quay.io/biocontainers/infernal:1.1.5--pl5321h7b50bb2_4`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/infernal%3A1.1.5--pl5321h7b50bb2_4>

* 安装方式（本地）：`mamba create -n infernal-native -c conda-forge -c bioconda infernal=1.1.5`

* 上游 GitHub：<https://github.com/EddyRivasLab/infernal>（release 为源码 tag 归档，无预编译 assets；官网下载页 <http://eddylab.org/infernal/>）
