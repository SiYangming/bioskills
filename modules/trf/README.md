# trf 软件模块（串联重复序列查找）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# trf / native — 串联重复序列查找驱动

TRF（Tandem Repeats Finder，[Benson-Genomics-Lab/TRF](https://github.com/Benson-Genomics-Lab/TRF)，官网 <https://tandem.bu.edu/trf/trf.html>）是**串联重复序列（tandem repeats）查找的事实标准工具**：**无需预先给出重复单元**，直接在输入的 FASTA 中定位并展示串联重复（可查周期 1–2000 bp），输出重复汇总表（HTML）、逐条重复的数据文件（`*.dat`，无标签、便于脚本处理）以及可选的 **N 屏蔽序列**（`*.mask`）。它以 Smith-Waterman 风格的局部比对 + wraparound 动态规划打分（匹配权重 / 不匹配罚分 / INDEL 罚分 / 匹配概率 PM / INDEL 概率 PI / 最小得分 / 最大周期共 7 个数值参数）。

TRF 是 **RepeatMasker 内部集成**（`modules/repeatmasker` 的 trf 路径）与 **RepeatModeler 的关键依赖**（`modules/repeatmodeler`；两者均由 bioconda 包装入，见对应模块文档，本模块不重复其依赖说明）；同时它也常**独立使用**于基因组重复序列的快速扫描与教学演示（教学课件典型命令 `trf genome.fasta 2 7 7 80 10 50 500 -m -d -h`）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/trf / bioconda trf）提供：

## 能力

| 子命令 | 包装命令 | 作用 | 线程 |
| ---- | ---- | ---- | ---- |
| `scan` | `trf <File> <Match> <Mismatch> <Delta> <PM> <PI> <Minscore> <MaxPeriod> [-m] [-d] [-h]` | 在 FASTA 中查找串联重复：默认产出 HTML 汇总/比对，`-d` 追加 `*.dat`，`-m` 追加 `*.mask`（N 屏蔽序列） | 单线程（`--threads` 为运行期协议位，**不注入**命令行） |

> 💡 **`-h` 语义更正（重要）**：上游 TRF **默认即产出 HTML**；`-h`（本驱动的 `-h/--html`）实际含义是**关闭** HTML 输出，并**自动开启 `-d`**（上游 usage：`-h suppress html output (this automatically switches -d to ON)`）。教学命令 `... -m -d -h` 因此得到 `*.mask` + `*.dat`、不含 HTML。

## 用法

```bash
# CLI 直跑（教学典型链路；产物写到输入 FASTA 同目录）
python main.py scan genome.fasta                      # 上游推荐默认参数 2 7 7 80 10 50 500
python main.py scan genome.fasta -m -d                # 追加 .mask（N 屏蔽序列）+ .dat（数据文件），HTML 为默认产物
python main.py scan genome.fasta -m -d -h             # 教学命令：-h 关闭默认 HTML（并自动开启 -d）
python main.py scan genome.fasta --mismatch-weight 5 --max-period 2000 -m -d
python main.py scan genome.fasta --min-score 50 --extra-args "-f -ngs"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）；`--threads` 仅作接口协议位被接受，trf 为**单线程**程序、不注入命令行。

> 📄 **产物命名**：以「输入文件名 + 7 个参数值」为前缀写在输入文件同目录，单序列输入时形如
> `genome.fasta.2.7.7.80.10.50.500.dat`、`.mask`、`.1.html` / `.txt.html`；多条序列时另出 `.summary.html`，各序列产物名内嵌 `.s<n>.` 序号。

## 实战示例：基因组串联重复序列查找（教学典型链路）

TRF 教学典型命令为 `trf genome.fasta 2 7 7 80 10 50 500 -m -d -h`（匹配权重 2 / 不匹配罚分 7 / INDEL 罚分 7 / 匹配概率 80 / INDEL 概率 10 / 最小得分 50 / 最大周期 500，`-m` 输出 N 屏蔽序列、`-d` 输出数据文件、`-h` 关闭默认 HTML）；以下为原生 CLI 的典型用法，**等价能力由 `native/main.py` 的 `scan` 子命令提供**（见上「用法」）。

### 1. 单基因组串联重复扫描（教学典型命令）

```bash
mkdir -p trf_out
cd trf_out
# 上游默认参数即 2 7 7 80 10 50 500；-m 屏蔽序列、-d 数据文件、-h 关闭 HTML
trf ../genome.fasta 2 7 7 80 10 50 500 -m -d -h
# 产物：genome.fasta.2.7.7.80.10.50.500.dat（逐条重复注释）
#       genome.fasta.2.7.7.80.10.50.500.mask（重复位点替换为 N 的 FASTA）
# 参数说明：
# 2 = 匹配权重
# 7 = 不匹配权重
# 7 = INDEL 权重
# 80 = 匹配概率
# 10 = INDEL 概率
# 50 = 最小得分
# 500 = 最大重复单元长度
```

### 2. 多样本批量扫描（每样本一个工作目录）

```bash
for fa in genomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    mkdir -p trf_${name} && cd trf_${name}
    trf ../"$fa" 2 7 7 80 10 50 500 -m -d -h     # 产物名取输入文件名前缀，分目录避免互相覆盖
    cd ..
done
```

### 3. 需要保留 HTML 汇总/比对页（默认产出，勿加 -h）

```bash
# 不加 -h：除 .dat（如同时加 -d 外）外得到 HTML 重复汇总表与逐条比对页
trf genome.fasta 2 7 7 80 10 50 500 -m -d
# genome.fasta.2.7.7.80.10.50.500.1.html（汇总表）/ *.txt.html（比对页）；多序列时 *.summary.html
```

### 4. 与 RepeatModeler / RepeatMasker 教学链路的关系

TRF 是 RepeatModeler 建库阶段与 RepeatMasker 屏蔽阶段的内部依赖（随 `bioconda repeatmodeler` / `repeatmasker` 一并装入）。用这两个模块时**无需单独安装/调用 TRF**；本模块仅在需要**独立**做串联重复扫描时使用（两者安装文档见 `modules/repeatmodeler`、`modules/repeatmasker`）。

### 5. 参数说明

| 参数（本驱动） | trf 位置/选项 | 说明 |
| ---- | ---- | ---- |
| `genome_fasta` | `<File>`（位置） | 待分析序列 FASTA（可含多条序列） |
| `--match-weight` | `<Match>` | 匹配权重，上游推荐 **2** |
| `--mismatch-weight` | `<Mismatch>` | 不匹配罚分，上游推荐 **7**（常用 3/5/7，越大越严格） |
| `--indel-weight` | `<Delta>` | INDEL 罚分，上游推荐 **7** |
| `--match-prob` | `<PM>` | 匹配概率，支持 75/80，上游推荐 **80** |
| `--indel-prob` | `<PI>` | INDEL 概率，支持 10/20，上游推荐 **10** |
| `--min-score` | `<Minscore>` | 报告所需最小比对得分，上游推荐 **50** |
| `--max-period` | `<MaxPeriod>` | 报告的最大周期（程序可查 1–2000），默认 **500** |
| `-m` / `--mask` | `-m` | 生成 N 屏蔽后的序列文件（`*.mask`） |
| `-d` / `--data` | `-d` | 生成逐条重复的数据文件（`*.dat`） |
| `-h` / `--html` | `-h` | **关闭**默认 HTML 输出（并自动开启 `-d`）；别名 `--suppress-html` |
| `--extra-args` | 其它 `[options]` | 透传 `-f`（记录侧翼序列）/ `-r`（关闭冗余消除）/ `-l <n>` / `-ngs` 等，慎用 |
| `--threads` / `--tmpdir` | — | 运行期覆盖；`--threads` 为协议位不注入（trf 单线程），`--tmpdir` 注入 `TMPDIR` |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n trf-native -c conda-forge -c bioconda trf=4.10.0rc2
conda activate trf-native
trf 2>&1 | head -n 3     # 断言：无参数运行打印 "Please use: trf File Match Mismatch Delta PM PI Minscore MaxPeriod [options]"
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio trf 4.09.1，与 meta 登记 4.10.0rc2 略有差异（版本以 formula 为准；两者 CLI 兼容）
brew tap brewsci/bio     # 首次使用需要
brew install trf
trf 2>&1 | head -n 3     # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/trf:4.10.0rc2--h7b50bb2_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
# 教学命令示例（-m 屏蔽序列 / -d 数据文件 / -h 关闭 HTML）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/trf:4.10.0rc2--h7b50bb2_0 \
    trf /data/genome.fasta 2 7 7 80 10 50 500 -m -d -h
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull trf.sif docker://depot.galaxyproject.org/singularity/trf:4.10.0rc2--h7b50bb2_0
apptainer run -B $PWD:/data -H /data trf.sif trf /data/genome.fasta 2 7 7 80 10 50 500 -m -d -h
```

### 4. 二进制包安装（官方 release 预编译资产，或源码编译）

TRF 为 **C 源码程序**，上游 [Benson-Genomics-Lab/TRF releases](https://github.com/Benson-Genomics-Lab/TRF/releases) 提供**预编译可执行文件**（如 `trf4.10.0-rc.2.linux64.exe`；为兼容脚本，安装时同时建 `trf` 软链）。确需本机部署时拉到用户前缀（无需 root）：

```bash
# 从 releases 页面取对应平台资产（文件名按上游为 trf<version>.<os><arch>.exe），示例：
wget https://github.com/Benson-Genomics-Lab/TRF/releases/download/v4.10.0/trf4.10.0-rc.2.linux64.exe -P ~/software/trf-4.10.0rc2/
chmod +x ~/software/trf-4.10.0rc2/trf*.exe
ln -sf ~/software/trf-4.10.0rc2/trf*.exe ~/software/trf-4.10.0rc2/trf
echo 'export PATH=$PATH:~/software/trf-4.10.0rc2' >> ~/.bashrc && source ~/.bashrc
trf 2>&1 | head -n 3     # 断言
```

> 无预编译资产的平台/版本走源码编译（`mkdir build && cd build && ../configure && make`，见上游 README「Instructions for Compiling」），或**优先走上方 Conda / 官方容器**。

## 测试

```bash
cd modules/trf/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约（7 个位置参数顺序 + -m/-d/-h）必跑；
# PATH 含 trf 时追加真跑最小链路（合成小 genome.fa → scan -m -d → 断言 *.dat / *.mask / 默认 *.1.html，
#   并回归 -h 关闭 HTML；失败即报错）；无 trf 时 [SKIP]。
```

## 版本

* trf **4.10.0rc2**（bioconda::trf=4.10.0rc2，build 0，2025-06 发布；上游 4.10.0 的 release candidate）

* 上一稳定版 **4.09.1**（bioconda build 7）CLI 兼容，可作回落

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/trf / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方**无** trf 子模块（404）；snakemake-wrappers 官方**有** `bio/trf`（pin trf=4.10.0rc2）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，官方缺失说明）

官方 nf-core **无** `modules/nf-core/trf`（2026-09 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/trf` 返回 404，登记「官方无」）。Nextflow 场景暂无官方子模块可登记；需要时以 `trf_native` 为兜底（或参照本库其它模块自建本地 `nextflow/` 规则）。

### snakemake-wrappers（官方存在，扁平 wrapper）

官方 snakemake-wrappers **有** `bio/trf`（**扁平 wrapper**：`wrapper.py` + `environment.yaml` + `meta.yaml` + `test/`，无子目录；2026-09 在线核实，v9.17.1 tag 含该 wrapper；`environment.yaml` pin `trf =4.10.0rc2`）。params 契约：`match` / `mismatch` / `delta` / `pm` / `pi` / `minscore` / `maxperiod`（**7 个数值参数均必填**）+ `extra`（追加选项串）；`input` 为 fasta，`output` 为 **目录**（wrapper 会 chdir 到该目录，产物落在其中）。可直接粘贴的规则示例：

```python
rule trf:
    input:
        fasta="genome.fa",
    output:
        directory("trf_out"),
    params:
        match=2,
        mismatch=7,
        delta=7,
        pm=80,
        pi=10,
        minscore=50,
        maxperiod=500,
        extra="-m -d -h",     # -m 屏蔽序列 / -d 数据文件 / -h 关闭默认 HTML
    wrapper: "v9.17.1/bio/trf"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/trf`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现 | trf 版本 | 来源 |
| ---- | ---- | ---- |
| native（官方容器/conda） | **4.10.0rc2** | official biocontainer：quay.io/biocontainers/trf:4.10.0rc2--h7b50bb2\_0 / bioconda trf=4.10.0rc2 |
| nf-core master | 官方无 | modules/nf-core/trf 404（2026-09） |
| snakemake-wrappers | 4.10.0rc2 | bioconda trf=4.10.0rc2（bio/trf/environment.yaml，扁平 wrapper；v9.17.1 tag） |
| brew（brewsci/bio） | 4.09.1 | Formula/trf.rb（4.09.1；CLI 与 4.10.0rc2 兼容，版本以 formula 为准） |

> 4.10.0rc2 为上游**候选发布版**（bioconda 现行默认）；如追求稳定可回落 4.09.1（`trf=4.09.1`），两者命令与产物命名一致，可共存于不同环境。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# trf native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 trf-native.yml 后 mamba env create -f trf-native.yml；
# 在线推荐上方 mamba create 直装命令。
name: trf-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - trf=4.10.0rc2
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/trf>

* **Docker**：`docker pull quay.io/biocontainers/trf:4.10.0rc2--h7b50bb2_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/trf%3A4.10.0rc2--h7b50bb2_0>

* 安装方式（本地）：`mamba create -n trf-native -c conda-forge -c bioconda trf=4.10.0rc2`

* 上游 GitHub：<https://github.com/Benson-Genomics-Lab/TRF>（releases 含预编译资产）· 官网：<https://tandem.bu.edu/trf/trf.html>
