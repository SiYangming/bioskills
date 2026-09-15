# tracer 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 无 tracer 实现（2026-09 核实 404），故仅登记 native 实现。

***

## native 实现

# tracer / native — MCMC 收敛检查驱动（Java GUI）

Tracer v1.7.1 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

Tracer 只有一个核心动作：载入 MCMC 日志/trace 文件并打开图形界面做收敛诊断。

| 子命令  | 命令                              | 作用                                             |
| ---- | ------------------------------- | ---------------------------------------------- |
| `run` | `tracer <log> [<log2> ...]`     | 启动 Tracer GUI 并载入一个或多个 MCMC trace/日志文件（BEAST/MrBayes/LAMARC） |

官方 `tracer` 启动器内部即 `java -Xms64m -Xmx10000m -jar lib/tracer.jar "$@"`；
JVM 内存/调优通过环境变量 `JAVA_OPTS` 透传（见 `meta.yaml` 的 `optimization.env_vars`）。

## 用法

```bash
# CLI 直跑
python main.py run beast.log
python main.py run beast.log beast2.log

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（Tracer 为 GUI，线程参数仅为接口统一保留）。

## 实战示例：BEAST2 MCMC 结果的收敛性检查

Tracer 用于查看 MCMC 采样参数的 ESS（有效样本量）、后验估计与 trace 图，判断链是否收敛并确定 burn-in，
是 BEAST2 建树流程的配套诊断工具。以下为批量检查用法；等价能力由 `native/main.py` 的 `run`
子命令提供（见上「用法」）。

### 1. 运行 BEAST2 产生 MCMC 日志

```bash
beast -beagle -beagle_CPU -beagle_SSE -threads 8 input.xml &> beast2.log
```

### 2. 用 Tracer 检查收敛性

```bash
# 载入 BEAST2 日志（GUI 会打开 trace/density/ESS 面板）
tracer input.log

# 也可一次载入多个日志对比（同参数会自动生成 Combined 轨迹）
tracer run1.log run2.log
```

在 Tracer 中查看各参数的 ESS（一般要求 ESS > 200）与 trace 图是否平稳，据此确定 burn-in
比例，例如 10%（`treeannotator -burnin 20` 即 burn-in 前 10%）。

### 3. 参数说明

| 参数             | 说明                                     |
| -------------- | -------------------------------------- |
| `<log>`        | MCMC 日志/trace 文件（Tab 分隔，首行列名，首列 state/generation） |
| `JAVA_OPTS`    | JVM 调优（如 `-Xmx10g`），大日志载入时防止 OOM        |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方同时提供「预编译二进制包」（GitHub release `Tracer_v1.7.1.tgz`，Java 跨平台）与「源码编译」
（GitHub 源码，Java SDK 自编译），两条官方路线均保留；同时 bioconda → quay.io/biocontainers →
depot.galaxyproject.org 有官方镜像，可直拉官方镜像运行工具本体，`main.py` 驱动在宿主机跑。

### 1. 官方预编译二进制包（首选）

* **官网**：<http://tree.bio.ed.ac.uk/software/tracer/>
* **GitHub release**：<https://github.com/beast-dev/tracer/releases>

```bash
# 下载 Tracer v1.7.1
wget https://github.com/beast-dev/tracer/releases/download/v1.7.1/Tracer_v1.7.1.tgz -P ~/software

# 解压到用户目录（无需 root；禁 /opt/biosoft、/home/train）
mkdir -p ~/software/Tracer-1.7.1
tar zxf ~/software/Tracer_v1.7.1.tgz -C ~/software/Tracer-1.7.1 --strip-components=1
chmod 755 ~/software/Tracer-1.7.1/bin/tracer
echo 'export PATH=$PATH:~/software/Tracer-1.7.1/bin/' >> ~/.bashrc
source ~/.bashrc

# 验证（Tracer 无 --version：断言启动器与 jar 存在）
ls ~/software/Tracer-1.7.1/bin/tracer ~/software/Tracer-1.7.1/lib/tracer.jar
```

> 一键安装也可直接运行 `native/install.sh`（auto：有 conda/mamba 时建 bioconda 环境 `tracer`，
> 无 conda 时自动下载官方预编译包到 `~/software/Tracer-1.7.1` 并写 PATH；版本默认 1.7.1，
> 与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

Tracer 为 Java 程序，官方 GitHub 仓库提供源码；如需自行编译，需 JDK（`javac` + `jar`）。

```bash
# 克隆官方源码（如需从源码构建）
git clone https://github.com/beast-dev/tracer.git
cd tracer
# 按仓库 README 说明用 JDK 构建（产物为 lib/tracer.jar）；亦可直接使用官方预编译包（上节）
```

> 说明：官方预编译包已含 `lib/tracer.jar`，一般无需自编译；本节按「官方双路线均保留」规则并列记录。

### 3. Conda（包管理器安装）

```bash
mamba create -n tracer-native -c conda-forge -c bioconda tracer=1.7.1
conda activate tracer-native
```

> 说明：Homebrew 两源均未找到 tracer 公式（homebrew-core `formulae.brew.sh/api/formula/tracer.json`
> 返回 404；brewsci/bio `Formula/tracer.rb` 返回 404，2026-09 核实），故本模块不写 brew 小节。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/tracer:1.7.1--1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/tracer:1.7.1--1 tracer /data/input.log
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull tracer.sif docker://depot.galaxyproject.org/singularity/tracer:1.7.1--1
apptainer run -B $PWD:/data -H /data tracer.sif /data/input.log
```

> 注：GUI 需要 X11/Wayland 转发；无头服务器上 Tracer 的图形分析不可用，请在有显示环境或
> X11 转发下运行。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（Tracer 为 GUI，不执行真实界面）
```

## 版本

* tracer 1.7.1（bioconda::tracer=1.7.1；quay tag `1.7.1--1`）
* 构建路线：官方预编译包 / 官方源码 / 官方镜像（quay.io/biocontainers/tracer / depot.galaxyproject.org；本地不再自建容器）
* nf-core / snakemake-wrappers 官方均无 tracer 实现（2026-09 核实 404）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/tracer/overview>
* **Docker**：`docker pull quay.io/biocontainers/tracer:1.7.1--1`
* **Singularity**：<https://depot.galaxyproject.org/singularity/tracer%3A1.7.1--1>
* 安装方式（本地）：`mamba create -n tracer -c conda-forge -c bioconda tracer=1.7.1`
