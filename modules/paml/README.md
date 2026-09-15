# paml 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 paml 实现（2026-09 抓取 404），故不建对应目录，仅在 `software_versions` 与本文登记。

***

## native 实现

# paml / native — PAML v4.9i 分子进化程序套件驱动

PAML（Phylogenetic Analysis by Maximum Likelihood）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

使用PAML的baseml程序对每个单拷贝同源基因进行枝长分析，与标准树比较，剔除异常基因，以提高物种树构建的准确性。

子命令一一映射 PAML 的 9 个程序，命令形如 `<程序> <控制文件>`（省略 `ctl` 时用 PAML 默认名 `<subcommand>.ctl`）：

| 子命令              | 命令                              | 作用                                  | 14.md 对应      |
| ---------------- | ------------------------------- | ----------------------------------- | ------------- |
| `baseml`         | `baseml baseml.ctl`             | 核苷酸最大似然枝长 / 异常基因检测                  | 六、PAML baseml |
| `mcmctree`       | `mcmctree mcmctree.ctl`         | 贝叶斯分子钟 / 分歧时间估计（经 baseml 近似似然）       | 七、6.1        |
| `codeml`         | `codeml codeml.ctl`             | 正选择分析（YN00 / branch / branch-site）  | 九、PAML codeml |
| `yn00`           | `yn00 yn00.ctl`                 | Nei-Gojobori 法 dn/ds（候选正选择基因筛选）     | 九、8.4        |
| `basemlg`        | `basemlg basemlg.ctl`           | 连续伽马模型枝长估计                          | —             |
| `evolver`        | `evolver evolver.ctl`           | 序列 / 树模拟                            | —             |
| `infinitesites`  | `infinitesites infinitesites.ctl` | 无穷位点模拟（`mcmctree -D INFINITESITES`） | —             |
| `chi2`           | `chi2 chi2.ctl`                 | 卡方临界值计算（似然比检验）                      | —             |
| `pamp`           | `pamp pamp.ctl`                 | 祖先序列重建                              | —             |

## 用法

```bash
# CLI 直跑（<程序> <控制文件>）
python main.py baseml baseml.ctl --threads 8
python main.py mcmctree mcmctree.ctl
python main.py codeml codeml.ctl
python main.py yn00 yn00.ctl

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

> PAML 各程序**单线程**；`--threads` 经 `OMP_NUM_THREADS` 透传（对 OpenMP 构建生效），命令行不注入线程参数。
> `mcmctree` 的大规模近似似然步骤需用 `ParaFly` 等外部工具并行（见 14.md「七、6.1.2」），本驱动只负责单程序 argv 构造。

## 实战示例：baseml 异常基因检测 + mcmctree 分子钟 + codeml 正选择

以 14.md 的基因组比较流程为例；等价能力由 `native/main.py` 的 `baseml` / `mcmctree` / `codeml` / `yn00` 子命令提供（见上「用法」）。

### 1. baseml 枝长分析（异常基因检测）

```bash
mkdir -p paml_baseml && cd paml_baseml
# 每个单拷贝同源基因的密码子比对 + 标准树拓扑
printf '4 1\n(((parub,sccit),(laame,plost)),(phgig,lasul));\n' > input.trees
for i in $(cat ../orthologGroups.txt); do
    # 等价：python main.py baseml $i.ctl
    baseml $i.ctl > $i.baseml.log
done
```

### 2. mcmctree 贝叶斯分子钟

```bash
# 两步法：先近似似然（usedata=3 生成 out.BV），再 usedata=2 跑 MCMC
mcmctree mcmctree.ctl          # 等价：python main.py mcmctree mcmctree.ctl
cp out.BV in.BV
perl -p -i -e 's/usedata = .*/usedata = 2    \* 0:/;' mcmctree.ctl
mcmctree mcmctree.ctl          # 产出 FigTree.tre / mcmc.txt
```

### 3. codeml 正选择（YN00 预筛 + branch-site）

```bash
# YN00 计算 dn/ds 筛候选正选择基因
python main.py yn00 yn00.ctl
# codeml branch-site 模型对目标分枝做 LRT
python main.py codeml codeml.ctl
```

### 4. 参数说明（.ctl 常用项）

| 控制项         | 说明                              |
| ----------- | ------------------------------- |
| `seqfile`   | Phylip 格式比对文件                   |
| `treefile`  | Newick 树文件（首行 `物种数 树数`）         |
| `outfile`   | 结果输出文件                          |
| `usedata`   | mcmctree：`3` 生成近似似然、`2` 跑 MCMC  |
| `model`     | mcmctree 模型（如 `7` = HKY85）      |
| `burnin`    | MCMC 预热步数                        |
| `nsample`   | MCMC 采样数                         |
| `clock`     | codeml：`0` 无钟 / `1` 严格钟 / `2` 局部钟 |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n paml-native -c conda-forge -c bioconda paml=4.9   # bioconda 无 4.9i 独立版；4.9 即 4.9 系列
conda activate paml-native
baseml   # 打印 BASEML in paml version 4.9, ... 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install paml
paml_version=$(basename "$(command -v baseml)")   # PAML 无 --version，直接看 baseml banner
# 注：brew 当前 paml 4.10.10，与 meta 登记 4.9i 略有差异（版本以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `paml`（装 paml=4.9），无 conda 时下载官方源码 `paml4.9i.tgz` 编译到 `~/software/paml-4.9i` 并写 PATH；版本默认 4.9i，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/paml:4.9--hec16e2b_7
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/paml:4.9--hec16e2b_7 baseml baseml.ctl
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull paml.sif docker://depot.galaxyproject.org/singularity/paml:4.9--hec16e2b_7
apptainer run -B $PWD:/data -H /data paml.sif baseml /data/baseml.ctl
```

### 4. 官方源码编译（官方唯一源码路线，4.9i）

官方**不提供**预编译二进制包，源码归档即唯一官方来源（已核实）；GitHub 仓库以 release `pre-v4.10` 归档 4.9i 及更早版本：

```bash
# 下载官方源码（github.com/abacus-gene/paml，release pre-v4.10）
curl -fsSL -o ~/software/paml4.9i.tgz \
    https://github.com/abacus-gene/paml/releases/download/pre-v4.10/paml4.9i.tgz
tar zxf ~/software/paml4.9i.tgz -C ~/software/
cd ~/software/paml4.9i/src
make -f Makefile            # 产出 baseml basemlg chi2 codeml evolver infinitesites mcmctree pamp yn00
mkdir -p ~/software/paml-4.9i/bin
cp baseml basemlg chi2 codeml evolver infinitesites mcmctree pamp yn00 ~/software/paml-4.9i/bin/
echo 'export PATH=$PATH:~/software/paml-4.9i/bin' >> ~/.bashrc && source ~/.bashrc
baseml                      # 打印 banner 断言（BASEML in paml version 4.9i）
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证 + 自省断言；baseml 已安装则额外冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/paml/overview>

* **Docker**：`docker pull quay.io/biocontainers/paml:4.9--hec16e2b_7`

* **Singularity**：<https://depot.galaxyproject.org/singularity/paml%3A4.9--hec16e2b_7>

* **官方源码**：<https://github.com/abacus-gene/paml/releases/tag/pre-v4.10>（`paml4.9i.tgz`）

* 安装方式（本地）：`mamba create -n paml -c conda-forge -c bioconda paml=4.9`

* 官方无 nf-core 模块（`modules/nf-core/paml` 404）、无 snakemake-wrappers（`bio/paml` 404）——如需流程集成请以本模块 `native/main.py` 兜底。

## 版本

* paml **4.9i**（官方源码 `paml4.9i.tgz`，`make -f Makefile` 编译全部程序）

* 构建路线：官方镜像 / conda 提供（quay.io/biocontainers/paml / depot.galaxyproject.org，官方 tag 为 `4.9`/`4.10.x`；本地不再自建容器）

* 官方渠道版本对照：bioconda `paml=4.9`（= 4.9 系列，无 "4.9i" 独立 tag）与 `4.10.x`；homebrew-core `paml 4.10.10`；native 登记以官方源码 4.9i 为准
