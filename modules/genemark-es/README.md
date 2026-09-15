# genemark-es 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# genemark-es / native — 自包含从头/hints 基因预测驱动

GeneMark-ES/ET（`gmes_petap`）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

GeneMark-ES/ET 是一种基于隐马尔可夫模型的基因预测工具，其中 ES 版本用于从头预测，ET 版本结合 RNA-seq 证据。

三个子命令覆盖「ES 从头预测 / ET 结合 hints / hints 格式转换」：

| 子命令             | 命令（上游）                                                                  | 作用                                        |
| --------------- | ----------------------------------------------------------------------- | ----------------------------------------- |
| `es`            | `gmes_petap.pl --sequence <genome.fasta> --ES [--fungus] [--soft_mask 1] --cores N` | 无监督自训练从头预测                                |
| `et`            | `gmes_petap.pl --sequence <genome.fasta> --ET <introns.gff> [--fungus] [--et_score N] --cores N` | 结合 RNA-seq hints 预测                       |
| `convert_hints` | `hints2genemarkETintron.pl <genome.fasta> <hints.gff>`                   | AUGUSTUS 风格 hints GFF → GeneMark-ET 内含子（写 stdout） |

> ⚠️ **运行需许可密钥**：GeneMark 需 `~/.gm_key`（在官网申请 `gm_key_64.gz` 后 `gzip -dc gm_key_64.gz > ~/.gm_key`；
> 官方许可**禁止再分发**软件与密钥）。脚本按 `GENEMARK_PATH` / `~/software/gmes_linux_64*/` / `PATH` 惰性解析。

## 用法

```bash
# 前置：安装密钥
gzip -dc gm_key_64.gz > ~/.gm_key && chmod 600 ~/.gm_key

# CLI 直跑
python main.py es genome.fasta --fungus --threads 8
python main.py et genome.fasta --introns genemarkET.intron.gff --fungus --et-score 10 --threads 8
python main.py convert_hints genome.fasta hints.gff -o genemarkET.intron.gff

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`es`/`et` 注入 `--cores`）。

## 实战示例：ES 从头预测 → hints 转换 → ET 预测

GeneMark-ES 是唯一可无监督自训练的真核基因预测器；结合 RNA-seq hints 的 ET 模式精度更高。
以下为典型链路；等价能力由 `native/main.py` 的 `es` / `et` / `convert_hints` 子命令提供（见上「用法」）。

```bash
mkdir -p genemark_es_et/es genemark_es_et/et && cd genemark_es_et

# 1. ES 从头预测（真菌模式；--cores 并行）
cd es
gmes_petap.pl --sequence ../genome.fasta --ES --fungus --cores 8
#   产物 genemark.gtf；可转 GFF3：
#   /path/to/gtf_to_gff3_format.pl genemark.gtf ../genome.fasta > genemark.gff3

# 2. hints 转换（把 AUGUSTUS 风格 hints GFF 转为 GeneMark-ET 内含子格式）
cd ../et
hints2genemarkETintron.pl ../genome.fasta ../../augustus/making_hints/hints.gff > genemarkET.intron.gff

# 3. ET 预测（结合 hints）
gmes_petap.pl --sequence ../genome.fasta --ET genemarkET.intron.gff --fungus --et_score 10 --cores 8
```

参数说明：

| 参数                      | 说明                    |
| ----------------------- | --------------------- |
| `--sequence genome.fasta` | 基因组序列文件             |
| `--ES`                  | 启用从头预测模式            |
| `--ET introns.gff`      | 启用 ET 模式，使用 RNA-seq hints |
| `--fungus`              | 指定物种类型为真菌           |
| `--cores 8`             | 并行线程数               |
| `--et_score 10`         | ET 模式的得分阈值          |

> 桥接句：上表的等价能力由 `native/main.py` 的 `es` / `et` / `convert_hints` 子命令提供，先 CLI 直跑、再按需接入 Agent。

## 环境安装（官方预编译二进制包优先；官方无源码/容器，自建兜底配方）

> 官方渠道核实（2026-09-11）：**bioconda `genemark-es` 404**、**quay.io/biocontainers/genemark-es 未找到**、
> **depot.galaxyproject.org 无 `genemark*`** → 官方渠道全无镜像/conda 包；官方**仅提供许可受限的预编译包**（无源码），
> 且许可**禁止再分发**，故本模块提供自建兜底配方（`native/Dockerfile` + `native/Apptainer.def`）。

### 1. 官方预编译二进制包（首选；需同意许可）

```bash
# 在官网同意许可后下载 gmes_linux_64_4.tar.gz（GeneMark-ES/ET/EP ver 4.72_lic, LINUX 64）与 gm_key_64.gz
#   下载页：http://topaz.gatech.edu/GeneMark/license_download.cgi
tar zxf ~/software/gmes_linux_64_4.tar.gz -C ~/software/
gzip -dc ~/Downloads/gm_key_64.gz > ~/.gm_key && chmod 600 ~/.gm_key
echo 'export GENEMARK_PATH=~/software/gmes_linux_64_4' >> ~/.bashrc
echo 'export PATH=$PATH:~/software/gmes_linux_64_4' >> ~/.bashrc
source ~/.bashrc
gmes_petap.pl --help 2>&1 | head   # 断言（脚本存在）
```

> 一键安装：`bash native/install.sh --tarball ~/Downloads/gmes_linux_64_4.tar.gz`（解压到 `~/software/gmes_linux_64_4`，
> 写 `GENEMARK_PATH`/`PATH`；脚本会检查 `~/.gm_key` 并提示 Perl 依赖）。
>
> Perl 依赖：`YAML / Hash::Merge / Logger::Simple / Parallel::ForkManager`
> （Debian/Ubuntu：`sudo apt install libyaml-perl libhash-merge-perl liblogger-simple-perl libparallel-forkmanager-perl`，或 `sudo cpan -i YAML Hash::Merge Logger::Simple Parallel::ForkManager`）。

### 2. 官方源码编译

已核实：GeneMark-ES/ET 官方**不提供源码**（上游仅分发预编译 `gmes_linux_64` 包），故本模块无源码编译路线。

### 3. Conda（包管理器安装，非官方备选）

```bash
# ⚠️ bioconda 无 genemark-es（404，2026-09-11 核实）；下列为第三方频道（非官方维护，版本以频道为准）
mamba create -n genemark-es -c conda-forge -c bioconda -c HCC genemark-et
conda activate genemark-es
# 运行仍需 ~/.gm_key（官网申请）；GENEMARK_PATH 指向该环境的 gmes 目录
```

> ⚠️ 无 Homebrew 公式：已核实 homebrew-core（`formulae.brew.sh/api/formula/genemark-es.json` 404）与 brewsci/bio tap
> 两源均无，故不提供 `brew` 块。

### 4. Docker（自建兜底配方；官方无镜像）

```bash
# 构建前：把官方 gmes 包放到构建上下文（许可禁止再分发，故不随仓库分发）
cp ~/Downloads/gmes_linux_64_4.tar.gz modules/genemark-es/native/
docker build -t bioskills/genemark-es:4.72-v1.0 modules/genemark-es/native

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root；并挂载许可密钥
docker run --rm -u $(id -u):$(id -g) \
    -v ~/.gm_key:/opt/gmkey -v $PWD:/data -w /data -e HOME=/tmp \
    bioskills/genemark-es:4.72-v1.0 \
    es /data/genome.fasta --fungus --threads 8
```

### 5. Apptainer / Singularity（自建兜底配方；无 depot 官方 sif 可直拉）

> 说明：depot.galaxyproject.org **无** `genemark-es` 预构建 sif（2026-09-11 核实），故不能直拉，改用本地自建：

```bash
# 构建前：把官方 gmes 包放到本目录（默认名 gmes_linux_64_4.tar.gz）
apptainer build genemark-es.sif modules/genemark-es/native/Apptainer.def
apptainer run -B $PWD:/data -B ~/.gm_key:/opt/gmkey -H /data genemark-es.sif \
    es /data/genome.fasta --fungus --threads 8
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证；GENEMARK_PATH/gmes_petap.pl 就绪时额外做入口冒烟
```

## 容器与 Conda 链接

* **官网**：https://exon.gatech.edu/

* **下载**：https://exon.gatech.edu/GeneMark/gmes_instructions.html
* **Bioconda 页面**：官方无（<https://anaconda.org/bioconda/genemark-es> → 404，2026-09-11 核实）

* **Docker（自建）**：`bioskills/genemark-es:4.72-v1.0`（由 `native/Dockerfile` 构建；需自备官方 gmes 包）

* **Apptainer（自建）**：`genemark-es.sif`（由 `native/Apptainer.def` 构建）；depot.galaxyproject.org 无官方 sif

* **官方预编译包 / 密钥**：<http://topaz.gatech.edu/GeneMark/license_download.cgi>（同意许可后下载；许可禁止再分发）

* 第三方频道（非官方）：`HCC::genemark-et`（4.72）、`thiesgehrmann::genemark_es`

## 版本

* GeneMark-ES/ET/EP 4.72_lic（官方 `gmes_linux_64_4.tar.gz`，LINUX 64；以下载包内版本为准）

* 构建路线：官方预编译包（需许可）+ **自建容器兜底**（native/Dockerfile、Apptainer.def，apt 最小化；无官方 bioconda/quay/depot）

* 运行前提：`~/.gm_key`（官网申请；官方许可禁止再分发）

* nf-core / snakemake-wrappers：官方无模块 / 无 wrapper（2026-09-11 抓取 404；nf-core 仅 braker3 覆盖整链）
