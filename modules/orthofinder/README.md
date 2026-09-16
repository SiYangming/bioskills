# orthofinder 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 本仓库的 OrthoFinder 模块用于替代已停止维护的 `modules/orthomcl/`（OrthoMCL）。

***

## native 实现

# orthofinder / native — 自包含同源基因聚类驱动

OrthoFinder（v2.5.5）的本地自包含实现（`source_type: custom`、`type: native`）：一条命令
完成同源基因聚类全流程（orthogroups / orthologues / 基因树 / 有根物种树 / 基因复制事件），
比 OrthoMCL 快 10-100 倍、准确性更高、无需 MySQL。

## 功能

**OrthoFinder** 是一款现代化的同源基因聚类工具，是 OrthoMCL 的继任者。它解决了 OrthoMCL 的许多局限性，具有以下优势：

| 子命令 | 实际命令 | 作用 |
| ---- | ---- | ---- |
| `run` | `orthofinder -f <dir> -t <threads> -a <threads> -S <search> [-M dendroblast\|msa] [-I infl] [-o dir] [-n name] [-A msa] [-T tree] [-s tree] [-x xml] [-d] [-op\|-og\|-os\|-oa\|-ot]` | 全流程同源聚类 |
| `resume` | `orthofinder -b <prev_dir> [-f <new_dir>] -t <threads> -a <threads> -S <search> [...]` | 从既有结果续跑 / 追加物种 |
| `help` | `orthofinder -h` | 打印帮助与版本横幅 |

`run`/`resume` 自动注入线程（`-t` 与 `-a` 同值）；`-S` 默认 `diamond`（与 nf-core 用法一致）。线程优先级 `--threads` > `per_subcommand_threads` > `default_cpus`。

## 用法

```bash
# CLI 直跑
python main.py run -f input_proteins -S diamond -t 8 -M dendroblast -o orthofinder_results
python main.py run -f input_proteins -S diamond -t 8 -M msa -A mafft -T fasttree
python main.py resume -b orthofinder_results/OrthoFinder/Results_input_proteins -t 8
python main.py help

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`-t` 亦可）。

## 参数说明（对照 OrthoFinder 2.5.5 help）

| 参数 | 子命令 | 说明 |
| ---- | ---- | ---- |
| `-f` | run/resume | 输入目录：每物种一个蛋白 FASTA（文件名即物种名）；DNA 序列需 `-d` |
| `-b` | resume | 上次结果目录（含 WorkingDirectory），从预计算结构续跑 |
| `-t` / `-a` | run/resume | 并行序列搜索线程数（`-t`）/ 分析线程数（`-a`），本驱动同值注入 |
| `-S` | run/resume | 序列搜索程序（默认 `diamond`；可选 `blast` 等） |
| `-M` | run/resume | 基因树推断方法：`dendroblast`（快速，默认）/ `msa`（多序列比对） |
| `-I` | run/resume | MCL inflation 参数（默认 1.5） |
| `-A` / `-T` | run/resume | MSA 程序 / 基因树程序（需 `-M msa`；默认 mafft / fasttree） |
| `-s` | run/resume | 用户指定的有根物种树（Newick） |
| `-x` | run/resume | OrthoXML 输出所需信息文件 |
| `-d` | run/resume | 输入为 DNA 序列 |
| `-o` / `-n` | run | 非默认输出目录 / 结果目录名后缀 |
| `-op/-og/-os/-oa/-ot` | run/resume | 提前停止（仅准备 / 仅 orthogroups / 仅序列 / 仅比对 / 仅基因树） |

## 实战示例：同源基因聚类

```bash
# 1) 准备输入：每物种一个蛋白 FASTA，文件名即物种名
mkdir -p input_proteins && cd input_proteins
for i in parub sccit laame plost lasul phgig
do
    cp ../../a.preparing_data/$i.pep.fasta $i.fasta
done
cd ..

# 2) 全流程（DIAMOND 距离矩阵 + 默认 dendroblast）
orthofinder -f input_proteins -S diamond -t 8 -o orthofinder_results

# 3) 用多序列比对推断基因树（更准，更慢）
orthofinder -f input_proteins -S diamond -t 8 -M msa

# 4) 从上一轮结果续跑（追加新物种）
orthofinder -f input_proteins_new -b orthofinder_results/OrthoFinder/Results_input_proteins -t 8
```

输出结构（结果目录）：

```
orthofinder_results/OrthoFinder/Results_input_proteins/
├── Orthogroups/
│   ├── Orthogroups.tsv                        # 同源群（基因家族）列表
│   ├── Orthogroups.txt                        # OrthoMCL 格式同源群列表
│   ├── UnassignedGenes.tsv                    # 未分配基因
│   └── Orthogroups_SingleCopyOrthologues.txt  # 单拷贝同源基因列表
├── Gene_Trees/                                # 每个基因家族的基因树
├── Species_Tree/                              # 有根/无根物种树
├── Comparative_Genomics_Statistics/           # 每物种/总体统计
└── Single_Copy_Orthologue_Sequences/          # 单拷贝同源基因序列（直接用于后续系统发育）
```

上述命令等价能力由 `native/main.py` 的 `run` / `resume` 子命令提供（见上「用法」）。

## 测试

```bash
bash test/run_test.sh   # run/resume/help 均为 argv 构造验证（orthofinder 未装时退化为断言）
```

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方
镜像运行工具本体；`main.py` 驱动在宿主机跑。OrthoFinder 官方 release 同时提供
**standalone 预编译包**（`OrthoFinder.tar.gz`，含冻结可执行 + 捆绑 diamond/mcl/fastme）
与**源码包**（`OrthoFinder_source.tar.gz`），故宿主安装两条官方路线并列。

### 1. Conda / brew（包管理器安装）

OrthoFinder的依赖包括DIAMOND（序列比对），MCL（聚类），FastTree（基因树构建），MAFFT（多序列比对）。

```bash
mamba create -n orthofinder-native -c conda-forge -c bioconda orthofinder=2.5.5
conda activate orthofinder-native
orthofinder -h   # 断言：启动横幅含 "OrthoFinder version 2.5.5"
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/orthofinder.json）与 brewsci/bio
> （Formula/orthofinder.rb）均 404（2026-09 核实），无公式 → 不登记 brew 安装块
> （`brew tap brewsci/bio && brew install orthofinder` 当前不可用）。

> 一键安装也可直接运行 `native/install.sh`（有 conda 时建 bioconda 环境 `orthofinder`；
> linux-x64 无 conda 时下载官方 standalone 预编译包，其余平台走源码；版本默认 2.5.5，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/orthofinder:2.5.5--hdfd78af_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/orthofinder:2.5.5--hdfd78af_2 \
    orthofinder -f /data/input_proteins -S diamond -t 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull orthofinder.sif docker://depot.galaxyproject.org/singularity/orthofinder:2.5.5--hdfd78af_2
apptainer run -B $PWD:/data -H /data orthofinder.sif \
    orthofinder -f /data/input_proteins -S diamond -t 8
```

### 4. 官方预编译 standalone 包（首选；仅 linux-x86_64）

官方 release 提供 `OrthoFinder.tar.gz`（约 63 MB，内含 frozen `orthofinder` 可执行与
捆绑 `bin/{diamond,mcl,fastme}`，**Linux x86-64**）：

```bash
wget https://github.com/davidemms/OrthoFinder/releases/download/2.5.5/OrthoFinder.tar.gz -P ~/software/
tar zxf ~/software/OrthoFinder.tar.gz -C ~/software/
export PATH="$HOME/software/OrthoFinder:$PATH"   # 建议写入 ~/.bashrc
orthofinder -h
# sha256(OrthoFinder.tar.gz) = 81dc09a9cfe0cab811359bce0bd3d8d44ff57f9771943ea4b427dc47df576a2d
```

> standalone 包为 **Linux x86-64** 专用（内含 Linux ELF 捆绑依赖）；macOS 请走 conda 或源码路线。

### 5. 官方源码编译（并列保留；需自备依赖）

官方 release 同时提供 `OrthoFinder_source.tar.gz`（源码，需自备 Python、DIAMOND、MCL、
MAFFT、FastTree）：

```bash
wget https://github.com/davidemms/OrthoFinder/releases/download/2.5.5/OrthoFinder_source.tar.gz -P ~/software/
tar zxf ~/software/OrthoFinder_source.tar.gz -C ~/software/
export PATH="$HOME/software/OrthoFinder_source:$PATH"   # 建议写入 ~/.bashrc
orthofinder.py -h        # 源码入口为 orthofinder.py
# sha256(OrthoFinder_source.tar.gz) = 43d034a66a13adba8872a0d4a76e32c25305a7fae638754adb61c37a3f957bd9
```

> 也可一键运行 `native/install.sh --method binary`（standalone，linux-x64）或
> `--method source`（源码 + 自动建 `orthofinder` 包装脚本）。

## 版本

* **2.5.5**（官方 release tag `2.5.5`）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/orthofinder / depot.galaxyproject.org；本地不再自建容器）
* License：**GPL-3.0-only**
* nf-core：有单模块 `modules/nf-core/orthofinder`（pin **bioconda::orthofinder=3.1.3**，与 native
  2.5.5 相差 major；正交流程迁移时请核对 `-M/-S` 等参数兼容性）
* snakemake-wrappers：无 `bio/orthofinder`（2026-09 核实 404）
* 引用：Emms DM, Kelly S. OrthoFinder: phylogenetic orthology inference for comparative
  genomics. *Genome Biol.* 2019;20:238. doi:10.1186/s13059-019-1832-y

## 容器与 Conda 链接

* **官网**：<https://davidemms.github.io/>
* **GitHub**：<https://github.com/davidemms/OrthoFinder>
* **新GitHub**：<https://github.com/OrthoFinder/OrthoFinder>
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/orthofinder/overview>
* **Docker**：`docker pull quay.io/biocontainers/orthofinder:2.5.5--hdfd78af_2`
* **Singularity**：<https://depot.galaxyproject.org/singularity/orthofinder%3A2.5.5--hdfd78af_2>
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* 安装方式（本地）：`mamba create -n orthofinder -c conda-forge -c bioconda orthofinder=2.5.5`
