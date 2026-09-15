# trimal 软件模块

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与
> snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息
> 记录于文末。

***

## native 实现

# trimal / native — MSA 修剪驱动

trimAl（[官网](http://trimal.cgenomics.org/) ・ [inab/trimal](https://github.com/inab/trimal)）是**多序列
比对（MSA）自动修剪工具**，是 Gblocks 的现代替代品：支持自动化阈值选择（`-automated1`）、多种修剪策略
（`-gappyout` / `-strictplus` / `-gt` 等），从比对中去掉伪序列与难比对区域，输出更紧凑可靠的比对供系统发育
建树使用。同一发行包还提供 **readal**（比对格式转换）与 **statal**（比对统计）两个配套程序。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**
（quay.io/biocontainers/trimal / bioconda trimal）提供，登记 **1.4.1**。

## 功能

| 子命令       | 命令                                                                            | 作用                                   |
| --------- | ----------------------------------------------------------------------------- | ------------------------------------ |
| `trim`    | `trimal -in <aln> -out <out> [-automated1 \| -gt <x> \| -gappyout \| -strictplus]` | 自动修剪多序列比对（默认 `-automated1`）          |
| `readal`  | `readal -in <aln> -out <out> -<format>`                                       | 比对格式转换（fasta/phylip/clustal/nexus…） |
| `statal`  | `statal -in <aln> -out <report>`                                             | 输出比对统计报告                             |
| `version` | `trimal -h`                                                                   | 打印 trimAl 用法/版本                       |

> trimAl / readal / statal 是同一发行包的三个独立可执行文件。

## 用法

```bash
# CLI 直跑
python main.py trim sample.aln -o sample.trimmed.aln                          # 默认 -automated1
python main.py trim sample.aln -o sample.trimmed.aln -m gt --gt-threshold 0.8 # gap 阈值 0.8
python main.py readal sample.aln -o sample.phy --readal-format phylip         # 转 Phylip
python main.py statal sample.aln -o sample.stats.txt                          # 比对统计

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR`）。**trimAl 为单线程
工具**，`--threads` 仅作统一接口保留，**不注入命令行**。

## 实战示例：MSA 修剪

trimAl 与 Gblocks 并列为 MSA 修剪的两条主流路线（二者可二选一，或先用 trimAl 粗修剪）；**等价能力由
`native/main.py` 的 `trim` / `readal` / `statal` 子命令提供**（见上「用法」）。

### 1. 自动修剪（保留信息位点）

```bash
mkdir -p trimal_out && cd trimal_out

# -automated1：按比对特征自动选择 gappyout/strict 策略（推荐默认）
trimal -in ../sample.aln -out sample.trimmed.aln -automated1

# 或用 gap 阈值（去掉空位比例 > 0.8 的列）
trimal -in ../sample.aln -out sample.gt80.aln -gt 0.8

# 驱动等价写法：
python ../modules/trimal/native/main.py trim ../sample.aln -o sample.trimmed.aln
```

### 2. 批量修剪 + 格式转换（送 RAxML 前）

```bash
for i in `cat orthologGroups.txt`; do
    trimal -in orthologGroups_CDS/$i.fasta.align -out $i.trimmed.aln -automated1   # 修剪
    readal  -in $i.trimmed.aln -out $i.phy -phylip                                  # 转 Phylip
done
# 产物：<gene>.trimmed.aln（修剪后比对）/ <gene>.phy（RAxML 输入）
```

### 3. 参数说明

| 参数                | 说明                                                        |
| ----------------- | --------------------------------------------------------- |
| `-automated1`     | 自动选择修剪策略（推荐默认）                                            |
| `-gappyout`       | 按空位分布自动修剪（快速，适合高空位数据）                                     |
| `-strictplus`     | 严格 + 保守区块（更激进）                                            |
| `-gt <x>`         | 去掉空位比例大于阈值 `x`（0–1）的列                                     |
| `-in` / `-out`    | 输入 / 输出比对（`-out` 缺省写 stdout）                              |
| `readal -<fmt>`   | readal 输出格式（fasta/phylip/clustal/nexus/pir…）              |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。官方同时提供**预编译二进制包**与**源码归档**，两条官方路线均保留（预编译优先）。

### 1. 官方预编译二进制包（首选）

官方 GitHub release <https://github.com/inab/trimal/releases/tag/v1.4.1> 提供预编译 zip（含 trimal/readal/
statal）：

```bash
mkdir -p ~/software && cd ~/software
# Linux x86_64：
wget https://github.com/inab/trimal/releases/download/v1.4.1/trimAl_Linux_x86-64.zip
# macOS x86_64：
# wget https://github.com/inab/trimal/releases/download/v1.4.1/trimAl_MacOS_x86-64.zip
unzip -q trimAl_Linux_x86-64.zip

mkdir -p ~/software/trimal-1.4.1/bin
install -m 0755 trimAl_Linux_x86-64/{trimal,readal,statal} ~/software/trimal-1.4.1/bin/
echo 'export PATH=$PATH:~/software/trimal-1.4.1/bin' >> ~/.bashrc && source ~/.bashrc
trimal -h        # 断言（打印 trimAl 版本横幅）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `trimal`，
> 无 conda 时自动下载官方 release zip 到 `~/software/trimal-<ver>` 并写 PATH；版本默认 1.4.1，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档（Source code (tar.gz)）
wget https://github.com/inab/trimal/archive/refs/tags/v1.4.1.tar.gz -P ~/software/
tar zxf ~/software/v1.4.1.tar.gz
cd trimal-1.4.1/source/
make -j 4
mkdir -p ~/software/trimal-1.4.1/bin
cp trimal readal statal ~/software/trimal-1.4.1/bin/
echo 'export PATH=$PATH:~/software/trimal-1.4.1/bin' >> ~/.bashrc && source ~/.bashrc
trimal -h        # 断言
```

（14.md「四 → 安装trimAl」即此源码路线；上 §1 预编译包与之等价，二者官方均提供。）

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n trimal-native -c conda-forge -c bioconda trimal=1.4.1
conda activate trimal-native
trimal -h        # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# 注意：brew 当前 trimal=1.5.1，与 meta 登记 1.4.1 略有差异（版本以 formula 为准）
brew install trimal
trimal -h        # 断言
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/trimal:1.4.1--h4ac6f70_9
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/trimal:1.4.1--h4ac6f70_9 \
    trimal -in /data/sample.aln -out /data/sample.trimmed.aln -automated1
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull trimal.sif docker://depot.galaxyproject.org/singularity/trimal:1.4.1--h4ac6f70_9
apptainer run -B $PWD:/data -H /data trimal.sif trimal -in /data/sample.aln -out /data/sample.trimmed.aln -automated1
```

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/trimal/` **存在**（单模块**扁平结构**：`environment.yml` + `main.nf` +
`meta.yml` + `tests/`；2026-09 在线核实，以官方在线目录为准），`environment.yml` pin
**bioconda::trimal=1.5.0**（高于 native 登记的 1.4.1）：

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core trimal`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），
> 随后 `include { TRIMAL } from '../modules/nf-core/trimal/main'`。

### snakemake-wrappers（官方无）

官方**无** `bio/trimal`（2026-09 核实 `tree/master/bio/trimal` 返回 **404**）→ 不建目录；Snakemake 场景请用
本模块 `native/` 兜底。

## 测试

```bash
cd modules/trimal/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ argv 构造断言必跑；
# PATH 含 trimal 时追加真实修剪（-gt 0.8）并断言产物；否则跳过（argv 验证已通过）。
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/trimal>（现行 latest 1.5.1；本模块登记 1.4.1）

* **Docker**：`docker pull quay.io/biocontainers/trimal:1.4.1--h4ac6f70_9`（bioconda 自动构建；tag 以 quay /
  depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/trimal%3A1.4.1--h4ac6f70_9>

* 安装方式（本地）：`mamba create -n trimal -c conda-forge -c bioconda trimal=1.4.1`（或 `brew install trimal`
  当前 1.5.1；或官方预编译 zip / 官方源码编译）

* 上游：<http://trimal.cgenomics.org/>（官网）· <https://github.com/inab/trimal>（源码与 release）

## 版本

* trimal **1.4.1**（bioconda::trimal=1.4.1；官方容器 tag `1.4.1--h4ac6f70_9`；bioconda 现行 latest 为 1.5.1，
  本模块按 14.md 流程锁定 1.4.1）

* 许可：GPL-3.0-or-later（bioconda trimal 包元数据）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/trimal / depot.galaxyproject.org；本地不再自建容器）；
  官方另有预编译 zip 与源码归档（两条官方路线均保留）

* 官方层：nf-core 有 `modules/nf-core/trimal`（扁平，pin 1.5.0）；snakemake-wrappers 无 wrapper（均 2026-09 核实）
