# lastz 软件模块

> 汇总说明：本 README 合并 native 实现用法；安装方式见下方各节，容器与 conda 信息记录于此。
>
> **版本提示**：本模块以 **LASTZ 1.04.22** 为准。2026-09 核实
> bioconda/quay/depot 均含 1.04.22 构建（bioconda 最新为 1.04.52）；**LASTZ 为单线程程序**，
> 并行请按参考染色体拆分（见「实战示例」）。

***

## native 实现

# lastz / native — 自包含双序列/全基因组比对驱动

LASTZ 1.04.22 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

**LASTZ** 是一款用于两条基因组序列比对的工具，是 BLASTZ 的后继版本。它专门设计用于全基因组比对，能够识别基因组间的同源区域，包括大的重排、倒位和插入缺失。

- 专为全基因组比对设计
- 支持长序列比对
- 识别大的结构变异（倒位、易位等）
- 输出多种格式（MAF、lav等）
- 速度快，内存效率高

单命令 `align` 覆盖 LASTZ 的比对用法：

| 子命令    | 命令                                                                                             | 作用                                   |
| ------ | ---------------------------------------------------------------------------------------------- | ------------------------------------ |
| `align` | `lastz <target> <query> --output=<file> --format=<type> [--hspthresh= … --filter=identity: …]`   | 双序列/全基因组比对 → lav / maf / general 等 |

> 官方一致率/覆盖度过滤的正确写法是 `--filter=identity:<min>` / `--filter=coverage:<min>`；
> `--identity=90 --coverage=50` 为本驱动的 `--identity` / `--coverage` 参数（内部映射为
> 上述官方 `--filter=` 形式）。

## 用法

```bash
# CLI 直跑（lav / maf 输出）
python main.py align ref.fasta query.fasta --output result.lav --format lav
python main.py align ref.fasta query.fasta --output result.maf --format maf

# 更敏感的过滤参数（HSP/带间隙阈值 + 一致率/覆盖度）
python main.py align ref.fasta query.fasta --output result.lav --format lav \
    --hspthresh=2200 --gappedthresh=4000 --identity=90 --coverage=50

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；LASTZ 单线程，`--threads` 为占位（不注入命令行）。

## 实战示例：两基因组比对

```bash
mkdir -p i.lastz && cd i.lastz
cp Malassezia_sympodialis.genome_V01.fasta ref.fasta
cp IDBA.fasta query.fasta

# 12.2.1 基本比对（输出 lav 格式）
lastz ref.fasta query.fasta --output=result.lav --format=lav
# 输出 MAF（Multiple Alignment Format）
lastz ref.fasta query.fasta --output=result.maf --format=maf

# 12.2.2 更敏感的参数
lastz ref.fasta query.fasta --output=result.lav \
    --hspthresh=2200 --gappedthresh=4000 --identity=90 --coverage=50

# 12.2.3 分染色体比对（LASTZ 单线程 → 按参考染色体拆分并行）
python -c "
from Bio import SeqIO
import os
os.makedirs('ref_chr', exist_ok=True)
for rec in SeqIO.parse('ref.fasta', 'fasta'):
    SeqIO.write(rec, f'ref_chr/{rec.id}.fasta', 'fasta')
"
for chr in ref_chr/*.fasta; do
    name=$(basename $chr .fasta)
    lastz $chr query.fasta --output=result_${name}.lav --format=lav
done
```

等价能力由 `native/main.py` 的 `align` 子命令提供（见上「用法」）；带 `--output=` 时直接落盘，
无需 shell 重定向。

### 参数说明

| 参数                | 说明                                             |
| ----------------- | ---------------------------------------------- |
| `--format`        | 输出格式：lav / maf / axt / sam / general[:fields] / rdotplot / text / cigar / blastn |
| `--output`        | 输出文件（默认写 stdout）                                |
| `--hspthresh`     | HSP（gap-free 扩展）得分阈值（官方 `<score>`）              |
| `--gappedthresh`  | 带间隙扩展得分阈值（官方 `<score>`）                          |
| `--identity`      | 最小一致率百分比（映射 `--filter=identity:<min>`）           |
| `--coverage`      | 最小覆盖度百分比（映射 `--filter=coverage:<min>`）           |
| `--step`          | 种子步长（越大越快越不敏感）                                 |
| `--notransition`  | 降低种子灵敏度（不允许转换，约快 10 倍）                         |
| `--nogapped`      | 跳过带间隙扩展（仅 HSP，速度更快）                            |

> 💡 **LASTZ vs MUMmer**：MUMmer 基于精确匹配种子、速度快，适合亲缘关系较近的基因组；
> LASTZ 基于 BLAST-like 种子扩展、灵敏度更高，适合亲缘关系较远基因组与碱基水平变异检测。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
`main.py` 驱动在宿主机跑。官方 GitHub tag 1.04.22 **仅提供源码归档**（Source code zip/tar.gz，
**无预编译二进制资产**，2026-09 核实）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n lastz -c conda-forge -c bioconda lastz=1.04.22
conda activate lastz
lastz --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install lastz
lastz --version   # brew 当前 1.04.52，与 meta 登记 1.04.22 略有差异（版本以 formula 为准）
```

> 一键安装直接 `bash native/install.sh`（默认 auto：有 conda/mamba 走 bioconda `lastz=1.04.22`，
> 无 conda 时回退官方源码 `make` 编译到 `~/software/lastz-1.04.22` 并写 PATH。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/lastz:1.04.22--h7b50bb2_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/lastz:1.04.22--h7b50bb2_2 \
    ref.fasta query.fasta --output=/data/result.maf --format=maf
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull lastz.sif docker://depot.galaxyproject.org/singularity/lastz:1.04.22--h7b50bb2_2
apptainer run -B $PWD:/data -H /data lastz.sif \
    /data/ref.fasta /data/query.fasta --output=/data/result.maf --format=maf
```

### 4. 官方源码编译（并列保留；已核实无预编译二进制资产）

官方 GitHub tag 1.04.22 仅分发源码归档，源码编译为官方并列路线：

```bash
wget https://github.com/lastz/lastz/archive/refs/tags/1.04.22.tar.gz -P ~/software/
tar zxf ~/software/1.04.22.tar.gz -C ~/software/
cd ~/software/lastz-1.04.22
make -j 4
mkdir -p ~/software/lastz-1.04.22/bin
cp src/lastz ~/software/lastz-1.04.22/bin/
echo 'export PATH=$PATH:~/software/lastz-1.04.22/bin' >> ~/.bashrc && source ~/.bashrc
lastz --version   # 断言
```

> 一键安装：`bash native/install.sh --method source`（下载 1.04.22 源码 → `make` → 安装 `src/lastz`
> 到 `~/software/lastz-1.04.22/bin` 并写 PATH；版本断言 `lastz --version`。官方 release 未提供摘要，
> 脚本不内嵌 sha256、跳过校验并提示自行核对）。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证 + 自省；lastz 未安装时跳过真实冒烟
```

## 容器与 Conda 链接

* **Github**：https://github.com/lastz/lastz

* **官网**：https://lastz.github.io/lastz/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/lastz/overview>

* **Docker**：`docker pull quay.io/biocontainers/lastz:1.04.22--h7b50bb2_2`

* **Singularity**：<https://depot.galaxyproject.org/singularity/lastz%3A1.04.22--h7b50bb2_2>

* 安装方式（本地）：`mamba create -n lastz -c conda-forge -c bioconda lastz=1.04.22`

## 版本

* LASTZ **1.04.22**（官方 GitHub tag 1.04.22；bioconda/quay/depot 均有 1.04.22 构建）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/lastz:1.04.22--h7b50bb2_2 / depot.galaxyproject.org；
  本地不自建容器）

* 2026-09 核实：nf-core `modules/nf-core/lastz` 404；snakemake-wrappers `bio/lastz` 404；
  homebrew-core `lastz` 公式为 1.04.52；LASTZ 单线程（无 `--threads` 选项）
