# fastuniq 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09-08 逐渠道核实）。

***

## native 实现

# fastuniq / native — 双端短读去 PCR/光学重复驱动（v1.1）

FastUniq（Xu et al. 2012, PLoS ONE 7:e52249）的本地驱动实现（`source_type: custom`、`type: native`），命令逻辑对齐官方 v1.1 CLI（sourceforge FastUniq-1.1.tar.gz 内 README.txt）：

```
fastuniq -i <input_list> -t <q|f|p> -o <out1> [-p <out2>] [-c <0|1>]
```

## 能力

| 子命令  | 说明 | 关键参数 |
| ---- | ---- | ---- |
| `run` | 双端短读（Illumina）去 PCR/光学重复 | `-i/--list`（输入列表）或 `--read1/--read2`（自动写列表）、`-o/--output1`、`-p/--output2`、`-t/--format`（q/f/p）、`-c/--desc-type`（0/1） |

输入列表格式（官方）：**每行一个 FASTQ/FASTA 文件**，相邻两行、reads 顺序一致的文件属一对（2N 行 = N 对）；**最多 1000 对**。FastUniq 通过比较 read pair 序列（R1+R2 完全一致）识别 PCR/光学重复对并去除，**无需参考基因组**，可同时处理不同长度 reads。

> ⚠️ **真实 CLI 澄清（勿臆造）**：FastUniq 的 `-t` 是**输出序列格式**（q=双 FASTQ 默认 / f=双 FASTA / p=单 FASTA），`-c` 是**输出描述类型**（0=原始描述 / 1=重编号）——并非网上部分二手教程所说的「临时目录/输出目录」。本驱动按官方 README 录入；`--tmpdir` 只用于进程 TMPDIR 环境与自动输入列表的落盘位置。

## 快速开始

```bash
# 1. 安装环境（任选其一，见「环境安装」）
mamba create -n fastuniq -c conda-forge -c bioconda fastuniq=1.1
# 或 brew tap brewsci/bio && brew install fastuniq
# 或 bash native/install.sh

# 2. CLI 调用（与教学文档同构：-i 列表 / -o R1 / -p R2）
python main.py run -i illumina.list -o illumina.1.fastq -p illumina.2.fastq
# 双端两文件直接给（自动写 2 行输入列表）
python main.py run --read1 R1.fastq --read2 R2.fastq -o R1.uniq.fastq -p R2.uniq.fastq
# FASTA 双文件输出 + 重编号描述
python main.py run -i list.txt -t f -c 1 -o R1.uniq.fa -p R2.uniq.fa
# 单 FASTA 输出（相邻两条属一对，无需 -p）
python main.py run -i list.txt -t p -o interleaved.uniq.fa

# 3. Agent / Schema 自省
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py run -i list.txt -o out.R1.fq -p out.R2.fq --dry-run   # 只打印构建出的命令
```

> 说明：fastuniq 为**单线程** C 程序，无 `--threads`/`-p` 多线程参数（驱动内 `--threads` 仅作占位接受、不注入）；无 `--version`/`--help`（无参运行即打印用法文本并返回非 0，可用性断言见下方「测试」）。

## 实战示例：双端 reads 去除 PCR/光学重复（Trimmomatic 质控后）

以下为教学场景的典型用法（FastUniq 置于测序质控流程中：原始 reads → 质控/去接头 → **去 PCR 重复** → 组装/比对）；等价能力由 `native/main.py` 的 `run` 子命令提供（见上「快速开始」）。

### 1. 写输入列表并运行（单样本双端）

```bash
mkdir -p FastUniq && cd FastUniq

# 输入列表：每行一个 FASTQ 文件；相邻两行 = 一对（read1/read2 顺序须一致、条数相同）
ls ../Trimmomatic/illumina.?.fastq > illumina.list
cat illumina.list        # 形如：../Trimmomatic/illumina.1.fastq / ../Trimmomatic/illumina.2.fastq

# 去重（-t q 默认双 FASTQ；-o/-p 输出 read1/read2 去重结果）
fastuniq -i illumina.list -o illumina.1.fastq -p illumina.2.fastq
cd ..
```

### 2. 多样本批量（bash 循环）

```bash
mkdir -p dedup
for sample in A B C; do
    ls ../trimmomatic/${sample}.{1,2}.fastq > dedup/${sample}.list
    fastuniq -i dedup/${sample}.list \
        -o dedup/${sample}.1.fastq -p dedup/${sample}.2.fastq
done
```

### 3. 参数说明

| 参数 | 说明 |
| --- | --- |
| `-i <list>` | 输入文件列表 [FILE IN]：每行一个 FASTQ/FASTA 文件，相邻两行 reads 顺序一致的文件属一对；最多 1000 对 |
| `-t q\|f\|p` | 输出序列格式：`q`=FASTQ 双文件（默认）、`f`=FASTA 双文件、`p`=FASTA 单文件（相邻两条属一对） |
| `-o <out1>` | 第一输出文件 [FILE OUT]（read1 去重结果；`-t p` 模式为唯一输出） |
| `-p <out2>` | 第二输出文件 [FILE OUT]（read2 去重结果；可选，仅 `-t q/f` 双文件模式需要） |
| `-c 0\|1` | 输出序列描述类型：`0`=原始描述（默认）、`1`=FastUniq 重新编号 |

> 使用提示：R1/R2 两文件 reads 必须**同序同数**（缺失/乱序会报 "Error in Reading pair-end FASTQ sequence!"）；FastUniq 将 reads 载入内存排序去重，**大 lane 数据请给足内存**（官方 README/论文未给精确内存公式，超内存行为未核实）；建议先质控/去接头再去重。

***

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有 fastuniq 1.1），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n fastuniq-native -c conda-forge -c bioconda fastuniq=1.1   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate fastuniq-native
fastuniq 2>&1 | grep "The input file list of paired"   # 断言（fastuniq 无 --version/--help，无参运行即打印用法）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio          # 首次使用需要
brew install fastuniq
fastuniq 2>&1 | grep "The input file list of paired"   # 断言
# 注：公式 Fastuniq 1.1（sha256 与 bioconda 一致 9ebf2515…）；brew 当前版本与 meta 登记一致（1.1）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `fastuniq`，无 conda 时自动下载官方 sourceforge 源码包编译到 `~/software/fastuniq-1.1` 并写 PATH；版本默认 1.1，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/fastuniq:1.1--h7b50bb2_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/fastuniq:1.1--h7b50bb2_2 \
    -i /data/reads.list -o /data/out.1.fastq -p /data/out.2.fastq
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换；tag 与 quay.io/biocontainers 互通）：

```bash
apptainer pull fastuniq.sif docker://depot.galaxyproject.org/singularity/fastuniq:1.1--h7b50bb2_2
apptainer run -B $PWD:/data -H /data fastuniq.sif \
    -i /data/reads.list -o /data/out.1.fastq -p /data/out.2.fastq
```

### 4. 二进制包安装（官方 release / 源码编译）

FastUniq 官方**仅发布源码包、无预编译二进制 release**（sourceforge 文件区：FastUniq-1.1.tar.gz / FastUniq-1.0.tar.gz / README.txt）：

```bash
# 下载官方源码包（sha256 9ebf251566d097226393fb5aa9db30a827e60c7a4bd9f6e06022b4af4cee0eae）
wget https://downloads.sourceforge.net/project/fastuniq/FastUniq-1.1.tar.gz -P ~/software/

# 解压编译（用户目录前缀 ~/software/fastuniq-1.1，无需 root；禁 /opt/biosoft、/home/train 教学硬编码）
mkdir -p ~/software/fastuniq-1.1
tar zxf ~/software/FastUniq-1.1.tar.gz -C ~/software/fastuniq-1.1 --strip-components=1
cd ~/software/fastuniq-1.1/source && make
chmod 0755 fastuniq
echo 'export PATH=$PATH:~/software/fastuniq-1.1/source' >> ~/.bashrc
source ~/.bashrc

# 验证安装（无 --version：无参运行打印用法文本）
fastuniq 2>&1 | grep "The input file list of paired"
```

> 依赖：gcc（≥4.0，官方 README 建议）/ make；Debian/Ubuntu `sudo apt-get install -y --no-install-recommends build-essential make`，macOS 装 Xcode Command Line Tools。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；fastuniq 已装时真跑（3 对合成双端 FASTQ 去重 → 剩 2 对）
```

## 版本与来源（2026-09-08 逐渠道核实，禁止编造版本/URL）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| sourceforge 文件区 | ✅ **FastUniq-1.1.tar.gz**（2012-05-13，4.7 MB；另有 1.0 与 README.txt） | 官方**仅源码包**，无预编译二进制 |
| 官方直链 | ✅ `https://downloads.sourceforge.net/project/fastuniq/FastUniq-1.1.tar.gz` | sha256 `9ebf251566d097226393fb5aa9db30a827e60c7a4bd9f6e06022b4af4cee0eae`（bioconda recipe + brew formula 双源一致） |
| bioconda | ✅ **fastuniq=1.1**（linux-64 / osx-64 / linux-aarch64 / osx-arm64） | 官方维护判定第一来源 |
| quay.io/biocontainers | ✅ `1.1--h7b50bb2_2`、`1.1--h470a237_1` | bioconda 自动构建官方镜像 |
| depot.galaxyproject.org | ✅ `fastuniq:1.1--h7b50bb2_2` sif（HTTP 200） | 与 quay tag 互通 |
| Homebrew | ⚠️ homebrew-core **404**；**brewsci/bio 有公式** `fastuniq.rb`（1.1） | 需 `brew tap brewsci/bio`；desc 确为 bio 软件（同名核对通过） |
| nf-core modules | ❌ 404（modules/nf-core/fastuniq） | 无官方 Nextflow module → 流程场景降级 native |
| snakemake-wrappers | ❌ 404（bio/fastuniq） | 无官方 Snakemake wrapper → 流程场景降级 native |
| 官方源码包内容 | source/（C 源码 + Makefile）+ README.txt（+ example/，据 brew formula 引用） | 无内嵌 LICENSE 文件；license 按 bioconda recipe 记 CC-BY |

* 官方渠道（bioconda → quay biocontainers → depot）**齐全** → 判定「官方维护」→ 走官方优先路线，`native/` 不维护 Dockerfile/Apptainer.def（`environment.container_official` 已登记）。
* license：bioconda recipe 记录为 **Creative Commons Attribution License（CC-BY）**（非 GPL）；官方包内未见显式 LICENSE 文件 → 具体许可版本号未核实。

## 历史留存

原教学文档（旧法，仅追溯对照、不推荐）：安装用 `wget sourceforge` + 解压到 `/opt/biosoft/` + `echo PATH=.../FastUniq/source >> ~/.bashrc`（root 级硬编码路径），或 `conda install -c bioconda -c conda-forge fastuniq`；示例在 `/home/train/...` 下以 `ls ../Trimmomatic/illumina.?.fastq > illumina.list` 写列表后 `fastuniq -i illumina.list -o illumina.1.fastq -p illumina.2.fastq`。以上 `/opt/biosoft`、`/home/train` 硬编码与 root 级安装均不保留，命令语义已由本模块「实战示例」（用户前缀 + 官方渠道安装）承接。

## 性能优化约定

* fastuniq 为**单线程**：无多线程参数，驱动不注入 `--threads`（占位接受）；`optimization.per_subcommand_threads.run=1`。

* 内存：FastUniq 将 read pair 载入内存排序去重，内存占用高（大 lane 数据请给足；官方未给精确公式，超内存行为未核实）。

* `--tmpdir` 覆盖 `$TMPDIR` 环境（`optimization.env_vars.TMPDIR`）并作为自动输入列表的落盘位置；输出文件路径由 `-o/-p` 指定。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# fastuniq native Conda 环境配方（native/environment.yml）
# 离线兜底：mamba env create -f native/environment.yml；在线推荐上方 mamba create 直装命令
# 说明：bioconda 官方有 fastuniq=1.1（2026-09 核实）；官方镜像 quay.io/biocontainers/fastuniq 即由 bioconda 本环境构建
name: fastuniq-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - fastuniq=1.1
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **SourceForge**：<https://sourceforge.net/projects/fastuniq/>（文件区：<https://sourceforge.net/projects/fastuniq/files/>）
* **官方源码直链**：<https://downloads.sourceforge.net/project/fastuniq/FastUniq-1.1.tar.gz>（sha256 `9ebf251566d097226393fb5aa9db30a827e60c7a4bd9f6e06022b4af4cee0eae`）
* **Bioconda 页面**：<https://anaconda.org/bioconda/fastuniq>（fastuniq=1.1）
* **Docker**：`docker pull quay.io/biocontainers/fastuniq:1.1--h7b50bb2_2`
* **Singularity**：<https://depot.galaxyproject.org/singularity/fastuniq%3A1.1--h7b50bb2_2>
* **Homebrew（brewsci/bio）**：<https://github.com/brewsci/homebrew-bio/tree/master/Formula/fastuniq.rb>（`brew tap brewsci/bio`）
* **引用**：Xu, H. et al. FastUniq: A Fast De Novo Duplicates Removal Tool for Paired Short Reads. PLoS ONE 7(12): e52249 (2012). <https://doi.org/10.1371/journal.pone.0052249>
