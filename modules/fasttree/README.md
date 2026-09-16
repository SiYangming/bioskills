# fasttree 软件模块

> 汇总说明：本 README 说明 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# fasttree / native — 自包含超快建树驱动

FastTree 的本地自包含实现（`source_type: custom`、`type: native`；单一 C 源文件编译，单线程）。

## 功能

**FastTree** 是一款超快的系统发育树构建工具，特别适合大规模数据集（如数千条序列）。它使用近似最大似然法，速度比 RAxML 快 100-1000 倍，同时保持较高的准确性。

| 子命令         | 命令                                                                     | 作用                        |
| ----------- | ---------------------------------------------------------------------- | ------------------------- |
| `protein`   | `FastTree [-out <tree>] <aln>`（默认 JTT+CAT）                             | 蛋白比对建树                    |
| `nucleotide`| `FastTree -nt [-gtr] [-out <tree>] <aln>`                              | 核酸比对建树（GTR+CAT）           |
| `boot`      | `FastTree [-nt] [-gtr] -boot <n> [-out <tree>] <aln>`（SH-like 重采样）    | 计算局部支持度                   |

FastTree **单线程**，`--threads` 仅作统一接口与上层调度参考，不注入命令行。

## 用法

```bash
# CLI 直跑
python main.py protein allSingleCopyOrthologsAlign.Protein.fasta -out tree.nwk
python main.py nucleotide allSingleCopyOrthologsAlign.Codon.fasta --gtr -out tree.nwk
python main.py boot allSingleCopyOrthologsAlign.Protein.fasta -boot 1000 -out tree.nwk

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：FastTree 快速构建物种树

FastTree 使用近似最大似然法，速度比 RAxML 快 100-1000 倍，特别适合大规模数据集（数千条序列）。以下为典型用法；等价能力由 `native/main.py` 的 `protein` / `nucleotide` / `boot` 子命令提供（见上「用法」）。

```bash
# 1. 蛋白质序列建树（默认 JTT+CAT 模型）
FastTree allSingleCopyOrthologsAlign.Protein.fasta > tree.nwk

# 2. 核酸序列建树（GTR+CAT 模型）
FastTree -gtr -nt allSingleCopyOrthologsAlign.Codon.fasta > tree.nwk

# 3. 计算 bootstrap 值（1000 次）
FastTree -boot 1000 allSingleCopyOrthologsAlign.Protein.fasta > tree.nwk

# 4. 使用 gamma 模型（更准确但更慢）
FastTree -gamma allSingleCopyOrthologsAlign.Protein.fasta > tree.nwk
```

### 参数说明

| 参数        | 说明                         |
| --------- | -------------------------- |
| `-gtr`    | 使用 GTR 模型（核酸）              |
| `-nt`     | 输入是核酸序列                    |
| `-gamma`  | 使用 gamma 分布建模位点异质性         |
| `-boot`   | 局部支持度（SH-like）重采样次数        |
| `-out`    | 输出 Newick 树文件（缺省 stdout）   |
| `-log`    | 中间树/参数/模型详情日志              |
| `-quiet`  | 抑制进度/统计输出（默认开启）            |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；官方另仅提供**源码**（无官方预编译二进制），故官方源码编译路线一并登记。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n fasttree-native -c conda-forge -c bioconda fasttree=2.1.11
conda activate fasttree-native
FastTree -help   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install fasttree
FastTree -help           # 断言（brew 当前 2.1.11，与 meta 登记 2.1.11 一致，以 formula 为准）
```

> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `fasttree`，无 conda 时下载官方源码 `FastTree-2.1.11.c` 用 gcc 编译 FastTree + FastTree_d 到 `~/software/FastTree-2.1.11`；版本默认 2.1.11，与下方 `software_versions` 对齐，内嵌官方源码 sha256。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/fasttree:2.1.11--h7b50bb2_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/fasttree:2.1.11--h7b50bb2_5 \
    -out tree.nwk allSingleCopyOrthologsAlign.Protein.fasta
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull fasttree.sif docker://depot.galaxyproject.org/singularity/fasttree:2.1.11--h7b50bb2_5
apptainer run -B $PWD:/data -H /data fasttree.sif \
    -out /data/tree.nwk /data/allSingleCopyOrthologsAlign.Protein.fasta
```

### 4. 官方源码编译（官方无预编译二进制，源码即官方本地安装路线）

官方仅分发单一 C 源文件 `FastTree-2.1.11.c`（2026-09 核实 200），按官方说明编译 `FastTree`（单精度）与 `FastTree_d`（`-DUSE_DOUBLE`，双精度）两版本：

```bash
wget http://www.microbesonline.org/fasttree/FastTree-2.1.11.c -P ~/software/
cd ~/software/
# 编译蛋白质版本
gcc -O3 -finline-functions -funroll-loops -Wall -o FastTree FastTree-2.1.11.c -lm
# 编译核酸版本（支持 GTR 模型）
gcc -O3 -finline-functions -funroll-loops -Wall -DUSE_DOUBLE -o FastTree_d FastTree-2.1.11.c -lm

# 部署到用户级前缀（无需 root；禁 /opt/biosoft、/home/train）
mkdir -p ~/software/FastTree-2.1.11/bin
cp FastTree FastTree_d ~/software/FastTree-2.1.11/bin/
echo 'export PATH=$PATH:~/software/FastTree-2.1.11/bin/' >> ~/.bashrc && source ~/.bashrc
FastTree -help   # 断言
```

## 官方实现（Snakemake / nf-core）

* **snakemake-wrappers**：官方 `bio/fasttree` 存在（扁平 wrapper，`environment.yaml` pin `fasttree=2.2.0`，2026-09 在线核实）。本模块无本地 snakemake 修订，可直接复用官方 wrapper 句柄（运行靠 Snakemake 运行时解析，勿把示例当 `wrapper_path`）：

  ```python
  rule fasttree:
      input:
          alignment="{sample}.fa",
      output:
          tree="{sample}.nwk",
      log:
          "logs/fasttree/{sample}.log",
      params:
          extra="",           # 额外参数（如 "-gamma -boot 1000"）
      wrapper:
          "v9.17.1/bio/fasttree"   # 与 software_versions.snakemake_wrappers.wrapper_tag 对齐
  ```

  缺失时用本模块 `native/main.py` 兜底。

* **nf-core**：官方扁平模块 `nf-core/fasttree` 存在（pin `bioconda::fasttree=2.1.10`，2026-09 在线核实）。执行前请 `nf-core modules install fasttree` 安装到项目自身目录，不要直接引用本仓库示例；缺失时用 `native/main.py` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证 + FastTree 已安装时真实极小规模建树冒烟
```

## 版本

* fasttree 2.1.11（bioconda::fasttree=2.1.11；官方源码 `FastTree-2.1.11.c`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/fasttree / depot.galaxyproject.org；本地不再自建容器）；官方本地安装为源码 gcc 编译

* 官方层：nf-core 扁平模块 fasttree（pin 2.1.10）、snakemake-wrappers 扁平 wrapper bio/fasttree（pin 2.2.0），与 native 2.1.11 存在 patch/minor 差异，跨实现迁移须核对

## 容器与 Conda 链接

* **官网**：<https://morgannprice.github.io/fasttree/>

* **Github仓库**：<https://github.com/morgannprice/fasttree>

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/fasttree/overview>

* **Docker**：`docker pull quay.io/biocontainers/fasttree:2.1.11--h7b50bb2_5`

* **Singularity**：<https://depot.galaxyproject.org/singularity/fasttree%3A2.1.11--h7b50bb2_5>

* 安装方式（本地）：`mamba create -n fasttree -c conda-forge -c bioconda fasttree=2.1.11`（或 `bash native/install.sh`）
