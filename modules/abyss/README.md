# abyss 软件模块（ABySS — de Bruijn Graph 并行组装器）

> 说明：教学文档（docs/04.md）将 ABySS 标为【淘汰技术】并以其 **1.9.0** 为教学版本；本模块
> 据此登记 1.9.0，但 ABySS **上游仍在维护**（bioconda 最新 `2.3.10`、nf-core 有
> `abyss/abysspe`、homebrew-core 有 `abyss` 公式；GitHub <https://github.com/bcgsc/abyss>
> 2026-09 探测 **HTTP 200**），故**不标记 deprecated**。本模块为 8 个子命令提供**可执行**
> native 驱动（`native/main.py`）。

**ABySS（Assembly By Short Sequences，1.9.0）** 是基于 **de Bruijn Graph** 的并行化基因组
组装器：`abyss-pe` 按 k-mer 组装 paired-end / mate-pair 数据，配套 `abyss-map` /
`abyss-fixmate` / `DistanceEst` / `abyss-scaffold` / `PathConsensus` / `MergeContigs` /
`PathOverlap` 可做独立 scaffolding。

***

## native 实现（`source_type: custom` / `type: native`）

`native/main.py` 继承 `base.SkillBase`：按官方用法构造命令行并**真实执行**；二进制**惰性解析**
（`shutil.which`），未安装时给出清晰报错（指向 bioconda `abyss` / 官方 GitHub）。子命令：

| 子命令 | 实际执行命令 | 作用 |
| ---- | ---- | ---- |
| `assemble` | `abyss-pe [np=<N>] j=<J> k=<K> [name=<name>] [lib=<lib>] [<key=value>...]` | de Bruijn 组装（核心） |
| `map` | `abyss-map -j <J> [-l <L>] <reads1> [<reads2>] <ref.fa>` | 读段比对到 contigs |
| `fixmate` | `abyss-fixmate [-l <L>] -h <hist>` | 修正 mate 并输出 histogram |
| `distance-est` | `DistanceEst [--dot] -j <J> -k <K> [-l <L>] [-s <S>] [-n <N>] -o <out> <hist>` | 估计 mate 方向/距离 |
| `scaffold` | `abyss-scaffold -k <K> [-s <S>] [-n <N>] -g <graph> <assembly.fa> <dist.dot>` | 独立 scaffolding |
| `path-consensus` | `PathConsensus -k <K> [-p <P>] -s <scaffolds> -g <adj> -o <path> <contigs...>` | path 一致性拆分 |
| `merge-contigs` | `MergeContigs -k <K> -o <out> <contigs\|-> <adj> <path>` | 合并 contigs |
| `path-overlap` | `PathOverlap [--overlap] [--dot] -k <K> <adj> <path>` | 输出 path 重叠 dot |

### 用法（CLI + Schema 自省）

```bash
cd modules/abyss/native

# 1) assemble：abyss-pe key=value 组装（np= MPI 进程数，j= 并行任务数）
python main.py assemble --kmer 51 --name E_coli --lib "pe1 mp=mp1" --np 4 \
    --extra-args 'pe1="fragment.1.fastq fragment.2.fastq" mp1="jumping.1.fastq jumping.2.fastq"'

# 2) 独立 scaffolding 链路（逐子命令）
python main.py map --reads1 jumping.1.fastq --reads2 jumping.2.fastq \
    --ref E_coli-6.fa --kmer 51 --threads 4
python main.py fixmate --hist mp1-6.hist --kmer 51
python main.py distance-est --hist mp1-6.hist --out mp1-6.dist.dot --dot \
    --kmer 51 --length 51 --size 200 --num 3
python main.py scaffold --graph E_coli-6.path.dot --assembly E_coli-6.fa \
    --dist mp1-6.dist.dot --kmer 51 --size 200 --num 3

# 3) Agent / Schema 自省
python main.py --schema          # 打印 JSON Schema（Agent Function Calling 挂载）
python main.py --list-commands   # 列出 8 个子命令
```

每个子命令支持 `--threads`（`assemble` 透传 `j=`；`map` / `distance-est` 透传 `-j`；优先级
「显式 `--threads` > `per_subcommand_threads` > `default_cpus`」）与 `--tmpdir`
（经进程环境变量 `TMPDIR` 注入；ABySS 无自身 tmp 选项）。

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `k=/-k/-l` | k-mer 长度（文档示例 51） |
| `name=` | `abyss-pe` 输出前缀/库名（如 `E_coli`） |
| `lib=` | 库定义（如 `pe1 mp=mp1`） |
| `pe1= / mp1=` | 各库读段文件（`abyss-pe` 的 key=value，经 `--extra-args` 透传） |
| `np=` | MPI 进程数（并行组装，需 `mpd`） |
| `j=` / `-j` | 并行任务数/线程 |
| `-l` | 读段长度（`DistanceEst`） |
| `-s / -n` | 距离阈值 / 命中数阈值（文档示例 200 / 3） |
| `-p` | `PathConsensus` 置信度（文档示例 0.9） |
| `--dot / --overlap` | 输出 dot 图 / 重叠（`DistanceEst`、`PathOverlap`） |

***

## 实战示例（`abyss-pe` 典型组装链路）

```bash
# 1) abyss-pe 直接组装（PE + mate-pair 两库；核心一步到位）
abyss-pe k=51 name=E_coli lib='pe1 mp=mp1' \
    pe1="fragment.1.fastq fragment.2.fastq" mp1="jumping.1.fastq jumping.2.fastq"

# 2) 独立 scaffolding 链路（已有 contigs，再用 mate-pair 提升骨架）
abyss-map -j4 -l51 jumping.1.fastq jumping.2.fastq E_coli-6.fa \
  | abyss-fixmate -l51 -h mp1-6.hist \
  | sort -snk3 -k4 \
  | DistanceEst --dot -j4 -k51 -l51 -s200 -n3 -o mp1-6.dist.dot mp1-6.hist
abyss-scaffold -k51 -s200 -n3 -g E_coli-6.path.dot E_coli-6.fa mp1-6.dist.dot > E_coli-6.path
PathConsensus -k51 -p0.9 -s E_coli-7.fa -g E_coli-7.adj -o E_coli-7.path \
    E_coli-6.fa E_coli-6.fa E_coli-6.path
cat E_coli-6.fa E_coli-7.fa | MergeContigs -k51 -o E_coli-8.fa - E_coli-7.adj E_coli-7.path
PathOverlap --overlap --dot -k51 E_coli-7.adj E_coli-7.path > E_coli-8.dot
```

上表每条命令的**等价能力由 `native/main.py` 的对应子命令提供**：`abyss-pe` → `assemble`、
`abyss-map` → `map`、`abyss-fixmate` → `fixmate`、`DistanceEst` → `distance-est`、
`abyss-scaffold` → `scaffold`、`PathConsensus` → `path-consensus`、`MergeContigs` →
`merge-contigs`、`PathOverlap` → `path-overlap`。先按 CLI 理解官方用法，再以
`python main.py <子命令> …` 交给 Agent 调用（同参数、同 argv 语义）。

## 测试

```bash
bash test/run_test.sh
```

* **恒跑断言**：`generate_data.py` 造数（PE/MP reads + contigs）、`--list-commands`
  （断言 8 子命令）、`--schema`（JSON 合法）、8 子命令 argv 构造断言（monkeypatch 二进制路径）、
  8 子命令缺必填 + 未知子命令校验、线程优先级、`--tmpdir → TMPDIR` 注入、stub 二进制下
  `run()` **真实执行**链路、缺二进制时明确报错 `rc 1`。
* **可选真跑**：PATH 中存在 `abyss-pe`（或设置 `$ABYSS`）时做一次 `abyss-pe --help` 冒烟；
  未安装则打印 `[SKIP]` 与原因（**本机未装 ABySS 也能全绿**）。

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09 在线核实）：**上游仍在维护**（GitHub 200，bioconda 最新 2.3.10），官方渠道
> 齐全——bioconda `abyss`（1.9.0 历史版 + 最新 2.3.10）→ quay.io/biocontainers 与
> depot.galaxyproject.org 有自动构建镜像；homebrew-core 有 `abyss` 公式；nf-core 有官方子模块
> `abyss/abysspe`（pin `bioconda::abyss=2.3.10`）。本模块登记文档教学版本 **1.9.0**。
> ⚠️ 已核实：官方 GitHub release **仅提供源码归档**（如 `abyss-2.3.10.tar.gz`），**无预编译
> 二进制资产**，故不设「官方预编译二进制包」小节；官方镜像已覆盖
> bioconda → quay.io/biocontainers → depot.galaxyproject.org，故**本地不再维护
> Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda abyss（文档教学版 1.9.0；上游最新 2.3.10）
mamba create -n abyss-native -c conda-forge -c bioconda abyss=1.9.0
conda activate abyss-native
abyss-pe version   # 断言：命令可达
# 一键安装（双路线：conda / 官方源码编译）：bash native/install.sh

# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install abyss
abyss-pe version   # 断言（brew 当前 2.3.x，与 meta 登记 1.9.0 略有差异，以 formula 为准）
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/abyss:1.9.0--0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/abyss:1.9.0--0 \
    abyss-pe k=51 name=E_coli lib=pe1 pe1="fragment.1.fastq fragment.2.fastq"
# 上游最新：quay.io/biocontainers/abyss:2.3.10--hf316886_1
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09-11 核实存在，与 quay tag 互通），直接拉取：

```bash
apptainer pull abyss.sif docker://depot.galaxyproject.org/singularity/abyss:1.9.0--0
apptainer run -B $PWD:/data -H /data abyss.sif \
    abyss-pe k=51 name=E_coli lib=pe1 pe1="fragment.1.fastq fragment.2.fastq"
```

### 4. 官方源码编译（唯一官方资产路线，依赖 sparsehash + openmpi）

```bash
# 依赖：google-sparsehash、openmpi（MPI 并行 np= 需要；不装 MPI 则仅串行）
tar zxf abyss-1.9.0.tar.gz          # 官方源码归档
cd abyss-1.9.0
./configure --prefix=$HOME/software/abyss-1.9.0 --with-mpi=$HOME/software/openmpi
make -j 4 && make install
export PATH="$HOME/software/abyss-1.9.0/bin:$PATH"
```

### 5. nf-core 官方子模块（说明层，不在本仓库建目录）

nf-core 有官方模块 **`abyss/abysspe`**（submodules=`["abysspe"]`，pin
`bioconda::abyss=2.3.10`，容器 `abyss:2.3.10--hf316886_1`）。
执行请用 `nf-core modules install` 安装到项目自身目录，**不要直接引用本仓库示例**：

```bash
nf-core modules install abyss/abysspe
```

> snakemake-wrappers：无 `bio/abyss`（2026-09-11 核实 404）→ 不登记官方 wrapper；
> 需要时用 `native/`（`shell: abyss-pe …`）兜底。

## 版本差异

| 实现 / 渠道 | 版本 | 来源 |
| ---- | ---- | ---- |
| **本模块（native，教学登记版）** | **1.9.0** | 文档 docs/04.md 教学版本；bioconda `abyss=1.9.0`（linux-64） |
| 上游最新 | **2.3.10** | bioconda `abyss=2.3.10`、GitHub tag 2.3.10（2026-09 核实） |
| nf-core 官方子模块 | **2.3.10** | `modules/nf-core/abyss/abysspe/environment.yml`（`bioconda::abyss=2.3.10`） |
| snakemake-wrappers | — | `bio/abyss` 404（无官方 wrapper） |
| homebrew-core | 2.3.x | `brew install abyss`（与 meta 登记 1.9.0 略有差异，以 formula 为准） |

> `abyss-pe` 的 `k=` / `np=` / `j=` / `name=` / `lib=` key=value 用法在 1.9.0 与 2.3.x 一致；
> 跨版本迁移时请复核参数与依赖（1.9.0 源码编译需 sparsehash + openmpi，现代 conda 包开箱即用）。
> **事实说明**：教学文档以 ABySS 1.9.0 为教学版本并标注【淘汰技术】，但上游仍在维护（bioconda
> 2.3.10、nf-core abyss/abysspe、homebrew-core abyss），故本模块不标记 deprecated。实际项目
> （尤其现代短读/长读组装）多由下列工具承担：

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **SOAPdenovo2** | 短读 de Bruijn 组装（ABySS 同代主流） | <https://github.com/aquaskyline/SOAPdenovo2> |
| **SPAdes** | 多 k-mer de Bruijn 组装器（现代主力） | <https://github.com/ablab/spades>（bioconda `spades`） |
| **Canu** | 三代长读组装 | <https://github.com/marbl/canu>（bioconda `canu`） |

## 版本

* 文档教学版本 **1.9.0**（ABySS 1.9.0；上游最新 bioconda 2.3.10，2026-03 仍有镜像构建）
* bioconda：`abyss=1.9.0`（linux-64）… `abyss=2.3.10`；license **GPL-3.0-only**
  （2026-09-11 api.anaconda.org 核实）
* homebrew-core：`abyss` 公式存在（license GPL-3.0-only AND LGPL-2.1-or-later AND MIT
  AND BSD-3-Clause）
* 引用：Simpson JT, Wong K, Jackman SD, Schein JE, Jones SJM, Birol I. ABySS: a
  parallel assembler for short read sequence data. *Genome Research* 2009;19(6):1117-23.
* nf-core：有官方子模块 `abyss/abysspe`（pin bioconda::abyss=2.3.10）；
  snakemake-wrappers：无（`bio/abyss` 404）

## 历史留存

* 历史教程常见安装前缀为 **`/opt/biosoft/abyss-1.9.0`**、依赖前缀
  `/opt/sysoft/openmpi-1.8.6`（root 全局限定路径）；本 README 一律改写为**用户前缀**
  `~/software/*`（免 root）。
* 原始发布包名：`abyss-1.9.0.tar.gz`；MPI 并行组装历史用 `mpd`（`~/.mpd.conf` +
  `MPD_SECRETWORD`），现代 conda/brew 包开箱即用、无需手工 mpd。
* `abyss-scaffold` 前常需把 contigs 名规范化为纯数字（历史流程用 perl 一行处理）。

## 容器与 Conda 链接

* **官网 / GitHub**：<https://github.com/bcgsc/abyss>（200）
* **conda**：<https://anaconda.org/bioconda/abyss>（1.9.0 … 2.3.10）
* **Docker / Singularity**：`quay.io/biocontainers/abyss:1.9.0--0`（历史）/
  `abyss:2.3.10--hf316886_1`（最新）/ depot.galaxyproject.org 同名 sif

  ```bash
  # Docker：必须带 -u $(id -u):$(id -g)，避免产物归 root
  docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
      quay.io/biocontainers/abyss:1.9.0--0 abyss-pe version

  # Apptainer：depot 预构建 sif 直拉（无需本地从 quay docker 转换）
  apptainer pull abyss.sif docker://depot.galaxyproject.org/singularity/abyss:1.9.0--0
  ```

* **brew**：`brew install abyss`（homebrew-core，当前 2.3.x）
* **nf-core 模块**：`abyss/abysspe`（<https://github.com/nf-core/modules/tree/master/modules/nf-core/abyss/abysspe>）
