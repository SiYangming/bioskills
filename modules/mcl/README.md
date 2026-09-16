# mcl 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# mcl / native — 自包含图聚类驱动

MCL（Markov Cluster Algorithm，Stijn van Dongen）的本地自包含实现（`source_type: custom`、
`type: native`）：用两路矩阵运算模拟随机流对加权无向图做聚类，单参数 `-I`（inflation）
控制聚类粒度。是 OrthoMCL 同源基因聚类流程的聚类内核（见下「实战示例」）。

## 功能

| 子命令 | 实际命令 | 作用 |
| ---- | ---- | ---- |
| `cluster` | `mcl <graph> [--abc] [-I <infl>] -o <out> [-te <threads>] [-scheme N] [-tf spec] [-pi num]` | 对图做 MCL 聚类，输出每行一个簇（制表符分隔标签） |
| `dump` | `mcxdump -imx <matrix> -o <out> [-tab <labels>] [--dump-pairs\|--dump-lines] [--no-values]` | MCL 套件图格式转换（原生矩阵 ↔ 文本/标签） |
| `version` | `mcl --version` | 打印版本 |

`cluster` 以 `-te` 注入线程（MCL 的 expansion threads）；`dump` 为单线程工具，不注入。

## 用法

```bash
# CLI 直跑（OrthoMCL 场景：ABC 图 + inflation 1.5）
python main.py cluster mclInput --abc -I 1.5 -o mclOutput --threads 8
python main.py dump -imx graph.mci -o graph.abc -tab labels.txt --dump-pairs
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 参数说明（对照官方 man page mcl / mcxdump）

| 参数 | 子命令 | 说明 |
| ---- | ---- | ---- |
| `<graph>` | cluster | 输入图文件（ABC 标签格式或 MCL 原生矩阵格式；`-` 表示 stdin） |
| `--abc` | cluster | 输入为 ABC 标签格式（每行 `标签A 标签B 权重`） |
| `-I` | cluster | inflation 参数，控制聚类粒度（MCL 默认 2.0；OrthoMCL 流程常用 1.5–2.0；起手值 1.4/2/4/6） |
| `-o` | cluster/dump | 输出文件 |
| `-te` | cluster | expansion 线程数（本驱动由 `--threads` 注入） |
| `-scheme` | cluster | 资源/剪枝方案编号（大图调优用；默认方案 6） |
| `-tf` | cluster | 输入矩阵变换表达式（如 `'gq(0.7),add(-0.7)'`，含括号/逗号需引号） |
| `-pi` | cluster | 预膨胀参数（提高边权对比度） |
| `-imx` | dump | mcxdump 输入矩阵 |
| `-tab` | dump | 标签文件（矩阵索引 → 标签） |
| `--dump-pairs` / `--dump-lines` | dump | 逐条输出 / 按行输出（默认按行） |
| `--no-values` | dump | 省略权重值 |

## 实战示例：OrthoMCL 流程中的 MCL 聚类

MCL 在 OrthoMCL 流程里接收 `orthomclDumpPairsFiles` 产出的 `mclInput`（ABC 格式的
相似序列对）做聚类，得到直系同源群 OCG（Ortholog Cluster Groups）：

```bash
# 1. MCL 聚类（-I 控制粒度，常用 1.5-2.0）
mcl mclInput --abc -I 1.5 -o mclOutput

# 2. 对聚类结果编号（OrthoMCL 提供）
orthomclMclToGroups OCG 1 < mclOutput > groups.txt
```

上述第 1 步等价能力由 `native/main.py cluster` 提供：

```bash
python main.py cluster mclInput --abc -I 1.5 -o mclOutput --threads 8
```

## 测试

```bash
bash test/run_test.sh   # cluster/dump/version 均为 argv 构造验证（mcl 未装时退化为断言）
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方
镜像运行工具二进制；`main.py` 驱动在宿主机跑。MCL 官方**仅分发源码、无预编译二进制**，
故宿主机安装主路线为 conda（源码编译作为并列官方路线）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n mcl-native -c conda-forge -c bioconda mcl=14.137
conda activate mcl-native
mcl --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap）
brew tap brewsci/bio
brew install mcl
mcl --version   # 断言
# 注：brew（brewsci/bio Formula/mcl.rb）当前公式版本为 22.282，与 meta 登记 14.137 略有差异（以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `mcl`，
> 无 conda 时下载官方源码 tarball 编译安装到 `~/software/mcl-14-137`；版本默认 14-137，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mcl:14.137--pl5321h031d066_9
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mcl:14.137--pl5321h031d066_9 \
    mcl mclInput --abc -I 1.5 -o mclOutput
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull mcl.sif docker://depot.galaxyproject.org/singularity/mcl:14.137--pl5321h031d066_9
apptainer run -B $PWD:/data -H /data mcl.sif \
    mcl /data/mclInput --abc -I 1.5 -o /data/mclOutput
```

### 4. 官方源码编译（官方唯一分发形式）

MCL 官方只提供源码 tarball（**无预编译二进制**，2026-09 于 micans.org 核实）：

* **官网**：<https://www.micans.org/mcl/>
* **源码**：<http://micans.org/mcl/src/mcl-14-137.tar.gz>（sha256 `b5786897a8a8ca119eb355a5630806a4da72ea84243dba85b19a86f14757b497`）

```bash
# MCL (Markov Cluster Algorithm) - 用于聚类分析
wget http://micans.org/mcl/src/mcl-14-137.tar.gz -P ~/software/
tar zxf ~/software/mcl-14-137.tar.gz -C ~/software/
cd ~/software/mcl-14-137
./configure --prefix=$HOME/software/mcl-14-137 && make -j 4 && make install
export PATH="$HOME/software/mcl-14-137/bin:$PATH"   # 建议写入 ~/.bashrc
mcl --version
```

> 也可一键运行 `native/install.sh --method source`（自动下载 + sha256 校验 + 编译安装 + PATH 写入）。

## 与 OrthoMCL / OrthoFinder 的关系

* **OrthoMCL** 流程用 MCL 做最后一步聚类（`mcl mclInput --abc -I 1.5 -o mclOutput`）；OrthoMCL
  模块见 `modules/orthomcl/`（已停止维护，推荐 OrthoFinder）。
* **OrthoFinder** 内置调用 MCL（`mcl <graph> -I <infl> -o <clusters> -te <threads> -V all`），
  conda 安装 OrthoFinder 会自动带上 mcl；单跑 MCL 时用本模块。

## 版本

* MCL **14-137**（upstream 发布号；bioconda 包名版本 **14.137**）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/mcl / depot.galaxyproject.org；本地不再自建容器）
* License：**GPL-3.0-only**（bioconda-recipes mcl 配方）
* nf-core：无 `modules/nf-core/mcl`（2026-09 核实 404）；snakemake-wrappers：无 `bio/mcl`（2026-09 核实 404）

## 容器与 Conda 链接

* **官网**：<https://www.micans.org/mcl/>
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/mcl/overview>
* **Docker**：`docker pull quay.io/biocontainers/mcl:14.137--pl5321h031d066_9`
* **Singularity**：<https://depot.galaxyproject.org/singularity/mcl%3A14.137--pl5321h031d066_9>
* **brew**：`brew tap brewsci/bio && brew install mcl`（brewsci/bio Formula/mcl.rb；当前公式 22.282）
* 安装方式（本地）：`mamba create -n mcl -c conda-forge -c bioconda mcl=14.137`
