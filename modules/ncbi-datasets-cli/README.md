# ncbi-datasets-cli 软件模块

> 汇总说明：本 README 合并本模块各实现（仅 native 一路）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。本模块只建 `native/`——官方无 brew/nf-core/snakemake-wrappers 实现（2026-09 核实）；conda 包在 **conda-forge**；官方容器存在但版本滞后（见「版本差异」）。

***

## native 实现

# ncbi-datasets-cli / native — NCBI 基因组数据下载与摘要驱动

NCBI Datasets 官方命令行工具（同包两个二进制 `datasets` 与 `dataformat`）的本地自包含实现
（`source_type: custom`、`type: native`）：按 **accession** 或 **taxon（物种）** 批量下载
基因组与注释（genome / gff3 / gbff / rna / cds / protein / seq-report），NCBI 服务端自动
打包 zip 并提供校验，免去手工在 FTP 目录逐层拼路径下载多个文件的麻烦；`datasets summary`
输出元数据 JSON，`dataformat` 可将其转为 TSV 表。本驱动把两工具封为**两个并列子命令**。

## 功能

模块提供**两个并列子命令**（对应官方同包的两个二进制 `datasets` 与 `dataformat`）：

| 子命令 | 二级 | 底层命令 | 作用 |
| --- | --- | --- | --- |
| `datasets` | `download` | `datasets download genome accession\|taxon <x> [--include genome,gff3] [-o zip] [--dehydrated]` | accession/taxon → 基因组数据包 zip（序列 + 注释 + 组装报告，自动打包） |
| `datasets` | `summary` | `datasets summary genome accession\|taxon <x> [--as-json-lines] [--report <r>]` | accession/taxon → 元数据 JSON（供 dataformat 转 TSV / 审阅） |
| `dataformat` | `fmt report_type` | `dataformat tsv genome --package <zip> [--accession \| --taxon] [--fields ...]` | 把 summary/下载包 JSON 转 TSV 表（gene / protein / virus 等同理） |
| `help` | — | 驱动子命令清单（二进制已安装时附真实 `datasets --help` / `dataformat version`） | 帮助 |

> `datasets` 的 `download` / `summary` 之外数据类型（gene / virus / ortholog）同理：装好后直接用原生
> CLI 即可（如 `datasets download virus taxon ...`）；`dataformat` 已封为并列子命令（见下「用法」）。

## 用法

```bash
# CLI 直跑（datasets 子命令 + 二级 download/summary）
python main.py datasets download GCF_000001405.39 --include genome,gff3 -o ncbi_dataset.zip
python main.py datasets download --taxon "Homo sapiens" --include genome --dehydrated
python main.py datasets summary GCF_000001405.39 --json-lines
python main.py datasets summary --taxon "Homo sapiens"

# dataformat 子命令（JSON -> TSV 表；package / accession / taxon 三选一 selector）
python main.py dataformat tsv genome --package ncbi_dataset.zip > genome_table.tsv
python main.py dataformat tsv gene --taxon "Homo sapiens" --fields gene_id,symbol

python main.py help

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（datasets 自身并发下载，线程参数为驱动层占位）。

> **批量多物种断点下载**（多 accession + 失败重试 + MD5 断点续传 + 按物种分类归置）：native/ 另有经典
> 脚本 [genome_download.sh](native/genome_download.sh)，见下方「实战示例 §7」。

## 实战示例：NCBI Datasets 批量下载基因组与注释（免手工 FTP 拼路径）

NCBI Datasets 是 NCBI 官方的数据打包下载服务与命令行工具：按 accession 或物种一次打包下载
基因组序列、注释与组装元数据（zip + 校验 + `assembly_data_report.jsonl`），替代手工在 FTP
目录逐层点进 assembly 目录、手动核对多个文件的繁琐流程（等价能力由 `native/main.py` 的
`datasets download` / `datasets summary` / `dataformat` 子命令提供，见上「用法」）。以下为直接使用原生 CLI
（安装后 `datasets` / `dataformat` 即官方二进制）的典型场景；NCBI 官方入门示例为人类参考基因组 GRCh38（`GCF_000001405.39`）。

### 1. 下载基因组序列 + 注释（最常用）

```bash
mkdir -p ~/ncbi_datasets && cd ~/ncbi_datasets

# accession 下载：--include 指定数据类型，默认 genome,gff3（基因组 + gff3 注释）
datasets download genome accession GCF_000001405.39 --include genome,gff3 -o ncbi_dataset.zip

# 解压后即得打包好的基因组/注释（无需手工拼 FTP 路径）：
unzip -q ncbi_dataset.zip
# ncbi_dataset/
#   data/GCF_000001405.39/GCF_000001405.39_GRCh38.p14_genomic.fna   # 基因组序列
#   data/GCF_000001405.39/GCF_000001405.39_GRCh38.p14_genomic.gff    # gff3 注释
#   data/assembly_data_report.jsonl                                  # 组装元数据
```

### 2. 只下载基因组序列（不要注释）

```bash
datasets download genome accession GCF_000001405.39 --include genome -o ncbi_dataset_genome.zip
```

### 3. 下载注释与 GenBank flatfile

```bash
# gff3 注释 + GenBank 格式（gbff）
datasets download genome accession GCF_000001405.39 --include gff3,gbff -o ncbi_dataset_anno.zip
```

### 4. 按物种（taxon）批量下载 / 批量 accession

```bash
# 按物种名或 NCBI Taxonomy ID 下载（适合一个物种多个组装）
datasets download genome taxon "Homo sapiens" --include genome,gff3 -o homo_sapiens.zip
datasets download genome taxon 9606 --include genome,gff3          # taxon ID 等价写法

# 多 accession 空格分隔一次下载（自动打包为同一个 zip）
datasets download genome accession GCF_000001405.39 GCF_000009045.1 --include genome,gff3
```

### 5. 查看元数据（summary）与转 TSV（dataformat）

```bash
# accession / 物种 的元数据摘要（JSON / JSON Lines）
datasets summary genome accession GCF_000001405.39
datasets summary genome taxon "Homo sapiens" --as-json-lines | head

# 兄弟工具 dataformat：把下载包内的组装报告转成 TSV 表
dataformat tsv genome --package ncbi_dataset.zip > genome_table.tsv
```

### 6. 与手工 FTP 下载对比

| 方式 | 流程 | 缺点 |
|------|------|------|
| 手工 FTP（旧） | 逐物种在 FTP 目录找 assembly 层 → 记录 GCF 号 → 分别下载 `*_genomic.fna`、`*_genomic.gff`… → 自行核对/记录 | 路径易拼错、多文件多次下载、无统一清单 |
| `datasets`（本模块） | 一条命令按 accession/taxon 下载 → NCBI 自动打包 zip（含序列/注释/`assembly_data_report.jsonl`） | 需要较新 glibc（老系统见「环境安装 §4」警告） |

### 7. 批量多物种断点下载（genome_download.sh 经典脚本）

`native/main.py` 的单次 download 之外，native/ 还提供批量脚本 [genome_download.sh](native/genome_download.sh)
（模块经典脚本位）：逐行读取 accession 列表，对每个物种下载 → 解压 → **MD5 完整性校验**，
**失败自动重试**（`--retries`）、历史目录校验通过则**断点跳过**，最后把 FASTA / 注释（GFF3 或 GBFF）
**按物种分类归置**，并输出成功/失败统计与退出码（有失败 → exit 1，便于流程/CI 判断）。

```bash
# species_list.txt 格式：每行两列 accession + 物种名（# 开头为注释）
#   GCF_000001405.39    Homo_sapiens
#   GCF_000001635.27    Mus_musculus
bash native/genome_download.sh -i species_list.txt -o ~/genomes --retries 3
# 产物：~/genomes/FASTA/Homo_sapiens/Homo_sapiens.fa 与 ~/genomes/GENE/Homo_sapiens/<原名>.gff(.gbff)

# 参数一览：-i/--input · -o/--output · --fasta-dir · --genes-dir · --include（默认 genome,gff3，
# 可改 genome,gbff 取 GenBank）· --retries · -h/--help
bash native/genome_download.sh --help
```

> 该脚本下载内容与 `main.py datasets download` 等价（同为 `datasets download genome`），差异在
> 「批量 + 重试 + MD5 断点 + 分类」编排；单条 accession 轻量调用仍建议走 `main.py`。

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道 2026-09 核实：**conda 包在 conda-forge**（`ncbi-datasets-cli=18.36.0`，与上游一致）；**Homebrew（core / brewsci/bio）无公式**；
官方容器 `quay.io/biocontainers/ncbi-datasets-cli:14.26.0` 与 depot.galaxyproject.org sif 存在（**直接拉取官方镜像，本地不维护 Dockerfile/Apptainer.def**）；
宿主机两条路线（一键 `bash native/install.sh`，`auto`：有 conda/mamba → conda-forge，否则官方 GitHub release 二进制到 `~/software/datasets-18.36.0`）。
版本差异：上游 release / conda-forge 18.36.0 vs 官方容器 14.26.0（容器滞后，较新参数可能缺失，见下）。

### 1. Conda / brew（包管理器安装）

conda 包在 **conda-forge**（2026-09 核实，18.36.0，覆盖 linux/osx/win × 64/arm64）——早期仅查 bioconda 曾误判「无 conda 路线」，已修正：

```bash
mamba create -n ncbi-datasets-cli -c conda-forge ncbi-datasets-cli=18.36.0
conda activate ncbi-datasets-cli
datasets --version    # 应含 18.36.0；dataformat 同环境可用（dataformat version）
```

Homebrew core 公式与 `brewsci/bio` tap 均无（2026-09 核实），**不提供 brew 安装块**。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ncbi-datasets-cli:14.26.0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ncbi-datasets-cli:14.26.0 \
    download genome accession GCF_000001405.39 --include genome,gff3 -o /data/ncbi_dataset.zip
# 用兄弟工具 dataformat 时显式指定 --entrypoint：
docker run --rm --entrypoint dataformat -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ncbi-datasets-cli:14.26.0 tsv genome --package /data/ncbi_dataset.zip
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull ncbi-datasets-cli.sif docker://depot.galaxyproject.org/singularity/ncbi-datasets-cli:14.26.0
apptainer run -B $PWD:/data -H /data ncbi-datasets-cli.sif \
    download genome accession GCF_000001405.39 --include genome,gff3 -o /data/ncbi_dataset.zip
```

### 4. 二进制包安装（官方 release，推荐方式）

* **GitHub**：<https://github.com/ncbi/datasets>（release 页 <https://github.com/ncbi/datasets/releases>）
* **官网**：<https://www.ncbi.nlm.nih.gov/datasets/>

官方按平台分发 zip 资产（v18.36.0，2026-08；`<plat>.cli.package.zip`，包内含 `datasets` 与 `dataformat` 两个可执行）：

| 平台 | release 资产 |
|------|-------------|
| Linux x86_64 | `linux-amd64.cli.package.zip` |
| Linux arm64 | `linux-arm64.cli.package.zip` |
| macOS x86_64（Intel） | `darwin-amd64.cli.package.zip` |
| macOS arm64（Apple Silicon） | `darwin-arm64.cli.package.zip` |
| Windows amd64 | `windows-amd64.cli.package.zip` |

```bash
cd ~/software
# 按本机平台选择（示例 Linux x86_64；macOS arm64 换成 darwin-arm64.cli.package.zip）
wget -c https://github.com/ncbi/datasets/releases/download/v18.36.0/linux-amd64.cli.package.zip
unzip -q linux-amd64.cli.package.zip -d datasets-18.36.0
# 若解压后二进制位于子目录，将 PATH 指向含 datasets 的那一层
export PATH=$PATH:~/software/datasets-18.36.0

# 验证安装（datasets 输出应含 18.36.0；dataformat 用 version 子命令）
datasets --version
dataformat version
echo 'export PATH=$PATH:~/software/datasets-18.36.0' >> ~/.bashrc
```

> 一键安装：直接 `bash native/install.sh`（`auto` 双路线：有 conda/mamba → conda-forge 建环境
> `ncbi-datasets-cli`；无 conda → binary 下载官方 release 到 `~/software/datasets-18.36.0`、装入
> `datasets` + `dataformat`、`datasets --version` 断言、可选写 PATH；`--help` 看用法）。
> 另：NCBI ftp 提供单二进制 LATEST 直链（无 dataformat）：
> `wget https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/linux-amd64/datasets`。

> 💡 **校验说明**：官方 release 未发布公开 sha256 资产（2026-09 核实），下载后无法做摘要校验；
> 解压后 NCBI 数据包（`ncbi_dataset.zip`）本身带打包校验与 `assembly_data_report.jsonl` 清单，可据此确认数据完整。

> ⚠️ **兼容性警告（glibc）**：新版 `datasets` 客户端依赖较新的 glibc；**CentOS 6（glibc 2.12）
> 等老系统**可能报 `version GLIBC_2.x not found` 等错误无法运行。建议在 CentOS 7+ / Ubuntu 20.04+
> 或容器中运行；确实受困于老系统的，可退回旧版本归档（如 v14 系 release）或使用官方容器
> `quay.io/biocontainers/ncbi-datasets-cli:14.26.0`。

## 版本差异（native vs 官方容器）

| 路线 | 版本 | 说明 |
|------|------|------|
| native（GitHub release / ftp LATEST，本模块 install.sh） | **18.36.0** | 上游最新；release assets 无公开 sha256 |
| 官方容器 quay.io/biocontainers / depot.galaxyproject.org | **14.26.0** | 存在但**滞后**于上游（较新参数可能缺失；老系统兼容反而可用它兜底） |
| bioconda / Homebrew / nf-core / snakemake-wrappers | 官方无 | 2026-09 全部核实 404 / 无公式，均登记「官方无」 |

## 测试

```bash
bash test/run_test.sh   # 8 步：自省 + datasets(download/summary)/dataformat argv 构造断言 + install.sh bash -n + 可选二进制冒烟
```

## 版本

* datasets / dataformat 18.36.0（官方 GitHub release；NCBI ftp LATEST 同版本）

* 构建路线：官方 release 二进制 / 官方容器（quay.io/biocontainers/ncbi-datasets-cli / depot.galaxyproject.org；本地不维护配方）

* dataformat 已封为模块并列子命令（`python main.py dataformat ...`），非脚本级裸调用

## 容器与 Conda 链接

* **GitHub**：<https://github.com/ncbi/datasets>

* **官网**：<https://www.ncbi.nlm.nih.gov/datasets/>

* **Bioconda 页面**：官方无（<https://anaconda.org/bioconda/ncbi-datasets-cli> → 404，2026-09）

* **Docker**：`docker pull quay.io/biocontainers/ncbi-datasets-cli:14.26.0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/ncbi-datasets-cli%3A14.26.0>

* **NCBI ftp（单二进制 LATEST）**：<https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/>
