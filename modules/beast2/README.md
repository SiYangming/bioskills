# beast2 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 beast2 实现（2026-09 抓取 404），故不建对应目录，仅在 `software_versions` 与本文登记。

***

## native 实现

# beast2 / native — BEAST2 v2.5.2 贝叶斯分子钟驱动（Java）

BEAST2（Bayesian Evolutionary Analysis Sampling Trees）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

| 子命令             | 命令                                                         | 作用                                    |
| --------------- | ---------------------------------------------------------- | ------------------------------------- |
| `beast`         | `beast [-beagle -beagle_CPU -beagle_SSE -beagle_double] -threads N -instances M input.xml` | 运行 MCMC 贝叶斯分析（分子钟 + 树先验）               |
| `treeannotator` | `treeannotator -burnin N input.trees output.tre`           | 由 posterior tree 采样生成最大可信度（MCC）树       |
| `logcombiner`   | `logcombiner -b N -o out in1 in2 ...`                      | 合并 / 降采样多个 `.log` / `.trees`           |
| `loganalyser`   | `loganalyser -b N in1 in2 ...`                             | log 统计量摘要                             |
| `densitetree`   | `densitetree in.trees ...`                                 | DensiTree 树分布可视化                       |
| `beauti`        | `beauti`                                                   | BEAUti 图形界面（生成 BEAST 输入 XML）          |
| `version`       | `beast -version`                                           | 打印版本（v2.5.2）                          |

> ⚠️ **BEAST 2.5.2 需 Java 8/11**：Java ≥20 移除了 `Thread.stop`，`beast` 运行结束会抛 `UnsupportedOperationException`（版本仍正常打印）。官方 Linux 包不自带 JRE，请自备 Java 8/11（如 `mamba install -c conda-forge openjdk=11`）。
> JVM 堆内存与临时目录经 `JAVA_OPTS`（`-Xmx{mem_mb}m -Djava.io.tmpdir={tmpdir}`）注入。

## 用法

```bash
# CLI 直跑（BEAGLE 加速 + 线程 + 实例数）
python main.py beast input.xml --beagle --threads 8 --instances 8
python main.py treeannotator input.trees -o tree_abbr.BEAST2 --burnin 20
python main.py logcombiner a.log b.log -o combined.log --burnin 10
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：BEAST2 贝叶斯分子钟（14.md 七、6.3）

BEAST2 以 XML 描述模型（BEAUti 生成），MCMC 采样后由 treeannotator 汇总 MCC 树。等价能力由 `native/main.py` 的 `beast` / `treeannotator` 子命令提供（见上「用法」）。

### 1. 准备输入 XML（BEAUti 设置要点）

```
Site Model：GTR、Gamma Category Count=4、勾选 Substitition Rate estimate / Rate CT estimate
Clock Model：Relaxed Clock Log Normal
Priors：Tree.t = Calibrated Yule Model；calibration（如 BOL 89MYA、AGC 246MYA）
MCMC：Chain Length=10000000、Store Every=5000
```

### 2. 运行 MCMC（BEAGLE 加速）

```bash
# 等价：python main.py beast input.xml --beagle --threads 8 --instances 8
beast -beagle -beagle_CPU -beagle_SSE -beagle_double -threads 8 -instances 8 input.xml &> beast2.log
```

### 3. 收敛性检查 + MCC 树

```bash
tracer input.log                                          # 图形界面检查 ESS
# 等价：python main.py treeannotator input.trees -o tree_abbr.BEAST2 --burnin 20
treeannotator -burnin 20 input.trees tree_abbr.BEAST2
```

### 4. 参数说明

| 参数                                      | 说明                        |
| --------------------------------------- | ------------------------- |
| `-beagle -beagle_CPU -beagle_SSE`       | 用 BEAGLE 库做 CPU/SSE 加速    |
| `-beagle_double`                        | 双精度似然                     |
| `-threads N` / `-instances M`           | 线程数 / BEAGLE 并行实例数        |
| `-burnin N`（treeannotator/logcombiner） | 丢弃的预热比例（%）               |
| `input.xml`                             | BEAUti 生成的模型描述            |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护镜像（bioconda → quay.io/biocontainers → depot.galaxyproject.org），且官方 release 同时提供**预编译二进制包**与**源码**（两条官方路线均保留，预编译为首选）；`main.py` 驱动在宿主机跑。

### 1. 官方预编译二进制包（首选，Linux x86_64）

```bash
# 下载官方 release 预编译包（v2.5.2；Linux 包不带 JRE，需自备 Java 8/11）
curl -fsSL -o ~/software/BEAST.v2.5.2.Linux.tgz \
    https://github.com/CompEvol/beast2/releases/download/v2.5.2/BEAST.v2.5.2.Linux.tgz
mkdir -p ~/software/beast2-2.5.2 && tar zxf ~/software/BEAST.v2.5.2.Linux.tgz -C ~/software/beast2-2.5.2/
echo 'export PATH=$PATH:~/software/beast2-2.5.2/beast/bin' >> ~/.bashrc && source ~/.bashrc
beast -version     # 断言：v2.5.2
```

> 一键安装也可直接运行 `native/install.sh`（Linux x64 用官方包精确装 2.5.2；其它平台回落 conda；版本默认 2.5.2，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

官方源码仓库用 Apache Ant（`build.xml`）构建：

```bash
git clone https://github.com/CompEvol/beast2.git && cd beast2
ant build_all_BEAST          # 或 ant dist_all_BEAST 打包；产物在 release/ 下
# 生成的 release/ 目录即与官方预编译包同构（beast/bin/{beast,beauti,treeannotator,...}）



# BEAGLE - 加速计算库（可选）
# 下载地址：https://github.com/beagle-dev/beagle-lib
wget https://github.com/beagle-dev/beagle-lib/archive/v3.1.2.tar.gz -O ~/software/beagle-lib-3.1.2.tar.gz
tar zxf ~/software/beagle-lib-3.1.2.tar.gz
cd beagle-lib-3.1.2/
./autogen.sh 
./configure --prefix=/opt/biosoft/beagle-lib-3.1.2
make -j 8
make install
echo 'export PKG_CONFIG_PATH=/opt/biosoft/beagle-lib-3.1.2/lib/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/opt/biosoft/beagle-lib-3.1.2/lib/:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/opt/biosoft/beagle-lib-3.1.2/include:$C_INCLUDE_PATH' >> ~/.bashrc

# Tracer - 结果分析工具
# 下载地址：http://tree.bio.ed.ac.uk/software/tracer/
wget https://github.com/beast-dev/tracer/releases/download/v1.7.1/Tracer_v1.7.1.tgz -P ~/software
tar zxf ~/software/Tracer_v1.7.1.tgz -C /opt/biosoft/
chmod 755 /opt/biosoft/Tracer_v1.7.1/bin/tracer 
echo 'PATH=$PATH:/opt/biosoft/Tracer_v1.7.1/bin/' >> ~/.bashrc
source ~/.bashrc
```

### 3. Conda / brew（包管理器安装，备选）

```bash
# bioconda 无 beast2=2.5.2（有 2.4.5/2.5.0/2.6.x/2.7.7），最接近的 2.5 系列为 2.5.0
mamba create -n beast2-native -c conda-forge -c bioconda beast2=2.5.0 openjdk=11
conda activate beast2-native
beast -version   # 断言：v2.5.0
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install beast2
beast -version   # 断言
# 注：brewsci/bio beast2 当前 2.6.3，与 meta 登记 2.5.2 略有差异（版本以 formula 为准）；
#     homebrew-core 的 `beast`（beast.community，v10.x）为同名异义的不同软件，勿混用。
```

### 4. Docker（官方镜像）

```bash
# quay/depot 无 beast2:2.5.2（有 2.5.0 / 2.7.7）；取最接近的 2.5.0
docker pull quay.io/biocontainers/beast2:2.5.0--hf1b8bbb_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/beast2:2.5.0--hf1b8bbb_0 beast -version
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull beast2.sif docker://depot.galaxyproject.org/singularity/beast2:2.5.0--hf1b8bbb_0
apptainer run -B $PWD:/data -H /data beast2.sif beast -version
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证 + 自省断言；beast 已安装则额外冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/beast2/overview>

* **Docker**：`docker pull quay.io/biocontainers/beast2:2.5.0--hf1b8bbb_0`（另有 `2.7.7--he65b2d3_0`）

* **Singularity**：<https://depot.galaxyproject.org/singularity/beast2%3A2.5.0--hf1b8bbb_0>

* **官方预编译包**：<https://github.com/CompEvol/beast2/releases/download/v2.5.2/BEAST.v2.5.2.Linux.tgz>（sha256 `2feb2281…`）

* **官方源码 / 文档**：<https://github.com/CompEvol/beast2>、<https://www.beast2.org/>

* 安装方式（本地）：`mamba create -n beast2 -c conda-forge -c bioconda beast2=2.5.0 openjdk=11`

* 官方无 nf-core 模块（`modules/nf-core/beast2` 404）、无 snakemake-wrappers（`bio/beast2` 404）——如需流程集成请以本模块 `native/main.py` 兜底。

## 版本

* beast2 **2.5.2**（官方 GitHub 预编译包 `BEAST.v2.5.2.Linux.tgz`）

* 构建路线：官方镜像 / conda 提供（quay.io/biocontainers/beast2 / depot.galaxyproject.org，tag 为 `2.5.0`/`2.7.7`；本地不再自建容器）

* 官方渠道版本对照：bioconda `beast2` 2.4.5/2.5.0/2.6.x/2.7.7（无 2.5.2）；homebrew brewsci/bio `beast2` 2.6.3；native 登记以官方预编译包 2.5.2 为准

* 运行依赖：Java 8/11（Java ≥20 因 `Thread.stop` 移除会报错）
