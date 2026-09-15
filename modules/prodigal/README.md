# prodigal 软件模块

> 汇总说明：本 README 记录 prodigal native 实现的用法、环境安装（官方预编译二进制包优先；官方源码编译并列保留）
> 与容器/Conda 链接；官方 nf-core 子模块（modules/nf-core/prodigal）仅登记、不建目录。

***

## native 实现

# prodigal / native — 自包含原核基因预测驱动

Prodigal v2.6.3 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

Prodigal 是一个原核生物基因预测工具，BUSCO 使用它进行原核生物基因组分析。

四个子命令对应 Prodigal 的四种运行模式：

| 子命令       | 命令                                                                                              | 作用                          |
| --------- | ----------------------------------------------------------------------------------------------- | --------------------------- |
| `predict` | `prodigal -p single -i <input> -o <out> [-a <faa>] [-d <fna>] [-s <score>] [-f <fmt>] [-g <code>]` | 单基因组预测（自训练模型，默认）            |
| `meta`    | `prodigal -p meta -i <input> ...`                                                                | 宏基因组预测（不做训练）                |
| `anon`    | `prodigal -p anon -i <input> ...`                                                                | 匿名模式（内置匿名模型）                |
| `train`   | `prodigal -p train -i <input> -t <training_file> -o <out> ...`                                    | 训练模式：导出参数文件（供 -t 复用）        |

> Prodigal 为**单线程**工具，不接受线程参数；`--threads` 仅为接口一致性保留（不注入命令行）。

## 用法

```bash
# 单基因组预测（输出 GFF + 蛋白/核酸序列）
python main.py predict -i genome.fna -o genes.gff -f gff -a proteins.faa -d genes.fna -g 11

# 宏基因组预测（不做自训练）
python main.py meta -i contigs.fna -o meta.gff -f gff

# 训练并导出参数文件，随后复用
python main.py train  -i genome.fna -t genome.training -o train.gbk
python main.py predict -i genome.fna -o genes.gff -f gff -t genome.training

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`--threads` 不注入 Prodigal）。

## 实战示例：细菌基因组基因预测 → GFF3 转换

Prodigal 是原核（细菌/古菌）基因预测的常用首选，也是 BUSCO 原核基因组分析的依赖工具。典型批量用法
（等价能力由 `native/main.py` 的 `predict` 子命令提供，见上「用法」）：

```bash
mkdir -p prodigal
cd prodigal

# 1. 逐基因组预测（-g 11=标准密码子表；-f gff 便于后续处理；同时输出蛋白/核酸序列）
for f in ../genomes/*.fna; do
    sample=$(basename "$f" .fna)
    python ../main.py predict -i "$f" -o "${sample}.gff" -f gff \
        -a "${sample}.faa" -d "${sample}.fna" -g 11 -c
done

# 2. Prodigal 的 GFF 为 GFF2；如需 GFF3 可用脚本转换（历史遗留工作流见 10.md 第十八节 geneMarkS_gff2gff3.pl）
#    本驱动不内置转换脚本；可直接将 .gff/.faa 交给下游注释/比较流程
```

### 参数说明

| 参数          | 说明                                  |
| ----------- | ----------------------------------- |
| `-i`        | 输入基因组/contigs FASTA（核酸）             |
| `-o`        | 基因坐标输出文件（默认 gbk）                    |
| `-a`        | 输出蛋白序列（FASTA）                       |
| `-d`        | 输出基因核酸序列（FASTA）                     |
| `-s`        | 输出起始位点打分明细文件                         |
| `-f`        | 坐标格式：gbk\|gff\|sqn\|sco\|none（默认 gbk） |
| `-g`        | 遗传密码子表（11=标准/细菌，4=古菌）               |
| `-c`        | 视为完整环状/无缺口序列（禁止基因跨两端）               |
| `-m`        | 屏蔽含 N 区域的基因                         |
| `-p`        | 运行模式（single/meta/anon/train，由子命令映射） |
| `-t`        | 训练参数文件（train 输出；predict/meta/anon 复用） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。**官方另提供预编译二进制与源码归档，两条官方路线均保留**。

### 1. 官方预编译二进制包（首选）

官方 GitHub release `v2.6.3` 资产：

```bash
# Linux x86_64
wget https://github.com/hyattpd/Prodigal/releases/download/v2.6.3/prodigal.linux -P ~/software/
mkdir -p ~/software/prodigal-2.6.3/bin
install -m 0755 ~/software/prodigal.linux ~/software/prodigal-2.6.3/bin/prodigal
echo 'export PATH=$HOME/software/prodigal-2.6.3/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
prodigal -v   # 断言

# macOS（Intel）：资产名为 prodigal.osx.10.9.5
# wget https://github.com/hyattpd/Prodigal/releases/download/v2.6.3/prodigal.osx.10.9.5 -P ~/software/
# install -m 0755 ~/software/prodigal.osx.10.9.5 ~/software/prodigal-2.6.3/bin/prodigal
```

> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 走 bioconda 环境 `prodigal`；无 conda 时自动下载上表官方
> 预编译二进制到 `~/software/prodigal-<ver>` 并写 PATH；版本默认 2.6.3，内嵌官方资产 sha256 校验）。
> 用法：`bash native/install.sh --help`。

### 2. 官方源码编译（并列保留）

```bash
wget https://github.com/hyattpd/Prodigal/archive/refs/tags/v2.6.3.tar.gz -P ~/software/
tar zxf ~/software/v2.6.3.tar.gz -C ~/software/
cd ~/software/Prodigal-2.6.3
make install INSTALLDIR=$HOME/software/prodigal-2.6.3/bin   # 官方 Makefile 提供 install 目标
export PATH=$HOME/software/prodigal-2.6.3/bin:$PATH
prodigal -v   # 断言
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n prodigal-native -c conda-forge -c bioconda prodigal=2.6.3
conda activate prodigal-native
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install prodigal
prodigal -v   # 断言（brew 当前 2.6.3，与 meta 登记 2.6.3 一致）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/prodigal:2.6.3--h577a1d6_11
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/prodigal:2.6.3--h577a1d6_11 \
    prodigal -p single -i /data/genome.fna -o /data/genes.gff -f gff
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull prodigal.sif docker://depot.galaxyproject.org/singularity/prodigal:2.6.3--h577a1d6_11
apptainer run -B $PWD:/data -H /data prodigal.sif \
    prodigal -p single -i /data/genome.fna -o /data/genes.gff -f gff
```

## 测试

```bash
bash test/run_test.sh   # predict/meta/anon/train 为 argv 构造验证；已安装 prodigal 时对合成基因组做真实冒烟
```

## 版本

* prodigal 2.6.3（bioconda::prodigal=2.6.3）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/prodigal / depot.galaxyproject.org；本地不再自建容器）
* 官方预编译二进制（prodigal.linux / prodigal.osx.10.9.5）与源码（Prodigal-2.6.3.tar.gz）均保留
* brew homebrew-core 公式 `prodigal` 当前 2.6.3，与 meta 登记一致

## 官方实现登记（不建目录）

* **nf-core**：官方存在子模块 `modules/nf-core/prodigal`（扁平模块，无子目录），`environment.yml` pin
  `bioconda::prodigal=2.6.3`（+ `conda-forge::pigz=2.6`）。执行请用
  `nf modules install nf-core prodigal` 安装到项目自身目录，**不要直接引用本仓库示例**；缺失时用本模块 `native/` 兜底。
* **snakemake-wrappers**：`bio/prodigal` 不存在（2026-09 核实 `environment.yaml` / `wrapper.py` 均 404），Snakemake 场景请在容器/PATH 内直调 `prodigal`。

## 容器与 Conda 链接

* **GitHub**：https://github.com/hyattpd/Prodigal
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/prodigal/overview>
* **Docker**：`docker pull quay.io/biocontainers/prodigal:2.6.3--h577a1d6_11`
* **Singularity**：<https://depot.galaxyproject.org/singularity/prodigal%3A2.6.3--h577a1d6_11>
* **Homebrew**：`brew install prodigal`
* **官方预编译二进制**：<https://github.com/hyattpd/Prodigal/releases/tag/v2.6.3>
* 安装方式（本地）：`mamba create -n prodigal -c conda-forge -c bioconda prodigal=2.6.3`
