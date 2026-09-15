# freebayes 软件模块

> 汇总说明：本 README 合并各实现（native + 官方 nf-core / snakemake-wrappers 登记）的用法；
> 安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# freebayes / native — 自包含贝叶斯变异检测驱动

freebayes 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

freebayes 是一个基于贝叶斯算法的变异检测工具，用于从 BAM 文件中检测 SNP 和 INDEL。它支持任意倍性的样本，特别适合非二倍体生物和群体样本的变异检测。

两个子命令覆盖单/多样本检测与区域并行：

| 子命令        | 命令（驱动构造）                                                                                          | 作用                          |
| ---------- | ------------------------------------------------------------------------------------------------- | --------------------------- |
| `call`     | `freebayes -f <ref> [--ploidy N] [--min-alternate-count N] [--min-coverage N] <bam...>`（结果写 stdout，`-o` 落盘） | 单/多样本贝叶斯变异检测                |
| `parallel` | `freebayes-parallel <regions.bed> <ncpus> -f <ref> <bam...>`                                       | 按区域文件并行检测（GNU parallel）     |

> `call` 单线程；`parallel` 把 `--threads`（默认 8）作为并发 CPU 数传给 freebayes-parallel。

## 用法

```bash
# CLI 直跑
python main.py call -f genome.fasta --ploidy 2 --min-alternate-count 3 --min-coverage 5 \
    -o variants.filtered.vcf V1.bam V2.bam
python main.py parallel regions.bed -f genome.fasta -o out.vcf V1.bam --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：单样本 → 多样本 → 过滤

给出 freebayes 的典型用法；等价能力由 `native/main.py` 的 `call` 子命令提供
（见上「用法」）。

```bash
mkdir -p freebayes && cd freebayes
ln -s ../*bam* . && ln -s ../genome.* .

# 单个样本变异检测
freebayes -f genome.fasta V1.bam > variants.vcf

# 多个样本联合变异检测
freebayes -f genome.fasta V1.bam V2.bam > variants.multi.vcf

# 指定倍性（如单倍体真菌）
freebayes -f genome.fasta --ploidy 1 V1.bam > variants.haploid.vcf

# 设置最小等位基因计数和最小覆盖度
freebayes -f genome.fasta \
    --min-alternate-count 3 \
    --min-coverage 5 \
    V1.bam > variants.filtered.vcf

# 与 bcftools 配合使用，一步完成检测和过滤
freebayes -f genome.fasta V1.bam V2.bam | \
    bcftools filter -i 'QUAL > 30 && DP > 10' -Ov - > variants.filtered.vcf

# 等价（多样本 + 过滤阈值）：
#   python main.py call -f genome.fasta V1.bam V2.bam --min-alternate-count 3 --min-coverage 5 \
#       -o variants.filtered.vcf
```

### 参数说明

| 参数                        | 说明                    |
| ------------------------- | --------------------- |
| `-f`                      | 指定参考基因组 FASTA 文件       |
| `--ploidy`                | 设置样本倍性，默认为 2          |
| `--min-alternate-count`   | 最小等位基因计数（支持变异的 reads 数） |
| `--min-coverage`          | 最小覆盖深度                |
| `--min-base-quality`      | 最小碱基质量                |
| `--min-mapping-quality`   | 最小比对质量                |

### 注意事项

* freebayes 支持任意倍性的样本，适合非二倍体生物
* 与 GATK 相比运行更快，但对复杂变异的检测灵敏度稍低
* 输出标准 VCF，可结合 `bcftools` 过滤与格式转换

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），可直接拉取官方
镜像运行工具二进制；freebayes 官方同时提供**预编译静态二进制**与**源码**两条路线，均保留如下。

### 1. 官方预编译二进制包（首选）

GitHub release 提供预编译静态二进制（仅 linux-amd64）：

* <https://github.com/freebayes/freebayes/releases/download/v1.3.10/freebayes-1.3.10-linux-amd64-static.gz>

```bash
# 下载并解压到用户目录（免 root；禁 /opt/biosoft）
mkdir -p ~/software/freebayes-1.3.10/bin
curl -fsSL -o /tmp/freebayes.gz \
    https://github.com/freebayes/freebayes/releases/download/v1.3.10/freebayes-1.3.10-linux-amd64-static.gz
gunzip -c /tmp/freebayes.gz > ~/software/freebayes-1.3.10/bin/freebayes
chmod 755 ~/software/freebayes-1.3.10/bin/freebayes
export PATH="$HOME/software/freebayes-1.3.10/bin:$PATH"

freebayes --version   # 断言
```

> 💡 一键安装：`bash native/install.sh --method binary`（仅 linux-x64；内嵌该版本 sha256）。
> 注意：静态二进制仅含 `freebayes` 本体；`freebayes-parallel` 及配套脚本
> （`vcffirstheader` / `vcfstreamsort` / `vcfuniq` / `fasta_generate_regions.py`）不在静态包内，
> 需走 conda 或源码 release。

### 2. 官方源码编译（并列保留）

```bash
git clone --recursive https://github.com/freebayes/freebayes.git
cd freebayes
make -j $(nproc)          # 需 g++ / zlib / libbz2 / liblzma 等开发库
# 或添加到 PATH
echo 'PATH=$PATH:'"$PWD"'/bin/' >> ~/.bashrc && source ~/.bashrc
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n freebayes-native -c conda-forge -c bioconda freebayes=1.3.10
conda activate freebayes-native
freebayes --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install freebayes
freebayes --version   # 断言（brew 当前 1.3.10，与 meta 登记一致）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `freebayes`，
> 无 conda 时下载官方静态二进制到 `~/software/freebayes-<ver>`；版本默认 1.3.10，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/freebayes:1.3.10--h3752d28_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/freebayes:1.3.10--h3752d28_1 \
    freebayes -f /data/genome.fasta /data/V1.bam > variants.vcf
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull freebayes.sif docker://depot.galaxyproject.org/singularity/freebayes:1.3.10--h3752d28_1
apptainer run -B $PWD:/data -H /data freebayes.sif -f /data/genome.fasta /data/V1.bam > variants.vcf
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules（官方）**：`modules/nf-core/freebayes` 为**扁平单模块**（无子模块目录），
   pin `bioconda::freebayes=1.3.10`。执行前请 `nf modules install nf-core freebayes`
  安装到项目自身目录，**不要直接引用本仓库示例**；缺失时以本模块 `native/` 兜底。

* **snakemake-wrappers（官方）**：`bio/freebayes` 为**扁平 wrapper**，
  environment.yaml pin `freebayes=1.3.10`（含 `vcflib=1.0.15` / `bcftools=1.24` /
  `snakemake-wrapper-utils=0.9.0`）。运行靠 Snakemake 解析
  `wrapper: "v9.17.1/bio/freebayes"` 句柄，**不要把本地示例当 `wrapper_path`**；
  缺失时以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch _resolve_binary，不依赖已安装 freebayes）
```

## 版本

* freebayes 1.3.10（bioconda::freebayes=1.3.10；quay tag 1.3.10--h3752d28_1）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/freebayes / depot.galaxyproject.org；本地不再自建容器）

* 官方 release 静态二进制仅 linux-amd64；macOS 走 conda / 源码

## 容器与 Conda 链接

* **官网**：https://github.com/freebayes/freebayes

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/freebayes/overview>

* **Docker**：`docker pull quay.io/biocontainers/freebayes:1.3.10--h3752d28_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/freebayes%3A1.3.10--h3752d28_1>

* 安装方式（本地）：`mamba create -n freebayes -c conda-forge -c bioconda freebayes=1.3.10`
