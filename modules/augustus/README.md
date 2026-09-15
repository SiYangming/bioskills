# augustus 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# augustus / native — 自包含从头基因预测驱动

AUGUSTUS 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

AUGUSTUS 是一个基于隐马尔可夫模型（HMM）的从头基因预测工具。

六个子命令覆盖「预测 → 训练 → 优化 → 格式转换 → hints」链路：

| 子命令           | 命令（上游）                                                                       | 作用                                   |
| ------------- | ---------------------------------------------------------------------------- | ------------------------------------ |
| `predict`     | `augustus --species=<s> [--hintsfile=<f>] [--CRF=1] <genome.fasta>`           | 用训练好的物种参数预测基因结构（GFF 写 stdout）         |
| `etraining`   | `etraining --species=<s> [--CRF=1] <genes.gb>`                                | 用 GenBank 训练集训练物种参数                   |
| `optimize`    | `optimize_augustus.pl --species=<s> --rounds=N --cpus=N --kfold=N <genes.gb.train>` | 循环训练优化 HMM 参数（自动注入 `--cpus`）          |
| `new_species` | `new_species.pl --species=<s>`                                                | 为新物种创建参数目录                           |
| `gff2gb`      | `gff2gbSmallDNA.pl <gff> <genome.fasta> <flank> <out.gb>`                     | GFF3 → GenBank 训练集                   |
| `bam2hints`   | `bam2hints [--intronsonly] --in=<bam> --out=<hints.gff>`                      | RNA-seq 比对 BAM → hints GFF            |

> 二进制/脚本按 `AUGUSTUS_BIN_PATH` / `AUGUSTUS_SCRIPTS_PATH` / `~/software/augustus*/` / `PATH` 惰性解析；
> `JAVA_OPTS`（`optimization.env_vars.JAVA_OPTS: -Xmx4g`）透传给运行期。

## 用法

```bash
# CLI 直跑
python main.py predict genome.fasta --species=malassezia_sympodialis --hintsfile=hints.gff -o aug.gff
python main.py etraining genes.gb --species=malassezia_sympodialis --crf 1
python main.py optimize genes.gb.train --species=malassezia_sympodialis --rounds 5 --kfold 8 --threads 8
python main.py new_species --species=malassezia_sympodialis
python main.py gff2gb ati.filter2.gff3 genome.fasta --flank 100 -o genes.raw.gb
python main.py bam2hints rnaseq.sort.bam --intronsonly -o hints.gff

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`optimize` 注入 `--cpus`）。

## 实战示例：训练物种参数 → 制作 hints → 基因预测

AUGUSTUS 基于 HMM，训练集越充分预测越准；`optimize_augustus.pl` 的准确性检测值通常在 40-60%，
CRF training 可进一步提高准确性。以下为典型链路；等价能力由 `native/main.py` 的
`gff2gb` / `new_species` / `etraining` / `optimize` / `bam2hints` / `predict` 子命令提供（见上「用法」）。

```bash
mkdir -p augustus && cd augustus

# 1. GFF3 -> GenBank 训练集（提取基因前后各 100bp flank）
gff2gbSmallDNA.pl ../ati.filter2.gff3 ../genome.fasta 100 genes.raw.gb

# 2. 建立新物种参数并训练（先剔除坏基因，再分割训练/测试集）
new_species.pl --species=malassezia_sympodialis
etraining --species=malassezia_sympodialis --stopCodonExcludedFromCDS=false genes.raw.gb 2> train.err
cat train.err | perl -pe 's/.*in sequence (\S+): .*/$1/' > badgenes.lst
filterGenes.pl badgenes.lst genes.raw.gb > genes.gb
randomSplit.pl genes.gb 200

# 3. 第一次 training + 优化参数（--cpus 并行，--kfold 折）
etraining --species=malassezia_sympodialis genes.gb.train
optimize_augustus.pl --species=malassezia_sympodialis --rounds=5 --cpus=8 --kfold=8 \
    --onlytrain=genes.gb.train.test genes.gb.train.train > optimize.out 2> /dev/null
etraining --species=malassezia_sympodialis genes.gb.train        # 第二次 training

# 4. RNA-seq 制作 hints
samtools merge -@ 8 rnaseq.bam ../hisat2/*.sam
samtools sort -@ 8 -O bam -o rnaseq.sort.bam rnaseq.bam
bam2hints --intronsonly --in=rnaseq.sort.bam --out=hints.gff

# 5. 结合 hints 预测
augustus --species=malassezia_sympodialis --hintsfile=hints.gff genome.fasta > augustus.out
# 等价（native 驱动）：python main.py predict genome.fasta --species=malassezia_sympodialis \
#     --hintsfile=hints.gff -o augustus.gff
```

参数说明：

| 参数                                           | 说明                   |
| -------------------------------------------- | -------------------- |
| `--species=<s>`                              | 指定训练好的物种参数           |
| `--hintsfile=<f>`                            | 指定 RNA-seq hints 文件  |
| `--allow_hinted_splicesites=atac`            | 允许非标准剪接位点            |
| `--alternatives-from-evidence=true`          | 从证据中提取可变剪接异构体        |
| `--CRF=1`                                    | 使用条件随机场              |
| `--stopCodonExcludedFromCDS=false`           | training 时允许终止密码子参与 |

> 桥接句：上表的等价能力由 `native/main.py` 的 `predict` / `etraining` / `optimize` / `new_species` / `gff2gb` / `bam2hints` 子命令提供，先 CLI 直跑、再按需接入 Agent。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。
> 已核实：AUGUSTUS 官方**不提供预编译二进制包**（上游 `bioinf.uni-greifswald.de/augustus/binaries/augustus-3.4.0.tar.gz` 与 GitHub release 均为**源码**），官方路线为「源码编译」+「官方镜像/conda」，故本节按官方镜像路线编排，源码编译并列保留。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n augustus -c conda-forge -c bioconda augustus=3.4.0   # 跨平台，含编译好的 bam2hints
conda activate augustus
augustus --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install augustus
augustus --version   # 断言（brew 当前 3.5.0，与 meta 登记 3.4.0 略有差异，以 formula 为准）
```

> 一键安装：`bash native/install.sh`（有 conda/mamba 走 bioconda augustus=3.4.0，否则走官方源码编译）。

> 💡 **提示**：conda 安装的 AUGUSTUS 已包含大部分物种配置文件。配置文件路径可通过 `echo $AUGUSTUS_CONFIG_PATH` 查看，若未自动设置，可手动配置：
>
> ```bash
> # 查找配置文件路径（根据 conda 环境路径调整）
> export AUGUSTUS_CONFIG_PATH=$(dirname $(which augustus))/../config
> ```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/augustus:3.4.0--pl5321hf46c7bb_8
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/augustus:3.4.0--pl5321hf46c7bb_8 \
    augustus --species=human /data/genome.fasta > /data/augustus.gff
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull augustus.sif docker://depot.galaxyproject.org/singularity/augustus:3.4.0--pl5321hf46c7bb_8
apptainer run -B $PWD:/data -H /data augustus.sif \
    augustus --species=human /data/genome.fasta > /data/augustus.gff
```

### 4. 官方源码编译（并列保留）

> ⚠️ 需先准备训练/hints 依赖：`htslib 1.10`、`boost_1_64_0`、`bamtools`（编译 `bam2hints` 用）。
> 若仅用 conda/镜像路线（已含编译好的 `bam2hints`），可跳过本节。

需要先安装 bamtools 依赖（用于编译 bam2hints 程序）。

bamtools 是一个用于处理 BAM 格式文件的 C++ 工具库。

```bash
# 官方源码（官网 binaries/ 或 GitHub release v3.4.0）
curl -fsSL -o augustus-3.4.0.tar.gz \
    https://github.com/Gaius-Augustus/Augustus/releases/download/v3.4.0/augustus-3.4.0.tar.gz
tar zxf augustus-3.4.0.tar.gz -C ~/software/
cd ~/software/augustus-3.4.0
# 指定依赖（官方 Makefile 变量）
make clean
# perl -p -i -e 's#^SAMTOOLS=.*#SAMTOOLS=/path/to/samtools-0.1.19/#; s#^HTSLIB=.*#HTSLIB=/path/to/htslib-1.10/lib/#;' auxprogs/bam2wig/Makefile
CPLUS_INCLUDE_PATH=/path/to/boost_1_64_0/include make -j 4
chmod 777 config/species
echo 'export PATH=$PATH:'"$PWD"'/bin:'"$PWD"'/scripts' >> ~/.bashrc
echo "export AUGUSTUS_CONFIG_PATH=$PWD/config/" >> ~/.bashrc
source ~/.bashrc
augustus --version   # 断言
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证；augustus 已安装时额外做版本冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/augustus/overview>

* **Docker**：`docker pull quay.io/biocontainers/augustus:3.4.0--pl5321hf46c7bb_8`

* **Singularity**：<https://depot.galaxyproject.org/singularity/augustus%3A3.4.0--pl5321hf46c7bb_8>

* **官方源码**：<http://bioinf.uni-greifswald.de/augustus/binaries/augustus-3.4.0.tar.gz>（GitHub 镜像：<https://github.com/Gaius-Augustus/Augustus/releases/tag/v3.4.0>）

* 安装方式（本地）：`mamba create -n augustus -c conda-forge -c bioconda augustus=3.4.0`

## 版本

* AUGUSTUS 3.4.0（官方源码 augustus-3.4.0.tar.gz；官方镜像/conda augustus=3.4.0，tag 3.4.0--pl5321hf46c7bb_8）

* brew homebrew-core：augustus 3.5.0（与 meta 登记 3.4.0 略有差异，以 formula 为准）

* 构建路线：官方源码编译（需 htslib 1.10 / boost_1_64_0 / bamtools）+ 官方 biocontainer/quay/depot（本地不再自建容器）

* nf-core / snakemake-wrappers：官方无独立模块 / 无 wrapper（2026-09-11 抓取 404；nf-core 仅 braker3 覆盖整链）
