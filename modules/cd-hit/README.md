# cd-hit 软件模块（序列聚类去冗余）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# cd-hit / native — 序列聚类去冗余驱动

CD-HIT（Cluster Database at High Identity with Tolerance，[weizhongli/cdhit](https://github.com/weizhongli/cdhit)，官网 <https://sites.google.com/view/cd-hit/home>）是**高通量序列去冗余/聚类**的经典工具：以贪心增量聚类 + 短词过滤，按相似度阈值（`-c`，默认 0.9）把高度相似的序列聚为一簇，每簇保留一条**代表序列**并输出 `.clstr` 簇明细。常用于**蛋白家族去冗余**（`cd-hit`）、**转录组/EST/组装去冗余**（`cd-hit-est`）与宏基因组 OTU 聚类，也是 **RepeatModeler**（见本仓库 `modules/repeatmodeler`）等教学流程的依赖工具。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/cd-hit / bioconda cd-hit）提供；两个子命令分别包装官方两个入口：

## 能力

| 子命令       | 包装命令                                             | 作用                                | 线程               |
| --------- | ------------------------------------------------ | --------------------------------- | ---------------- |
| `protein` | `cd-hit -i in.fa -o out.fa -c 0.9 -T N [-M mb]`      | 蛋白序列按相似度阈值聚类去冗余 → 代表序列 + `out.fa.clstr` | ✅ 默认 4（注入 `-T`） |
| `est`     | `cd-hit-est -i in.fa -o out.fa -c 0.9 -T N [-M mb]`  | 核酸（EST/转录组）序列聚类去冗余 → 代表序列 + `out.fa.clstr` | ✅ 默认 4（注入 `-T`） |

## 用法

```bash
# CLI 直跑（教学典型链路）
python main.py protein -i proteins.fa -o proteins_nr.fa -c 0.9 --threads 8          # 蛋白去冗余（90% identity）
python main.py est     -i transcripts.fa -o transcripts_nr.fa -c 0.95 --threads 8   # 转录组去冗余（95% identity）
python main.py est     -i reads.fa -o reads_nr.fa -c 0.9 --threads 8 -M 4000       # 限制内存上限 4 GB

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。产物：`<output>`（代表序列 FASTA）与 `<output>.clstr`（簇明细）。

> 💡 **去冗余程度看阈值**：`-c` 越接近 1 越严格（保留越多代表序列），越低越激进（压缩越狠）。核酸高相似数据集（如去 PCR 重复、同一物种转录本）常用 0.95–1.0；跨物种/家族聚类常用 0.9 或更低。

## 实战示例：蛋白集 / 转录组去冗余（RepeatModeler 依赖语境）

CD-HIT 是重复序列注释流程 RepeatModeler 等工具的默认依赖（其内部用 `cd-hit` 对重复家族做去冗余），也是转录组/组装去冗余的通用首选；以下为原生 CLI 的典型批量用法，**等价能力由 `native/main.py` 的 `protein` / `est` 子命令提供**（见上「用法」）。

### 1. 蛋白序列去冗余（cd-hit，-c 0.9）

```bash
mkdir -p cdhit_out
cd cdhit_out

# 单文件：90% identity 聚类，代表序列写 proteins_nr.fa、簇明细写 proteins_nr.fa.clstr
cd-hit -i ../proteins.fa -o proteins_nr.fa -c 0.9 -T 8 -M 0

# 多样本批量（每个样本一份代表序列 + .clstr）
for fa in ../proteomes/*.faa; do
    name=$(basename "$fa" .faa)
    cd-hit -i "$fa" -o ${name}_nr.fa -c 0.9 -T 8 -M 0
done
```

### 2. 核酸/转录组去冗余（cd-hit-est，-c 0.95）

```bash
# 转录组/EST 去冗余：核酸用 cd-hit-est（蛋白用 cd-hit），阈值通常更严
cd-hit-est -i ../transcripts.fa -o transcripts_nr.fa -c 0.95 -T 8 -M 0

# 批量（每样本一份）
for fa in ../transcriptomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    cd-hit-est -i "$fa" -o ${name}_nr.fa -c 0.95 -T 8 -M 0
done
```

### 3. 统计去冗余效果（输入 vs 代表序列）

```bash
echo "输入:     $(grep -c '^>' ../transcripts.fa)"
echo "去冗余后: $(grep -c '^>' transcripts_nr.fa)"
echo "簇数:     $(grep -c '^>Cluster' transcripts_nr.fa.clstr)"
```

### 4. 参数说明

| 参数            | 说明                                                        |
| ------------- | --------------------------------------------------------- |
| `-i <file>`   | 输入 FASTA（protein 为蛋白、est 为核酸；4.8.1 支持 `.gz` 输入）            |
| `-o <file>`   | 输出代表序列 FASTA（同时生成 `<file>.clstr` 簇明细）                      |
| `-c <float>`  | 相似度阈值（0.0–1.0，默认 0.9；本驱动由 `--identity` 注入，默认 0.9）          |
| `-T <int>`    | 线程数（本驱动由 `--threads` 注入，默认 4；cd-hit 原生默认 1）                |
| `-M <int>`    | 内存上限 MB（0 = 不限制；本驱动由 `--memory` 注入，缺省用 cd-hit 默认 800）      |
| `-n` / `-G` 等 | 词长/其它高级项经 `--extra-args` 透传（`-n` 默认随 `-c` 自动选择）          |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 `cd-hit` / `cd-hit-est` / `cd-hit-2d` / `cd-hit-est-2d` 等全部入口）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n cd-hit-native -c conda-forge -c bioconda cd-hit=4.8.1
conda activate cd-hit-native
cd-hit -h 2>&1 | head -n 1    # 断言：打印 "CD-HIT version 4.8.1 ..."
```

```bash
# 或用 Homebrew（macOS / Linux；homebrew-core 无此公式，公式在 brewsci/bio tap，需先添加 tap）
# brew 版本：brewsci/bio cd-hit V4.8.1，与 meta 登记 4.8.1 一致（版本以 formula 为准）
brew tap brewsci/bio     # 首次使用需要
brew install cd-hit
cd-hit -h 2>&1 | head -n 1   # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/cd-hit:4.8.1--h5ca1c30_13
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/cd-hit:4.8.1--h5ca1c30_13 \
    cd-hit-est -i /data/transcripts.fa -o /data/transcripts_nr.fa -c 0.95 -T 8 -M 0
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull cd-hit.sif docker://depot.galaxyproject.org/singularity/cd-hit:4.8.1--h5ca1c30_13
apptainer run -B $PWD:/data -H /data cd-hit.sif cd-hit-est \
    -i /data/transcripts.fa -o /data/transcripts_nr.fa -c 0.95 -T 8 -M 0
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

CD-HIT 官方 GitHub release（`V4.8.1`）**只提供源码归档**（asset `cd-hit-v4.8.1-2019-0228.tar.gz`，无 Linux/macOS 预编译二进制），需自行 `make`；**常规使用请优先上方 Conda 或官方容器**。源码路线（用户前缀、免 root）：

```bash
wget https://github.com/weizhongli/cdhit/releases/download/V4.8.1/cd-hit-v4.8.1-2019-0228.tar.gz -P ~/software/
tar zxf ~/software/cd-hit-v4.8.1-2019-0228.tar.gz -C ~/software/    # -> ~/software/cd-hit-4.8.1/
cd ~/software/cd-hit-4.8.1
make                                   # 编译生成 cd-hit / cd-hit-est 等二进制
echo 'export PATH=$PATH:~/software/cd-hit-4.8.1' >> ~/.bashrc && source ~/.bashrc
cd-hit -h 2>&1 | head -n 1             # 断言：打印 CD-HIT version 4.8.1
```

> （勿写 `/opt/biosoft`、`/home/train` 等教学硬编码路径；部署到 `~/software/<sw>-<ver>` 用户前缀。）

## 测试

```bash
cd modules/cd-hit/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与子命令参数契约
#   （protein/est 的 --input/--output/--identity/--memory/--threads/--tmpdir）必跑；
# PATH 含 cd-hit / cd-hit-est 时追加真跑最小链路（合成小 FASTA → 聚类 → 断言代表序列 + .clstr
#   且去冗余后条数减少；真跑失败仅 [WARN] 提示不阻断）；无二进制时 [SKIP]。
```

## 版本

* cd-hit **4.8.1**（bioconda::cd-hit=4.8.1，现行最新；linux-64 build `h5ca1c30_13`，2025-04 发布；4.8.1 为上游 `V4.8.1-2019-0228` 之后唯一维护版本）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/cd-hit:4.8.1--h5ca1c30_13 / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方子模块当前 pin cd-hit=**4.8.1**（与 native 一致，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方目录名为 **`cdhit`**（非 `cd-hit`），`modules/nf-core/cdhit/` **存在**（含 `cdhit` 与 `cdhitest` 两个子模块；2026-09 在线核实，以官方在线目录为准）：

| 子模块        | environment.yml 关键 pin  | 作用（据 nf-core meta）                              |
| ---------- | ----------------------- | --------------------------------------------- |
| `cdhit`    | bioconda::cd-hit=4.8.1   | 蛋白序列聚类：输入 fasta → 代表序列 fasta + `.clstr`        |
| `cdhitest` | bioconda::cd-hit=4.8.1   | 核酸序列聚类：输入 fasta/fastq → 代表序列 + `.clstr`        |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core cdhit cdhit cdhitest`（安装到项目自身 `modules/nf-core/`，
> 不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { CDHIT } from '../modules/nf-core/cdhit/cdhit/main'
> include { CDHITEST } from '../modules/nf-core/cdhit/cdhitest/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/cdhit | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/cdhit`、也无 `bio/cd-hit`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio`，`cd` 开头的目录为空；两个候选路径均返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `cd_hit_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | cd-hit 版本 | 来源                                                                                          |
| ------------------ | --------- | ------------------------------------------------------------------------------------------- |
| native（官方容器/conda）  | **4.8.1** | official biocontainer：quay.io/biocontainers/cd-hit:4.8.1--h5ca1c30\_13 / bioconda cd-hit=4.8.1 |
| nf-core master     | 4.8.1     | bioconda::cd-hit=4.8.1（modules/nf-core/cdhit/{cdhit,cdhitest}/environment.yml）                   |
| snakemake-wrappers | 官方无 wrapper | bio/cdhit 与 bio/cd-hit 均 404（2026-09）                                                        |

> 三方登记的 cd-hit 均为 4.8.1（4.8.1 后上游未再发新版），无代际 CLI 差异：native（Agent/CLI）与 nf-core（Nextflow）可用同一参数语义（`-c`/`-T`/`-M`）；Nextflow 侧仅壳层（process/容器）不同，可安心共存。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# cd-hit native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 cd-hit-native.yml 后 mamba env create -f cd-hit-native.yml；
# 在线推荐上方 mamba create 直装命令。cd-hit=4.8.1 会随包提供 cd-hit / cd-hit-est 等全部入口。
name: cd-hit-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - cd-hit=4.8.1
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/cd-hit>

* **Docker**：`docker pull quay.io/biocontainers/cd-hit:4.8.1--h5ca1c30_13`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/cd-hit%3A4.8.1--h5ca1c30_13>

* 安装方式（本地）：`mamba create -n cd-hit-native -c conda-forge -c bioconda cd-hit=4.8.1`

* 上游 GitHub：<https://github.com/weizhongli/cdhit>（release V4.8.1 仅源码归档）· 官网：<http://www.bioinformatics.org/cd-hit/>
