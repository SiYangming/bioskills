# fasta 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；容器与 conda 环境信息记录于文末「容器与 Conda 链接」。
> 官方 nf-core / snakemake-wrappers 均无 FASTA 实现（2026-09 抓取 `fasta` / `fasta36` / `fasta3` 路径均 404，见「版本」），故仅登记 native。
> ⚠️ 命名提示：模块名（软件名）为 **`fasta`**，上游仓库与主程序名为 **`fasta36`**（本模块保留 `fasta36` 等二进制名）；
> bioconda 的包名为 **`fasta3`**（`fasta36` / `fasta` 在 bioconda 均为 404），其提供 `fasta36` 等二进制。

***

## native 实现

# fasta / native — 自包含序列搜索驱动

FASTA（上游 wrpearson/fasta36）序列相似性搜索与比对工具包的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

FASTA 软件包包含一系列序列比对工具。

七个子命令对应 FASTA 的核心搜索程序：

| 子命令        | 命令                          | 作用                              |
| ---------- | --------------------------- | ------------------------------- |
| `search`   | `fasta36 <query> <library>` | 蛋白/核酸相似性搜索（启发式，快）               |
| `ssearch`  | `ssearch36 <query> <library>` | Smith-Waterman 全 DP 搜索（敏感）     |
| `fastx`    | `fastx36 <query> <library>` | 翻译后核酸查蛋白库                       |
| `fasty`    | `fasty36 <query> <library>` | 允许移码的翻译搜索                       |
| `ggsearch` | `ggsearch36 <query> <library>` | 全全局比对搜索                         |
| `glsearch` | `glsearch36 <query> <library>` | 半全局比对搜索                         |
| `lalign`   | `lalign36 <query> <library>` | 多条局部比对                          |

公共选项：`-m <格式>`（如 8=制表）、`-E <evalue>`、`-s <矩阵>`、`-b <top数>`；结果默认写 stdout（`-o/--output` 时落盘）。

> FASTA 各搜索程序均为**单线程**；子命令仍接受 `--threads` / `--tmpdir` 以保持接口一致（`--threads` 不向二进制透传）。

## 用法

```bash
# CLI 直跑
python main.py search query.fasta db.fasta -m 8 -E 1e-5 -s BLOSUM62 -o hits.tsv
python main.py ssearch query.fasta db.fasta -m 8 -o hits.tsv
python main.py fastx query.fasta db.fasta
python main.py glsearch query.fasta db.fasta

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：蛋白库搜索（PASA / 注释流程中的 FASTA 步骤）

FASTA 是 PASA、GETA 等注释流程的序列比对依赖。以下为典型用法；等价能力由 `native/main.py` 的 `search` / `ssearch` / `fastx` 等子命令提供（见上「用法」）。

```bash
# 1) 蛋白-蛋白相似性搜索（输出制表格式，便于下游解析）
fasta36 query.faa proteins.faa -m 8 -E 1e-5 -b 50 > search.hits.tsv

# 2) 核酸对核酸的敏感搜索（Smith-Waterman）
ssearch36 query.fna genome.fna -m 8 -E 1e-10 > ssearch.hits.tsv

# 3) 核酸（翻译）查蛋白库
fastx36 transcripts.fna proteins.faa -m 8 > fastx.hits.tsv

# 建库后可复用：fasta36 首次搜索会自动生成 db.fasta.?? 索引文件
ls db.fasta.*
```

> **桥接**：上述命令等价于 `python main.py search ...` / `python main.py ssearch ...` / `python main.py fastx ...`。

### 常用参数

| 参数          | 说明                                 |
| ----------- | ---------------------------------- |
| `-m 8`      | 制表格式输出（blasts 风格：每行一条命中）            |
| `-E 1e-5`   | E-value 阈值                         |
| `-s BLOSUM62` | 打分矩阵（蛋白）                          |
| `-b 50`     | 每条查询保留的 top 命中数                    |
| `-n`        | （lalign）输出的局部比对条数                  |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。
官方同时提供**预编译二进制包**（GitHub release `fasta-36.3.8i-linux64.tar.gz`）与**源码编译**，两条路线并列保留（预编译优先）。

### 1. Conda（包管理器安装）

```bash
mamba create -n fasta36 -c conda-forge -c bioconda fasta3=36.3.8i   # 包名为 fasta3（提供 fasta36 等二进制）
conda activate fasta36
fasta36   # 验证（无参运行时打印版本横幅）
```

> Homebrew 无 FASTA 公式（homebrew-core / brewsci-bio 均无），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `fasta36`，无 conda 时下载官方 release 预编译二进制 / macOS 走源码编译到 `~/software/fasta36-<ver>` 并写 PATH；版本默认 36.3.8i，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/fasta3:36.3.8i--h7b50bb2_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/fasta3:36.3.8i--h7b50bb2_3 \
    fasta36 /data/query.fasta /data/db.fasta -m 8 > hits.tsv
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull fasta36.sif docker://depot.galaxyproject.org/singularity/fasta3:36.3.8i--h7b50bb2_3
apptainer run -B $PWD:/data -H /data fasta36.sif fasta36 /data/query.fasta /data/db.fasta -m 8 > hits.tsv
```

### 4. 官方预编译二进制包（首选）

<https://github.com/wrpearson/fasta36/releases>（tag `v36.3.8i_14-Nov-2020`，资产 `fasta-36.3.8i-linux64.tar.gz`）：

```bash
# 下载并解压到用户目录（无需 root）
wget https://github.com/wrpearson/fasta36/releases/download/v36.3.8i_14-Nov-2020/fasta-36.3.8i-linux64.tar.gz -P ~/software/
tar zxf ~/software/fasta-36.3.8i-linux64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/fasta-36.3.8i/bin/' >> ~/.bashrc
source ~/.bashrc
fasta36   # 验证
```

### 5. 官方源码编译（并列保留）

官方源码归档：<https://github.com/wrpearson/fasta36/archive/refs/tags/v36.3.8i_14-Nov-2020.tar.gz>

```bash
wget https://github.com/wrpearson/fasta36/archive/refs/tags/v36.3.8i_14-Nov-2020.tar.gz -P ~/software/
tar zxf ~/software/v36.3.8i_14-Nov-2020.tar.gz -C ~/software/
cd ~/software/fasta36-36.3.8i/src/
make -f ../make/Makefile.linux_sse2 all       # macOS 用 ../make/Makefile.os_x86_64
ln -s ../bin/fasta36 ../bin/fasta
echo 'export PATH=$PATH:~/software/fasta36-36.3.8i/bin/' >> ~/.bashrc
source ~/.bashrc
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证为主；FASTA（fasta36/fasta）已安装时额外做真实搜索冒烟
```

## 版本

* fasta（上游 fasta36）`36.3.8i`（bioconda::fasta3=36.3.8i；bioconda 另有 36.3.8 / 36.3.8h）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/fasta3 / depot.galaxyproject.org；本地不再自建容器）
* ⚠️ 教程源码用 `fasta-36.3.8g`，但 g 版在 bioconda 无构建、旧官网 `faculty.virginia.edu` 分发页已失效；本模块取可安装的官方最新 `36.3.8i`
* 官方 nf-core module（`modules/nf-core/fasta`、`modules/nf-core/fasta36`）与 snakemake-wrappers（`bio/fasta`、`bio/fasta36`、`bio/fasta3`）均无（2026-09 抓取 404）

## 容器与 Conda 链接

* **Github**：https://github.com/wrpearson/fasta36
* **Bioconda 页面**：<https://anaconda.org/bioconda/fasta3>
* **Docker**：`docker pull quay.io/biocontainers/fasta3:36.3.8i--h7b50bb2_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/fasta3%3A36.3.8i--h7b50bb2_3>
* 安装方式（本地）：`mamba create -n fasta36 -c conda-forge -c bioconda fasta3=36.3.8i`
