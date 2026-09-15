# beagle-lib 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 beagle-lib 实现（2026-09 抓取 404），故不建对应目录，仅在 `software_versions` 与本文登记。

***

## native 实现

# beagle-lib / native — BEAGLE 3.1.2 似然计算库驱动

BEAGLE（Broad-platform Evolutionary Analysis General Likelihood Evaluator）的本地自包含实现（`source_type: custom`、`type: native`）。BEAGLE 是**库**（`libhmsbeagle`），不是可执行程序；上游 BEAST/BEAST2/MrBayes 通过头文件 + 共享库链接，并借 pkg-config 元数据（`hmsbeagle-1`）取得编译/链接参数。

## 功能

| 子命令       | 命令                                                                                     | 作用                              |
| --------- | -------------------------------------------------------------------------------------- | ------------------------------- |
| `install` | `cd <src> && ./autogen.sh && ./configure --prefix=<prefix> && make -j N && make install` | 源码编译安装 BEAGLE 库到 `--prefix`       |
| `verify`  | `pkg-config --modversion hmsbeagle-1`                                                  | 校验已安装库版本（需 PKG_CONFIG_PATH）      |
| `flags`   | `pkg-config --cflags --libs hmsbeagle-1`                                               | 打印下游工具链接 BEAGLE 所需编译/链接参数        |

> `install` 自动注入线程（`make -j N`）；`verify`/`flags` 依据 `--prefix` 设置 `PKG_CONFIG_PATH`。
> 驱动默认导出三个搜索路径：`PKG_CONFIG_PATH=<prefix>/lib/pkgconfig`、`LD_LIBRARY_PATH=<prefix>/lib`、`C_INCLUDE_PATH=<prefix>/include`。

## 用法

```bash
# 源码编译安装（--source-dir 为含 autogen.sh 的源码目录）
python main.py install --source-dir ./beagle-lib-3.1.2 --prefix ~/software/beagle-lib-3.1.2 --threads 8
# 校验与取链接参数
python main.py verify --prefix ~/software/beagle-lib-3.1.2
python main.py flags  --prefix ~/software/beagle-lib-3.1.2

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：编译 BEAGLE 并让 BEAST2 用其加速（14.md 七、6.3.1）

BEAGLE 是 BEAST2 的可选加速库：装好后在 `beast` 命令加 `-beagle`，运行期由 `LD_LIBRARY_PATH` 找到 `libhmsbeagle.so`。等价能力由 `native/main.py` 的 `install` / `verify` / `flags` 子命令提供（见上「用法」）。

### 1. 获取源码并编译安装

```bash
curl -fsSL -o ~/software/beagle-lib-3.1.2.tar.gz \
    https://github.com/beagle-dev/beagle-lib/archive/v3.1.2.tar.gz
tar zxf ~/software/beagle-lib-3.1.2.tar.gz -C ~/software/
cd ~/software/beagle-lib-3.1.2
# 等价：python main.py install --source-dir . --prefix ~/software/beagle-lib-3.1.2 --threads 8
./autogen.sh
./configure --prefix="$HOME/software/beagle-lib-3.1.2"
make -j 8 && make install
```

### 2. 配置搜索路径（供上层工具链接）

```bash
export PKG_CONFIG_PATH="$HOME/software/beagle-lib-3.1.2/lib/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$HOME/software/beagle-lib-3.1.2/lib:$LD_LIBRARY_PATH"
export C_INCLUDE_PATH="$HOME/software/beagle-lib-3.1.2/include:$C_INCLUDE_PATH"
# 等价校验：python main.py verify --prefix ~/software/beagle-lib-3.1.2
pkg-config --modversion hmsbeagle-1       # 断言：3.1.2
pkg-config --cflags --libs hmsbeagle-1    # 供 BEAST2 等链接
```

### 3. BEAST2 启用 BEAGLE 加速

```bash
beast -beagle -beagle_CPU -beagle_SSE -beagle_double -threads 8 -instances 8 input.xml
```

### 4. 参数说明

| 参数 / 变量                                  | 说明                              |
| --------------------------------------- | ------------------------------- |
| `--prefix`                              | 安装前缀（默认 `~/software/beagle-lib-3.1.2`） |
| `--enable-sse` / `--enable-avx`（透传）    | 启用 CPU SIMD 指令集加速                |
| `PKG_CONFIG_PATH`                       | 让 `pkg-config` 找到 `hmsbeagle-1.pc` |
| `LD_LIBRARY_PATH`                       | 运行期定位 `libhmsbeagle.so`          |
| `C_INCLUDE_PATH`                        | 编译期定位 `libhmsbeagle-1/*.h`       |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行；`main.py` 驱动在宿主机跑。官方**无** 预编译二进制包（BEAGLE 为源码分发），源码编译为官方源码路线。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n beagle-lib-native -c conda-forge -c bioconda beagle-lib=3.1.2
conda activate beagle-lib-native
pkg-config --modversion hmsbeagle-1   # 断言：3.1.2
```

```bash
# 或用 Homebrew：官方无 beagle-lib 公式（homebrew-core 与 brewsci/bio 均 404，2026-09 核实）——故不提供 brew 块
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `beagle-lib`，无 conda 时下载官方源码 `v3.1.2.tar.gz` 编译到 `~/software/beagle-lib-3.1.2` 并写三个搜索路径到 profile；版本默认 3.1.2，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/beagle-lib:3.1.2--h503566f_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/beagle-lib:3.1.2--h503566f_5 pkg-config --modversion hmsbeagle-1
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull beagle-lib.sif docker://depot.galaxyproject.org/singularity/beagle-lib:3.1.2--h503566f_5
apptainer run -B $PWD:/data -H /data beagle-lib.sif pkg-config --modversion hmsbeagle-1
```

### 4. 官方源码编译（官方唯一源码路线）

官方**不提供**预编译二进制包（源码归档即唯一官方来源，已核实）：

```bash
curl -fsSL -o ~/software/beagle-lib-3.1.2.tar.gz \
    https://github.com/beagle-dev/beagle-lib/archive/v3.1.2.tar.gz
tar zxf ~/software/beagle-lib-3.1.2.tar.gz -C ~/software/
cd ~/software/beagle-lib-3.1.2
./autogen.sh
./configure --prefix="$HOME/software/beagle-lib-3.1.2"
make -j 8 && make install
# 三个搜索路径见「实战示例 §2」
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证 + 自省断言；默认前缀已装库则额外冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/beagle-lib/overview>

* **Docker**：`docker pull quay.io/biocontainers/beagle-lib:3.1.2--h503566f_5`

* **Singularity**：<https://depot.galaxyproject.org/singularity/beagle-lib%3A3.1.2--h503566f_5>

* **官方源码 / 文档**：<https://github.com/beagle-dev/beagle-lib>

* 安装方式（本地）：`mamba create -n beagle-lib -c conda-forge -c bioconda beagle-lib=3.1.2`

* 官方无 nf-core 模块（`modules/nf-core/beagle-lib` 404）、无 snakemake-wrappers（`bio/beagle-lib` 404）——如需流程集成请以本模块 `native/main.py` 兜底。

## 版本

* beagle-lib **3.1.2**（官方源码 `v3.1.2.tar.gz`，`./autogen.sh + ./configure + make install`；pkg-config 模块名 `hmsbeagle-1`）

* 构建路线：官方镜像 / conda 提供（quay.io/biocontainers/beagle-lib / depot.galaxyproject.org，tag `3.1.2--h503566f_5`；本地不再自建容器）

* 官方无 Homebrew 公式（homebrew-core / brewsci-bio 均 404）；bioconda 提供 3.1.0/3.1.1/3.1.2/4.0.x
