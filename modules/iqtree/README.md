# iqtree 软件模块

> 汇总说明：本 README 说明 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# iqtree / native — 自包含最大似然建树驱动

IQ-TREE 的本地自包含实现（`source_type: custom`、`type: native`；本模块登记 v1.6.12）。

## 功能

**IQ-TREE**（IQTREE）是一款高效的最大似然系统发育树构建工具，支持合并分析（合并多个基因），内置多种替代模型。

| 子命令     | 命令                                                                                                                     | 作用                             |
| ------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `ml`    | `iqtree -s <aln> -m MFP [-bb <n>] [-alrt <n>] [-t <tree>] -nt N [-pre <prefix>]`                                        | ML 建树（ModelFinder Plus + UFBoot + aLRT） |
| `model` | `iqtree -s <aln> -m MF [-t <tree>] -nt N [-pre <prefix>]`                                                               | 仅模型选择（ModelFinder，不建树）          |

> ⚠️ IQ-TREE **v1.x 的线程参数为 `-nt`**（v2/v3 改为 `-T`）。本模块登记 1.6.12，故统一注入 `-nt`；与 nf-core 模块（pin 3.1.3）迁移时须核对。

## 用法

```bash
# CLI 直跑
python main.py ml allSingleCopyOrthologsAlign.Protein.phy -m MFP -bb 1000 -alrt 1000 --threads 8 -pre out_protein
python main.py ml allSingleCopyOrthologsAlign.Protein.phy -m LG+G4 -bb 1000 --threads 8
python main.py model allSingleCopyOrthologsAlign.Protein.phy --threads 4 -pre modelfinder

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：IQ-TREE 构建物种树

IQ-TREE 支持自动模型选择（ModelFinder）、超快 bootstrap（UFBoot）与近似似然比检验（aLRT），比 classic RAxML 快数倍。等价能力由 `native/main.py` 的 `ml` / `model` 子命令提供（见上「用法」）。

```bash
# 1. 基本用法：自动模型选择 + 超快 bootstrap + aLRT
iqtree -s allSingleCopyOrthologsAlign.Protein.phy -m MFP -bb 1000 -alrt 1000 -T 8

# 2. 使用指定模型（如 LG+G4）
iqtree -s allSingleCopyOrthologsAlign.Protein.phy -m LG+G4 -bb 1000 -T 8

# 3. 密码子模型
iqtree -s allSingleCopyOrthologsAlign.Codon.phy -m GTR+G -bb 1000 -T 8

# 输出文件：<prefix>.treefile（最佳树）/ <prefix>.iqtree（详细报告）/ <prefix>.log（日志）
```

### 参数说明

| 参数                 | 说明                                     |
| ------------------ | -------------------------------------- |
| `-s`               | 输入多序列比对（PHYLIP/FASTA）                   |
| `-m MFP`           | ModelFinder Plus：自动选模型 + 建树             |
| `-m MF`            | 仅做模型选择（不建树）                            |
| `-m LG+G4` / `GTR+G` | 显式指定进化模型                              |
| `-bb`              | 超快 bootstrap（UFBoot）重复次数               |
| `-alrt`            | 近似似然比检验重复次数                            |
| `-nt`              | 线程数（v1.6.12；v2/v3 为 `-T`）              |
| `-pre`             | 输出文件前缀                                 |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；官方另提供**预编译包**与**源码**，两条官方路线均保留。

### 1. 官方预编译二进制包（首选）

```bash
# Linux x86_64（GitHub release v1.6.12）
wget https://github.com/Cibiv/IQ-TREE/releases/download/v1.6.12/iqtree-1.6.12-Linux.tar.gz -P ~/software/
tar zxf ~/software/iqtree-1.6.12-Linux.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/iqtree-1.6.12-Linux/bin/' >> ~/.bashrc && source ~/.bashrc
iqtree --version   # 断言

# macOS（x86_64；Apple Silicon 需 Rosetta，建议改用下方 conda 路线）
wget https://github.com/Cibiv/IQ-TREE/releases/download/v1.6.12/iqtree-1.6.12-MacOSX.zip -P ~/software/
unzip -q ~/software/iqtree-1.6.12-MacOSX.zip -d ~/software/
echo 'export PATH=$PATH:~/software/iqtree-1.6.12-MacOSX/bin/' >> ~/.bashrc && source ~/.bashrc
```

> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `iqtree`，无 conda 时下载官方预编译包到 `~/software/iqtree-1.6.12` 并写 PATH；版本默认 1.6.12，与下方 `software_versions` 对齐，内嵌官方包 sha256。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档（tag v1.6.12；cmake 构建；需 gcc + cmake + eigen3）
wget https://github.com/Cibiv/IQ-TREE/archive/refs/tags/v1.6.12.tar.gz -P ~/software/
tar zxf ~/software/v1.6.12.tar.gz -C ~/software/
cd ~/software/IQ-TREE-1.6.12
mkdir build && cd build
cmake -DIQTREE_FLAGS=omp .. && make -j4
./iqtree --version   # 断言（cmake 产物为 iqtree 可执行）
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n iqtree-native -c conda-forge -c bioconda iqtree=1.6.12
conda activate iqtree-native
iqtree --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install iqtree
iqtree --version         # 断言（brew 当前 1.6.12，与 meta 登记 1.6.12 一致，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/iqtree:1.6.12--he513fc3_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/iqtree:1.6.12--he513fc3_0 \
    -s allSingleCopyOrthologsAlign.Protein.phy -m MFP -bb 1000 -nt 8 -pre out_protein
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull iqtree.sif docker://depot.galaxyproject.org/singularity/iqtree:1.6.12--he513fc3_0
apptainer run -B $PWD:/data -H /data iqtree.sif \
    -s /data/allSingleCopyOrthologsAlign.Protein.phy -m MFP -bb 1000 -nt 8 -pre /data/out_protein
```

## 官方实现（nf-core）

* **nf-core**：官方扁平模块 `nf-core/iqtree` 存在（pin `bioconda::iqtree=3.1.3`，2026-07 起由 v2 升 v3，2026-09 在线核实；`modules/nf-core/iqtree/{main.nf,meta.yml,environment.yml}`）。执行前请 `nf-core modules install iqtree` 安装到项目自身目录，不要直接引用本仓库示例 `main.nf`；缺失时用本模块 `native/main.py` 兜底。
* **snakemake-wrappers**：官方无 `bio/iqtree`（2026-09 在线核实 404）；Snakemake 场景请直接调用 native。

> ⚠️ nf-core 模块 pin 的 IQ-TREE 3.1.3 与 native 登记的 1.6.12 差异大（线程参数 `-nt` → `-T`、模型语法有变），跨实现迁移须核对。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（避免与系统 v2/v3 的 -nt/-T 差异冲突）
```

## 版本

* iqtree 1.6.12（bioconda::iqtree=1.6.12；官方 GitHub release v1.6.12）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/iqtree / depot.galaxyproject.org；本地不再自建容器）

* 官方层 nf-core：扁平模块 `nf-core/iqtree` pin bioconda::iqtree=3.1.3（2026-07 升 v3），与 native 1.6.12 差异大（`-nt`→`-T`）；snakemake-wrappers 无 iqtree（2026-09 核实 404）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/iqtree/overview>

* **Docker**：`docker pull quay.io/biocontainers/iqtree:1.6.12--he513fc3_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/iqtree%3A1.6.12--he513fc3_0>

* 安装方式（本地）：`mamba create -n iqtree -c conda-forge -c bioconda iqtree=1.6.12`（或 `bash native/install.sh`）

* **官网**：https://iqtree.github.io/

* **Github**：https://github.com/Cibiv/IQ-TREE
