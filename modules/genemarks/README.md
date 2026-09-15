# genemarks 软件模块

> 汇总说明：本 README 记录 genemarks native 实现（**原核版** GeneMarkS / GeneMarkS-2）的用法与环境安装。
> 官方 **无 bioconda 包、无官方容器**（2026-09 逐渠道核实全无），仅提供**预编译包**且**下载需先申请密钥**；
> 官方 nf-core / snakemake-wrappers 亦无（仅登记于 `meta.yaml software_versions` 与本文档）。
>
> ⚠️ **区别于第七节 GeneMark-ES/ET**：本节为原核生物基因预测工具 **GeneMarkS / GeneMarkS-2（gms2）**；
> GeneMark-ES/ET 为真核版，是另一工具。

***

## native 实现

# genemarks / native — 自包含原核基因预测驱动

GeneMarkS-2（gms2.pl）与旧版 GeneMarkS（gmsn.pl）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

两个子命令：

| 子命令    | 命令                                                                                                              | 作用                    |
| ------ | ------------------------------------------------------------------------------------------------------------- | --------------------- |
| `gms2` | `gms2.pl --seq <fasta> --genome-type <archaea\|bacteria\|auto> [--gcode N] [--format F] [--output <out>] [--fnn <fnn>] [--faa <faa>]` | GeneMarkS-2 原核基因预测（自训练） |
| `gms`  | `gmsn.pl --prok [--format GFF] [--fnn] [--faa] [--pdf] <fasta>`                                                 | 旧版 GeneMarkS 原核基因预测      |

> **运行前必须已申请并放置密钥**：GeneMarkS-2 用 `~/.gmhmmp2_key`，旧版 GeneMarkS 用 `~/.gm_key`。
> 申请入口（学术非营利免费、一年有效期、商业另行授权）：
> <https://exon.gatech.edu/GeneMark/license_download.cgi>。
> 工具未提供统一线程参数，`--threads` 仅接口兼容（不注入）。

## 用法

```bash
# GeneMarkS-2：细菌基因组，标准密码子表 11，输出 GFF + 核酸/蛋白序列
python main.py gms2 -i genome.fasta --genome-type bacteria --gcode 11 --format gff \
    -o gms2.gff --fnn genes.fasta --faa proteins.fasta

# GeneMarkS-2：古菌 + 自动判断密码子表
python main.py gms2 -i genome.fasta --genome-type archaea --format gtf -o gms2.gtf

# 旧版 GeneMarkS（位置参数）
python main.py gms  genome.fasta --format GFF --fnn --faa --pdf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`--threads` 不注入）。

## 实战示例：细菌基因组 GeneMarkS-2 预测 → GFF3 转换

GeneMarkS-2 是原核生物基因预测的常用工具，适用于细菌/古菌基因组（序列建议 > 50 kb）。典型用法
（等价能力由 `native/main.py` 的 `gms2` 子命令提供，见上「用法」）：

```bash
mkdir -p genemark_s && cd genemark_s

# 0. 准备基因组（FASTA）：清洗 header（仅保留首个 token），避免注释符干扰
gzip -dc GCF_000005845.2_ASM584v2_genomic.fna.gz > genome.ecoli.fasta
perl -p -i -e 's/^(>\S+).*/$1/' genome.ecoli.fasta

# 1. 运行 GeneMarkS-2（细菌、密码子表 11、GFF 输出，同时导出基因/蛋白序列）
python ../main.py gms2 -i genome.ecoli.fasta --genome-type bacteria --gcode 11 \
    --format gff -o gms2.gff --fnn genes.fasta --faa proteins.fasta

# 2. 旧版 GeneMarkS（如需 genemark_suite）
python ../main.py gms  genome.ecoli.fasta --format GFF --fnn --faa

# 3. 如需 GFF3：官方包内附带 geneMarkS_gff2gff3.pl 等转换脚本
#    /opt/genemarks/geneMarkS_gff2gff3.pl gms2.gff Ecoli > gms2.gff3
```

### 参数说明

| 参数              | 说明                                              |
| --------------- | ----------------------------------------------- |
| `--seq` / `-i`  | 输入基因组 FASTA（原核，建议 > 50 kb）                      |
| `--genome-type` | 基因组类型：archaea\|bacteria\|auto（gms2，默认 auto）     |
| `--gcode`       | 遗传密码子表（gms2，支持 11/4/25/15）                     |
| `--format`      | 输出格式（gms2：lst\|gff\|gtf\|gff3；gms：LST\|GFF）    |
| `--output`      | 输出坐标文件（gms2 默认 gms2.lst）                        |
| `--fnn`         | 输出基因核酸序列（gms2 带文件名；旧版 gms 为开关）                  |
| `--faa`         | 输出蛋白序列（同上）                                      |
| `--ext`         | 外部证据 GFF（gms2 PLUS 模式）                          |
| `--pdf`         | 输出可视化 PDF（旧版 gms）                               |

## 环境安装（官方预编译二进制包优先；需先申请密钥）

官方 **无 bioconda 包、无 quay/depot 镜像**（2026-09 核实全无）；官方提供**预编译包**
（`genemark_suite_linux_64` / `gms2_linux_64.gz`），但**下载需先在线申请密钥**，故安装前请先申请。

### 0. 申请密钥（必做）

1. 打开 <https://exon.gatech.edu/GeneMark/license_download.cgi>；
2. 选择软件（`gms2` GeneMarkS-2 / `gms` GeneMarkS）与操作系统、填写机构信息并同意学术许可；
3. 获得动态下载链接与密钥文件（`gm_key_64.gms2.gz` 等）；
4. 密钥放置：GeneMarkS-2 -> `~/.gmhmmp2_key`；旧版 GeneMarkS -> `~/.gm_key`（`gzip -dc gm_key_64.gms2.gz > ~/.gmhmmp2_key`）。

### 1. 官方预编译二进制包（首选）

```bash
# GeneMarkS-2（gms2_linux_64.gz -> 解出 tar）
tar zxf ~/software/gms2_linux_64.tar.gz -C ~/software/
echo 'export PATH=$HOME/software/gms2_linux_64:$PATH' >> ~/.bashrc
gzip -dc ~/software/gm_key_64.gms2.gz > ~/.gmhmmp2_key
source ~/.bashrc

# 旧版 GeneMarkS（genemark_suite_linux_64）
# tar zxf ~/software/genemark_suite_linux_64.tar.gz -C ~/software/
```

> 一键安装可直接运行 `native/install.sh`（安装**你已授权的压缩包**：`--tarball <本地包>` 或
> `--url <授权直链>`；解压到 `~/software/genemarks-<ver>` 并写 PATH；`--key <密钥文件>` 可一并安装密钥）。
> 用法：`bash native/install.sh --help`。官方动态链接无法硬编码，故本脚本不内嵌 URL/sha256。

### 2. 官方源码（并列说明）

GeneMarkS-2 官方**仅分发预编译包**（未提供可公开下载的源码归档）；故无源码编译路线。旧版
GeneMarkSuite 同为预编译分发。**已核实官方无预编译以外的源码资产**。

### 3. Conda / brew（不可用）

* **Conda**：bioconda 无 `genemarks` / `genemark-s` / `genemark` / `gms2` 包（2026-09 核实 404）；conda-forge 亦无。
* **Homebrew**：homebrew-core 与 brewsci/bio 均无 genemarks 公式（2026-09 核实 404）。
* 因此不提供 conda / brew 安装块。

### 4. Docker（自建镜像）

官方无镜像，本模块提供自建配方（`native/Dockerfile`；debian:bookworm-slim + perl + 官方预编译包）：

```bash
# 构建（context 必须是 modules/ 层；须先取得已授权的 GMS2_URL）
docker build -t bioskills/genemarks:1.14_1.25_lic \
    --build-arg GMS2_URL="<官方授权下载链接>" \
    -f modules/genemarks/native/Dockerfile modules/
# 运行：必须 -u $(id -u):$(id -g)，并挂载密钥
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    -v $HOME/.gmhmmp2_key:/root/.gmhmmp2_key:ro \
    bioskills/genemarks:1.14_1.25_lic \
    gms2 -i /data/genome.fasta --genome-type bacteria --gcode 11 --format gff -o /data/gms2.gff
```

### 5. Apptainer / Singularity（自建 sif）

```bash
# 先将已授权压缩包放到 modules/genemarks/native/gms2_linux_64.gz
cd modules && apptainer build genemarks-1.14.sif genemarks/native/Apptainer.def
apptainer run -B $PWD:/data -H /data genemarks-1.14.sif gms2 \
    -i /data/genome.fasta --genome-type bacteria --gcode 11 --format gff -o /data/gms2.gff
```

## 测试

```bash
bash test/run_test.sh   # gms2/gms 为 argv 构造验证；脚本已安装时做存在性探测（不触发真实预测，需密钥）
```

## 版本

* GeneMarkS-2 **1.14_1.25_lic**（官方下载页标注；GeneMarkS-2 自带 README 曾标 1.14_1.24_lic，以官方下载页为准）
* 旧版 GeneMarkS **v4.30**（官方下载页标注）
* 构建路线：**自建容器/官方预编译包**（官方渠道 bioconda→quay.io/biocontainers→depot.galaxyproject.org 2026-09
  核实全无：bioconda API 404、quay API 401、depot 无）
* 许可：Georgia Tech 学术许可（学术/非营利免费、一年有效期、需申请密钥；商业另行授权）

## 官方实现登记（不建目录）

* **nf-core**：`modules/nf-core/genemarks` 不存在（2026-09 核实 `meta.yml` 404）；BRAKER 相关流程以上游 BRAKER 说明为准。
* **snakemake-wrappers**：`bio/genemarks` 不存在（2026-09 核实 `environment.yaml` / `wrapper.py` 均 404）。

## 容器与 Conda 链接

* **官方站点**：<http://exon.gatech.edu/GeneMark/>
* **密钥申请/下载**：<https://exon.gatech.edu/GeneMark/license_download.cgi>
* **Bioconda**：（无——api.anaconda.org/package/bioconda/genemarks 及 genemark-s/genemark/gms2 均 404，2026-09 核实）
* **Docker/Singularity**：（官方无）本仓库自建：`native/Dockerfile` + `native/Apptainer.def`（需授权压缩包）
* **Homebrew**：（无——homebrew-core 与 brewsci/bio 均 404）
* 安装方式（本地）：先申请密钥，再 `bash native/install.sh --tarball <已授权压缩包>`（见上）
