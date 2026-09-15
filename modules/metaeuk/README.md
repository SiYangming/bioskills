# metaeuk 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# metaeuk / native — 自包含真核基因预测驱动

MetaEuk 的本地自包含实现（`source_type: custom`、`type: native`；驱动 MetaEuk 2-ddf2742）。

## 功能

metaeuk 是一个用于真核生物基因预测的工具，BUSCO 使用它进行基因组模式的分析。

四个子命令对应 MetaEuk 的主要模块：

| 子命令            | 命令                                                                              | 作用                                        |
| -------------- | ------------------------------------------------------------------------------- | ----------------------------------------- |
| `easy_predict` | `metaeuk easy-predict <contigs> <targets> <out_prefix> <tmp_dir> --threads N`   | 端到端预测（= predictexons + reduceredundancy + unitesetstofasta），出蛋白 FASTA + GFF |
| `easy_search`  | `metaeuk easy-search <query> <target> <out_file> <tmp_dir> --threads N`         | MMseqs2 风格同源搜索                             |
| `taxtocontig`  | `metaeuk taxtocontig <contigsDB> <preds.fas> <headersMap> <taxDb> <out> <tmpDir> [--majority F]` | 对预测做分类注释并多数投票赋给 contig                   |
| `version`      | `metaeuk version`                                                               | 打印版本                                      |

## 用法

```bash
# CLI 直跑
python main.py easy_predict contigs.fna proteins.faa preds tmp --threads 8
python main.py easy_search query.faa target.faa hits.m8 tmp --threads 8
python main.py taxtocontig contigsDB preds.fas headersMap.tsv seqTaxDb.tsv taxResult tmp --majority 0.5
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 透传 `metaeuk --threads`；不传 `tmp_dir` 时取 `--tmpdir`）。

## 实战示例：从 contig 预测真核基因

MetaEuk 适用于真核（宏）基因组 contig 的规模化基因发现；BUSCO `-m genome`（真核）即以它作为基因预测后端。以下为典型用法，等价能力由 `native/main.py` 的 `easy_predict` / `easy_search` 子命令提供（见上「用法」）。

### 1. 端到端预测

```bash
# contigs 与参考蛋白均可为 FASTA 或已建库
metaeuk easy-predict contigs.fna reference_proteins.faa preds tmp --threads 8
# 产物：preds.fas（预测蛋白）、preds.codon.fas、preds.headersMap.tsv、preds.gff
```

### 2. 关键参数

| 参数                    | 说明                                                     |
| --------------------- | ------------------------------------------------------ |
| `--min-length`        | 候选蛋白片段的最少密码子数                                          |
| `-e`                  | 保留匹配的最大 E-value                                         |
| `--max-exon-sets`     | 每个 TCS 保留的次优外显子集数（找基因重复，≥6 版本）                           |
| `--overlap`           | `1` 允许同链重叠（默认不允许）                                      |
| `--len-scan-for-start` | 在首外显子上游扫描最多 N nt 寻找起始 ATG                              |
| `--threads`           | 并行线程数                                                  |

### 3. 与 BUSCO 的桥接

BUSCO `-m genome` 时会自动调用 MetaEuk（真核）做基因预测；本模块的 `easy_predict` 亦可独立用于大规模宏基因组注释。若仅需评估完整性，直接使用 `busco` 模块即可。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方同时提供 **prebuilt 平台二进制**（GitHub release assets）与 **源码编译**，另有官方容器/conda（bioconda → quay.io/biocontainers → depot.galaxyproject.org）；两条官方安装路线（预编译 / 源码）均保留，预编译为首选。

### 1. 官方预编译二进制包（首选）

官方当前 release `2-ddf2742` 提供 `metaeuk-linux-sse41.tar.gz`、`metaeuk-linux-avx2.tar.gz`、`metaeuk-osx-avx2.tar.gz`（无 osx-sse41）：

```bash
mkdir -p ~/software && cd ~/software
# Linux（按 CPU 指令集选择 sse41 / avx2）
wget https://github.com/soedinglab/metaeuk/releases/download/2-ddf2742/metaeuk-linux-sse41.tar.gz
tar zxf metaeuk-linux-sse41.tar.gz
export PATH="$HOME/software/metaeuk/bin:$PATH"
metaeuk version   # 断言
```

> macOS（x86_64）请改用 `metaeuk-osx-avx2.tar.gz`（Apple Silicon 需 Rosetta 运行）。
> 一键安装直接运行 `bash native/install.sh`（有 conda/mamba 走 bioconda，否则自动下载官方预编译二进制到 `~/software/metaeuk-2-ddf2742` 并写 PATH）。

### 2. 官方源码编译（并列保留）

```bash
git clone --recursive https://github.com/soedinglab/metaeuk.git
cd metaeuk
mkdir build && cd build
cmake -DHAVE_AVX2=1 -DCMAKE_INSTALL_PREFIX="$HOME/software/metaeuk" ..
make -j 8 && make install
export PATH="$HOME/software/metaeuk/bin:$PATH"
metaeuk version
```

> 源码编译需 CMake + C++ 编译器，并 `--recursive` 拉取 MMseqs2 子模块；AVX2 不可用时改用 `-DHAVE_SSE41=1`。

### 3. Conda / brew

```bash
# 按教学文档登记版本 2-ddf2742（亦可省略 =2-ddf2742 取当前最新）
mamba create -n metaeuk-native -c conda-forge -c bioconda metaeuk=2-ddf2742
conda activate metaeuk-native
metaeuk version   # 断言
```

```text
brew：无公式（homebrew-core 与 brewsci/bio 均未收录 metaeuk，2026-09 核实）→ 不提供 brew 块。
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/metaeuk:2.ddf2742--h2d02072_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/metaeuk:2.ddf2742--h2d02072_0 \
    easy-predict /data/contigs.fna /data/proteins.faa /data/preds /data/tmp --threads 8
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull metaeuk.sif docker://depot.galaxyproject.org/singularity/metaeuk:2.ddf2742--h2d02072_0
apptainer run -B $PWD:/data -H /data metaeuk.sif \
    easy-predict /data/contigs.fna /data/proteins.faa /data/preds /data/tmp --threads 8
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch 二进制解析，覆盖 4 个子命令）；metaeuk 已安装时额外冒烟 version
```

## 版本

* metaeuk 2-ddf2742（GitHub release tag `2-ddf2742`；bioconda `metaeuk=2-ddf2742`）
* 构建路线：官方预编译二进制（首选）+ 官方源码编译（并列）+ 官方容器/conda（quay.io/biocontainers/metaeuk / depot.galaxyproject.org；本地不再自建容器）
* nf-core `metaeuk/easypredict` 子模块 pin `metaeuk=6.a5d39d9`（最新大版本），与 native 登记的 2-ddf2742 差距较大，跨引擎迁移需注意

## 容器与 Conda 链接

* **GitHub**：https://github.com/soedinglab/metaeuk
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/metaeuk/overview>
* **Docker**：`docker pull quay.io/biocontainers/metaeuk:2.ddf2742--h2d02072_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/metaeuk%3A2.ddf2742--h2d02072_0>
* **官方预编译二进制**：<https://github.com/soedinglab/metaeuk/releases/tag/2-ddf2742>
* 安装方式（本地）：`mamba create -n metaeuk -c conda-forge -c bioconda metaeuk=2-ddf2742`
