# mirdeep2 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 来源：`docs/10.md` 第十九节（非编码RNA预测）——miRNA 预测工具 miRDeep / miRDeep2。
> 命名说明：文档写作「miRDeep / miRDeep2」，本模块按 **bioconda / nf-core 统一规范名 `mirdeep2`** 建目录。

***

## native 实现

# mirdeep2 / native — 自包含 miRNA 发现与定量驱动

miRDeep2 的本地自包含实现（`source_type: custom`、`type: native`）。

miRDeep2 从深度测序 reads 中发现已知与新的 miRNA 基因（Friedländer et al., *Nat Biotechnol* 2012；miRDeep 原始算法 2008）。完整链路：

1. `mapper.pl`：折叠 reads（`-m`）、裁剪接头（`-k`）、按长度过滤（`-l`），并用 bowtie 比对到基因组，输出折叠 reads（`-s`）与 `.arf` 比对（`-t`）；
2. `miRDeep2.pl`：核心算法，识别 precursor/hairpin，输出 `results.html` / `results.csv`；
3. `quantifier.pl`：对已知 miRBase precursor 快速定量，输出 `miRNA_expressed.csv`。

## 功能

| 子命令         | 命令                                                                                                              | 作用                       |
| ----------- | ------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `mapper`    | `mapper.pl <reads> -c -j -k <adapter> -l 18 -m -p <index> -s <out> -t <arf> -v`                                | 折叠 reads + bowtie 比对到基因组  |
| `mirdeep`   | `miRDeep2.pl <reads> <genome> <arf> <mature> <other_mature> <hairpin> -t <species>`                            | 识别已知 / 新 miRNA（核心算法）     |
| `quantifier`| `quantifier.pl -p <hairpin> -m <mature> -r <reads> -t <code> -y <len>`                                          | 对已知 miRBase precursor 定量 |

> 以上命令行依据上游 `TUTORIAL.md` 整理。miRDeep2 脚本链路无并行参数；`--threads` 仅记录，不注入命令行。

## 用法

```bash
# CLI 直跑（对应上游教程 4 步）
python main.py mapper reads.fa -c -j -k TCGTATGCCGTCTTCTGCTTGT -l 18 -m \
    -p cel_cluster -s reads_collapsed.fa -t reads_collapsed_vs_genome.arf -v
python main.py quantifier -p precursors_ref_this_species.fa -m mature_ref_this_species.fa \
    -r reads_collapsed.fa -t cel -y 16_19
python main.py mirdeep reads_collapsed.fa cel_cluster.fa reads_collapsed_vs_genome.arf \
    mature_ref_this_species.fa mature_ref_other_species.fa precursors_ref_this_species.fa \
    -t C.elegans

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

参数（节选）：

| 子命令          | 参数                | 说明                                                 |
| ------------ | ----------------- | -------------------------------------------------- |
| `mapper`     | `-c` / `-e`       | 输入为 FASTA / FASTQ                                   |
| `mapper`     | `-j` / `-k` / `-l` | 剔除非规范字符 / 裁剪 3' 接头 / 最短长度                           |
| `mapper`     | `-m` / `-p`       | 折叠 reads / bowtie 基因组索引前缀                            |
| `mapper`     | `-s` / `-t`       | 折叠 reads 输出 / `.arf` 比对输出                           |
| `mirdeep`    | 6 个位置参数           | 顺序：reads genome arf mature other_mature hairpin    |
| `mirdeep`    | `-t` / `-d`       | 物种名（如 C.elegans）/ 断点续跑                              |
| `quantifier` | `-p` / `-m` / `-r` | precursor 参考 / mature 参考 / 折叠 reads（注意本子命令的字母含义）  |
| `quantifier` | `-t` / `-y`       | 3 字母物种代码 / mature 长度范围                              |

## 实战示例：已知 / 新 miRNA 发现（前端到后端）

```bash
mkdir -p mirdeep2_out && cd mirdeep2_out

# 1) 建索引 + 折叠并比对 reads（bowtie-build 需先安装 bowtie）
bowtie-build genome.fa genome
mapper.pl reads.fa -c -j -k TCGTATGCCGTCTTCTGCTTGT -l 18 -m \
    -p genome -s reads_collapsed.fa -t reads_collapsed_vs_genome.arf -v

# 2) 对已知 miRBase precursor 定量
quantifier.pl -p precursors_ref_this_species.fa -m mature_ref_this_species.fa \
    -r reads_collapsed.fa -t hsa -y 16_19

# 3) 已知 + 新 miRNA 识别
miRDeep2.pl reads_collapsed.fa genome.fa reads_collapsed_vs_genome.arf \
    mature_ref_this_species.fa mature_ref_other_species.fa \
    precursors_ref_this_species.fa -t H.sapiens 2> report.log
# 浏览 results.html
```

> 上述命令与 `native/main.py` 的 `mapper` / `quantifier` / `mirdeep` 子命令一一对应（见上「用法」）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n mirdeep2-native -c conda-forge -c bioconda mirdeep2=2.0.1.3
conda activate mirdeep2-native
mapper.pl -h 2>&1 | head -1   # 断言
```

> brew：homebrew-core 与 brewsci/bio 均无 `mirdeep2`（2026-09 核实 404），故不提供 brew 块。

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `mirdeep2`，
> 无 conda 时下载官方 GitHub 源码归档 `v0.1.3` 部署 Perl 脚本并提示外部依赖；默认版本 2.0.1.3，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mirdeep2:2.0.1.3--hdfd78af_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mirdeep2:2.0.1.3--hdfd78af_2 mapper.pl \
    /data/reads.fa -c -j -k TCGTATGCCGTCTTCTGCTTGT -l 18 -m -p cel_cluster \
    -s /data/reads_collapsed.fa -t /data/reads_collapsed_vs_genome.arf -v
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull mirdeep2.sif docker://depot.galaxyproject.org/singularity/mirdeep2:2.0.1.3--hdfd78af_2
apptainer run -B $PWD:/data -H /data mirdeep2.sif mapper.pl \
    /data/reads.fa -c -l 18 -m -p cel_cluster -s /data/reads_collapsed.fa -t /data/reads.arf -v
```

### 4. 官方源码安装（并列保留）

* **GitHub**：<https://github.com/rajewsky-lab/mirdeep2>

* **源码归档**：<https://github.com/rajewsky-lab/mirdeep2/archive/v0.1.3.tar.gz>（tag v0.1.3 = 2.0.1.3，sha256 `d6bac420…fa8d2f`）

```bash
# 方式一：上游自带安装脚本（交互式，会尝试下载 bowtie/ViennaRNA/randfold 等并写入 shell 配置）
wget https://github.com/rajewsky-lab/mirdeep2/archive/v0.1.3.tar.gz -P ~/software/
tar zxf ~/software/v0.1.3.tar.gz -C ~/software/
cd ~/software/mirdeep2-0.1.3
perl install.pl

# 方式二：手工部署脚本并自备依赖（bowtie / ViennaRNA(RNAfold) / randfold / perl PDF::API2 等）
export PATH=$PWD/src:$PATH
miRDeep2.pl -h 2>&1 | head -1   # 断言
```

## 测试

```bash
bash test/run_test.sh   # mapper/quantifier/mirdeep 为 argv 构造验证；未安装时跳过真实冒烟
```

## 版本

* miRDeep2 2.0.1.3（bioconda::mirdeep2=2.0.1.3；上游 git tag v0.1.3）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/mirdeep2 / depot.galaxyproject.org；本地不再自建容器）

* 与 nf-core 子模块 mirdeep2/mapper + mirdeep2/mirdeep2 的 bioconda pin（2.0.1.2）相差一个 patch

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/mirdeep2/overview>

* **Docker**：`docker pull quay.io/biocontainers/mirdeep2:2.0.1.3--hdfd78af_2`

* **Singularity**：<https://depot.galaxyproject.org/singularity/mirdeep2%3A2.0.1.3--hdfd78af_2>

* 安装方式（本地）：`mamba create -n mirdeep2 -c conda-forge -c bioconda mirdeep2=2.0.1.3`
