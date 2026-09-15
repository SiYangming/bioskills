# raxml 软件模块

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与
> snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息
> 记录于文末。

***

## native 实现

# raxml / native — 最大似然建树驱动

RAxML（[官网](https://cme.h-its.org/exelixis/web/software/raxml/index.html) ・
[stamatak/standard-RAxML](https://github.com/stamatak/standard-RAxML)，Randomized Axelerated Maximum
Likelihood，standard-RAxML **v8.2.12**）是最大似然系统发育树构建的经典工具：以 `GTRGAMMA`（核酸/密码子）
或 `PROTGAMMA*`（蛋白质）等模型搜索最优树，并支持快速 bootstrap（`-f a -x/-#`）评估分支支持度，输出
`RAxML_bestTree` / `RAxML_bipartitions` / `RAxML_bootstrap` 等结果文件。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**
（quay.io/biocontainers/raxml / bioconda raxml）提供，或由官方源码编译，登记 **8.2.12**。下一代工具
（RAxML-NG）见 `modules/raxml-ng`。

## 功能

| 子命令            | 命令                                                                                                       | 作用                                    |
| -------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `ml_bootstrap` | `raxmlHPC-PTHREADS-SSE3 -f a -x <seed> -p <seed> -# <n> -m <model> -s <msa> -n <name> -T <threads>`         | ML 树搜索 + 快速 bootstrap（分支支持度）           |
| `ml_search`    | `raxmlHPC-PTHREADS-SSE3 -f d -p <seed> -m <model> -s <msa> -n <name> -T <threads>`                         | 仅搜索最优 ML 树（无 bootstrap）                |
| `version`      | `raxmlHPC-PTHREADS-SSE3 -v`                                                                              | 打印 RAxML 版本                           |

> `execution.binary` 登记 **SSE3 PTHREADS** 版代表性入口；conda/官方镜像同时提供 `raxmlHPC` /
> `raxmlHPC-PTHREADS` / `raxmlHPC-SSE3` / `raxmlHPC-PTHREADS-SSE3` / `raxmlHPC-AVX` 等（见「官方源码编译」）。

## 用法

```bash
# CLI 直跑（14.md 密码子模型 / 蛋白质模型）
python main.py ml_bootstrap -s allSingleCopyOrthologsAlign.Codon.phy -m GTRGAMMA -n out_codon -# 100 -T 8
python main.py ml_search    -s allSingleCopyOrthologsAlign.Protein.phy -m PROTGAMMAILGX -n out_protein -T 8
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（注入 RAxML 的 `-T`）。**RAxML 为 CPU 密集工具**，
线程优先级 `--threads` > `per_subcommand_threads`（默认 8）> `default_cpus`。

## 实战示例：最大似然物种树构建

RAxML 输入为 Phylip 格式比对（由单拷贝同源基因的 Gblocks/trimAl 修剪结果整合、转换而来）；**等价能力由
`native/main.py` 的 `ml_bootstrap` 子命令提供**（见上「用法」）。

### 1. 密码子模型建树（GTRGAMMA，带 100 次 bootstrap）

```bash
mkdir -p RAxML && cd RAxML
raxmlHPC-PTHREADS-SSE3 -f a -x 12345 -p 12345 -# 100 \
    -m GTRGAMMA -s allSingleCopyOrthologsAlign.Codon.phy -n out_codon -T 8

# 输出文件：RAxML_bestTree.out_codon（最佳树，无 bootstrap 值）
#           RAxML_bipartitions.out_codon（带 bootstrap 值的树）
#           RAxML_bootstrap.out_codon（所有 bootstrap 树）
# 驱动等价写法：
python ../modules/raxml/native/main.py ml_bootstrap -s allSingleCopyOrthologsAlign.Codon.phy \
    -m GTRGAMMA -n out_codon -# 100 -T 8
```

### 2. 蛋白质模型建树（PROTGAMMAILGX）

```bash
raxmlHPC-PTHREADS-SSE3 -f a -x 12345 -p 12345 -# 100 \
    -m PROTGAMMAILGX -s allSingleCopyOrthologsAlign.Protein.phy -n out_protein -T 8
```

### 3. 参数说明

| 参数                  | 说明                             |
| ------------------- | ------------------------------ |
| `-f a`              | 快速 bootstrap 分析 + 搜索最佳树         |
| `-f d`              | 仅搜索最佳 ML 树                     |
| `-x <seed>`         | bootstrap 随机种子（`-f a`）         |
| `-p <seed>`         | 初始树/似然搜索随机种子                   |
| `-# <n>`            | bootstrap 重复次数（正式分析建议 1000）    |
| `-m <model>`        | 进化模型（GTRGAMMA / PROTGAMMAILGX…） |
| `-s <msa>`          | 输入比对（Phylip）                   |
| `-n <name>`         | 输出文件前缀                         |
| `-T <threads>`      | 线程数（驱动注入）                      |

## 环境安装（官方源码编译优先；Conda / brew / 官方镜像并列）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。RAxML 官方**仅以源码分发（无预编译二进制包）**，故各安装路线并列如下。

### 1. 官方源码编译（首选）

官方源码归档 <https://github.com/stamatak/standard-RAxML>（tag `v8.2.12`，归档
`https://github.com/stamatak/standard-RAxML/archive/v8.2.12.tar.gz`）。源码含多套 Makefile，按平台/指令集选择：

```bash
wget https://github.com/stamatak/standard-RAxML/archive/v8.2.12.tar.gz -O ~/software/RAxML-v8.2.12.tar.gz
tar zxf ~/software/RAxML-v8.2.12.tar.gz -C ~/software/
mv ~/software/standard-RAxML-8.2.12 ~/software/RAxML-8.2.12
cd ~/software/RAxML-8.2.12/

# PTHREADS 版本（多线程，免 MPI）：SSE3 / AVX
make -f Makefile.SSE3.PTHREADS.gcc -j 4      # → raxmlHPC-PTHREADS-SSE3
rm -f *.o
make -f Makefile.AVX.PTHREADS.gcc  -j 4      # → raxmlHPC-PTHREADS-AVX（新 CPU 更快）
rm -f *.o

# HYBRID 版本（MPI 并行，⚠️ 需 MPICH；PTHREADS 与 MPI 混合，适合多节点）
export C_INCLUDE_PATH=/usr/include/mpich-x86_64:$C_INCLUDE_PATH
export LD_LIBRARY_PATH=/usr/lib64/mpich/lib:$LD_LIBRARY_PATH
export PATH=/usr/lib64/mpich/bin:$PATH
make -f Makefile.SSE3.HYBRID.gcc -j 4        # → raxmlHPC-HYBRID-SSE3
rm -f *.o
make -f Makefile.AVX.HYBRID.gcc  -j 4        # → raxmlHPC-HYBRID-AVX

mkdir -p ~/software/raxml-8.2.12/bin
cp raxmlHPC* ~/software/raxml-8.2.12/bin/
chmod 755 ~/software/raxml-8.2.12/bin/*
echo 'export PATH=$PATH:~/software/raxml-8.2.12/bin' >> ~/.bashrc && source ~/.bashrc
raxmlHPC-PTHREADS-SSE3 -v     # 断言（打印版本 8.2.12）
```

> ⚠️ **MPI 依赖（HYBRID 版）**：`Makefile.{SSE3,AVX}.HYBRID.gcc` 编译出的 `raxmlHPC-HYBRID-*` 需要
> **MPICH**（头文件 `mpich-x86_64` 与库 `libmpich`）；运行 HYBRID 版需用 `mpiexec -n <N>` 启动。若无 MPI 环境，
> 使用 PTHREADS 版（`-T`）即可。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `raxml`，无 conda 时
> 自动下载官方源码归档并按 `Makefile.SSE3.PTHREADS.gcc` 编译到 `~/software/raxml-<ver>` 并写 PATH；版本默认
> 8.2.12，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Conda / brew（包管理器安装，备选）

```bash
mamba create -n raxml-native -c conda-forge -c bioconda raxml=8.2.12
conda activate raxml-native
raxmlHPC-PTHREADS-SSE3 -v     # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# 注意：brew 当前 raxml=8.2.13，与 meta 登记 8.2.12 略有差异（版本以 formula 为准）
brew tap brewsci/bio     # 首次使用需要
brew install raxml
raxmlHPC -v              # 断言（brew 版可执行名以 formula 为准）
```

### 3. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/raxml:8.2.12--h031d066_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/raxml:8.2.12--h031d066_6 \
    raxmlHPC-PTHREADS-SSE3 -f a -x 12345 -p 12345 -# 100 \
    -m GTRGAMMA -s /data/allSingleCopyOrthologsAlign.Codon.phy -n out_codon -T 8
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull raxml.sif docker://depot.galaxyproject.org/singularity/raxml:8.2.12--h031d066_6
apptainer run -B $PWD:/data -H /data raxml.sif \
    raxmlHPC-PTHREADS-SSE3 -f a -x 12345 -p 12345 -# 100 -m GTRGAMMA -s /data/msa.phy -n out -T 8
```

## 官方实现登记（不建目录，仅说明层）

* **nf-core**：官方**无** `modules/nf-core/raxml`（2026-09 抓取 `contents/modules/nf-core/raxml` 返回
  **404**）→ 不建目录；Nextflow 场景请用本模块 `native/` 兜底。

* **snakemake-wrappers**：官方**无** `bio/raxml`（2026-09 核实 `tree/master/bio/raxml` 返回 **404**）→
  不建目录；Snakemake 场景请用本模块 `native/` 兜底。

## 测试

```bash
cd modules/raxml/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ argv 构造断言（含 -f a/-f d、
# 线程优先级）必跑；PATH 含 raxmlHPC-PTHREADS-SSE3 时追加 `-v` 版本冒烟（不做真实建树，避免长耗时）。
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/raxml>（现行 latest 8.2.13；本模块登记 8.2.12）

* **Docker**：`docker pull quay.io/biocontainers/raxml:8.2.12--h031d066_6`（bioconda 自动构建；tag 以 quay /
  depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/raxml%3A8.2.12--h031d066_6>

* 安装方式（本地）：`mamba create -n raxml -c conda-forge -c bioconda raxml=8.2.12`（或
  `brew tap brewsci/bio && brew install raxml` 当前 8.2.13；或官方源码编译，见上「官方源码编译」）

* 上游：<https://cme.h-its.org/exelixis/web/software/raxml/index.html>（官网）·
  <https://github.com/stamatak/standard-RAxML>（源码与归档）

## 版本

* raxml **8.2.12**（bioconda::raxml=8.2.12；官方容器 tag `8.2.12--h031d066_6`；bioconda 现行 latest 为
  8.2.13，本模块按 14.md 锁定 8.2.12）

* 许可：GPL-3.0（bioconda raxml 包元数据 license=GPL；standard-RAxML 源码以 GNU GPL 分发）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/raxml / depot.galaxyproject.org；本地不再自建容器）；
  官方仅以源码分发（多套 Makefile，HYBRID 版需 MPICH）

* 官方层：nf-core 无子模块、snakemake-wrappers 无 wrapper（均 2026-09 核实 404）
