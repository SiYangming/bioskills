# cufflinks 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 
>⚠️ **淘汰技术（deprecated，2026-09 登记）**：Cufflinks 属于 Tuxedo 套件（TopHat-Cufflinks 流程），
> 最后稳定版为 **2.2.1**（官方约 2014 年后停更）。
> 建议改用 **StringTie**（转录本组装）+ **DESeq2 / edgeR**（差异表达）。
> 本模块**只做录入与命令构造**，仅供历史复现；**不产出自建容器配方**（deprecated）。

***

## native 实现

# cufflinks / native — 自包含 Tuxedo 套件命令构造驱动

Cufflinks 套件的本地实现（`source_type: custom`、`type: native`；⚠️ 淘汰技术）。

## 功能

**Cufflinks** 可以根据比对结果组装转录本，即使没有参考注释也能从头组装。

**cuffmerge** 整合多个GTF文件：当有多个样品时，需要将每个样品的组装结果整合为一个统一的转录组注释文件。

**cuffcompare** GTF比较：cuffcompare 用于将 Cufflinks 生成的 GTF 文件与参考注释 GTF 进行比较，评估组装质量。

| 子命令          | 命令                                                                                          | 作用                |
| ------------ | ------------------------------------------------------------------------------------------- | ----------------- |
| `cufflinks`  | `cufflinks [<bam>] -o <dir> -p N [-G <ref.gtf>] [-M <mask>] [-b <seq.fa>] [-u] [-L <label>]` | 转录本组装             |
| `cuffmerge`  | `cuffmerge -o <dir> -p N [-g <ref.gtf>] [-s <seq.fa>] <gtf_list>`                            | 多样本 GTF 合并        |
| `cuffcompare`| `cuffcompare -o <prefix> [-r <ref.gtf>] [-s <seq.fa>] [-g <gtf>] <gtf>`                      | 与参考注释比较           |
| `cuffdiff`   | `cuffdiff [--no-update-check] -o <dir> -p N [-L <labels>] [-b <seq.fa>] [-u <gtf>] <samples>`| 差异表达分析            |
| `cuffquant`  | `cuffquant -o <dir> -p N [-b <seq.fa>] [-u <gtf>] <bam>`                                     | 样本表达量定量           |
| `cuffnorm`   | `cuffnorm -o <dir> -p N [-L <labels>] <samples>`                                             | 表达量归一化            |

> `-p N` 由本驱动自动注入：线程优先级 `--threads > per_subcommand_threads > default_cpus`。

## 用法

```bash
# 转录本组装——0
python main.py cufflinks sample.sorted.bam -o sample -p 8 -b genome.fasta -u -L sample

# 多样本合并
python main.py cuffmerge gtf_list.txt -o ./cuffmerge -p 4 -s genome.fasta

# 与参考比较
python main.py cuffcompare A/transcripts.gtf -r genome.gtf -s genome.fasta -o cmp

# 差异表达
python main.py cuffdiff samples.txt --no-update-check -o cuffdiff_out -p 8 \
    -L control,treatment -b genome.fasta -u genome.gtf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：批量组装 → 合并 → 比较

```bash
mkdir -p cufflinks && cd cufflinks

# 1) 逐样本转录组组装（-L 样本标签）
for i in `ls ../hisat2/*.bam`
do
    sample=$(basename $i .bam)
    cufflinks -o $sample -p 4 -b ../genome.fasta -u -L $sample $i
done

# 2) 生成 GTF 列表并合并（cuffmerge）
ls */transcripts.gtf > ../cuffmerge/assembly_GTF_list.txt
cd ../cuffmerge
cuffmerge -o ./ -p 4 -s ../genome.fasta assembly_GTF_list.txt

# 3) 与参考注释比较（cuffcompare，class_code：= / c / j / u ...）
cd ../cuffcompare
cuffcompare -r ../genome.gtf -s ../genome.fasta ../cufflinks/A/transcripts.gtf
```

> 上述命令与 `native/main.py` 的 `cufflinks` / `cuffmerge` / `cuffcompare` 子命令一一对应（见上「用法」）。

### class_code 含义（cuffcompare 输出）

| 代码  | 含义                        |
| --- | ------------------------- |
| `=` | 完全匹配参考转录本的所有 intron       |
| `c` | 被包含在参考转录本中                |
| `o` | 外显子水平重叠                   |
| `x` | 与参考转录本反义链重叠               |
| `u` | 基因间区，可能是新基因               |
| `j` | 至少有一个共同剪接位点，可能是新转录本       |
| `e` | 单外显子，与参考 intron 重叠，可能是 pre-mRNA 片段 |
| `i` | 完全在参考 intron 中             |

## 环境安装（淘汰技术；官方预编译二进制包优先）

> ⚠️ Cufflinks 已淘汰，官方最后稳定版 2.2.1；以下仅供历史复现。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n cufflinks-native -c conda-forge -c bioconda cufflinks=2.2.1
conda activate cufflinks-native
cufflinks --version   # 断言
```

> brew：homebrew-core 与 brewsci/bio 均无 `cufflinks`（2026-09 核实 404），故不提供 brew 块。

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `cufflinks`，
> 无 conda 时下载官网预编译二进制到 `~/software/cufflinks-<ver>` 并写 PATH；默认版本 2.2.1，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方历史镜像）

```bash
docker pull quay.io/biocontainers/cufflinks:2.2.1--py27_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/cufflinks:2.2.1--py27_1 cufflinks \
    /data/sample.sorted.bam -o /data/sample -p 8 -b /data/genome.fasta -u -L sample
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 有预构建 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull cufflinks.sif docker://depot.galaxyproject.org/singularity/cufflinks:2.2.1--py27_1
apptainer run -B $PWD:/data -H /data cufflinks.sif cufflinks \
    /data/sample.sorted.bam -o /data/sample -p 8 -u -L sample
```

### 4. 官方预编译二进制包（首选）

* **官网**：<http://cole-trapnell-lab.github.io/cufflinks/>

* **二进制**：`cufflinks-2.2.1.Linux_x86_64.tar.gz` / `cufflinks-2.2.1.OSX_x86_64.tar.gz`
  （<http://cole-trapnell-lab.github.io/cufflinks/assets/downloads/>；sha256 Linux `d891c58e…d7e23`、OSX `98a78cdf…00c6`）

```bash
wget http://cole-trapnell-lab.github.io/cufflinks/assets/downloads/cufflinks-2.2.1.Linux_x86_64.tar.gz -P ~/software/
tar zxf ~/software/cufflinks-2.2.1.Linux_x86_64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/cufflinks-2.2.1.Linux_x86_64/' >> ~/.bashrc
source ~/.bashrc
cufflinks --version   # 断言
```

### 5. 官方源码编译（并列保留）

* **GitHub**：<https://github.com/cole-trapnell-lab/cufflinks>（源码需 samtools / boost / eigen 等依赖，编译较繁琐；官方主要分发预编译二进制）

## 测试

```bash
bash test/run_test.sh   # 六个子命令为 argv 构造验证；未安装时跳过真实冒烟
```

## 版本

* cufflinks 2.2.1（最后稳定版；bioconda::cufflinks=2.2.1，license=Boost Software License 1.0）

* 构建路线：历史遗留渠道（quay.io/biocontainers/cufflinks / depot.galaxyproject.org 自动构建历史镜像；官方预编译二进制）

* ⚠️ 已淘汰：不产出自建 Dockerfile/Apptainer.def；nf-core / snakemake-wrappers 均无官方模块（2026-09 核实 404）

## 容器与 Conda 链接

* **官网**：http://cole-trapnell-lab.github.io/cufflinks/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/cufflinks/overview>

* **Docker**：`docker pull quay.io/biocontainers/cufflinks:2.2.1--py27_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/cufflinks%3A2.2.1--py27_1>

* 安装方式（本地）：`mamba create -n cufflinks -c conda-forge -c bioconda cufflinks=2.2.1`
