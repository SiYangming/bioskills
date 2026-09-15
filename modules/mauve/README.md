# mauve 软件模块

> 汇总说明：本 README 合并 native 实现用法；安装方式见下方各节，容器与 conda 信息记录于此。
>
> **版本提示**：本模块以文档 14.md「十四、Mauve」采用的 **Mauve 2.4.0** 为准（附录 v2.3.1 属淘汰技术，不登记）。
> 官方分发 **预编译二进制包**（`mauve_linux_2.4.0.tar.gz`）与 **源码**（GitHub）两条路线；bioconda 包 `mauve`
> 依赖 `mauvealigner` 提供 `progressiveMauve` / `mauveAligner` 命令行工具。

***

## native 实现

# mauve / native — 自包含多基因组比对与可视化驱动

Mauve 2.4.0 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

Mauve 是一种多基因组比对工具，能够识别基因组间的同源区域（包括重排、倒位等），并以可视化的方式展示基因组结构变异。

三个子命令覆盖比对与可视化链路：

| 子命令              | 命令                                                                                       | 作用                                     |
| ---------------- | ---------------------------------------------------------------------------------------- | -------------------------------------- |
| `align`          | `progressiveMauve --output=<xmfa> [--backbone-output= …] <genome1> <genome2> …`            | 多基因组渐进式比对 → XMFA + backbone            |
| `apply_backbone` | `progressiveMauve --apply-backbone=<xmfa> --output=<out> [--hmm-p-go-homologous= …]`       | 对已有 XMFA 重新评估 backbone（同源/非同源 HMM 概率） |
| `gui`            | `mauve <alignment.xmfa>`                                                                 | Mauve 图形界面查看比对（需图形环境）                  |

> progressiveMauve 的 `--output` 缺省时写 stdout；`align` / `apply_backbone` 的 `--tmpdir` 映射为官方
> `--scratch-path-1=<tmpdir>`。

## 用法

```bash
# CLI 直跑
python main.py align genome1.fasta genome2.fasta genome3.fasta \
    --output=alignment.xmfa --backbone-output=alignment.backbone
python main.py align genome1.fasta genome2.fasta \
    --output=mums.xmfa --mums                          # 仅求 MUM
python main.py apply_backbone alignment.xmfa --output=rebuilt.xmfa
python main.py gui alignment.xmfa

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；progressiveMauve / Mauve 单线程，`--threads` 为占位
（不注入命令行），JVM 堆经 `JAVA_OPTS` 透传。

## 实战示例：多基因组比对与可视化

```bash
mkdir -p Mauve && cd Mauve
cp Malassezia_sympodialis.genome_V01.fasta IDBA.fasta MaSuRCA.fasta ./

# 11.2 运行 Mauve 多基因组比对（progressiveMauve 为多基因组比对算法）
progressiveMauve --output=alignment.xmfa \
    Malassezia_sympodialis.genome_V01.fasta \
    IDBA.fasta \
    MaSuRCA.fasta
# 输出文件：
#   alignment.xmfa   比对结果（eXtended Multi-Fasta Alignment）
#   alignment.backbone  保守区域坐标

# 11.3 结果可视化（需图形界面支持）
mauve alignment.xmfa
```

等价能力由 `native/main.py` 的 `align` / `apply_backbone` / `gui` 子命令提供（见上「用法」）：
`align` 直接对应 `progressiveMauve --output=…`，`gui` 对应 `mauve alignment.xmfa`。

### 参数说明

| 参数                    | 子命令              | 说明                          |
| --------------------- | ---------------- | --------------------------- |
| `--output`            | align/apply_backbone | 输出 XMFA 比对文件（默认 stdout）     |
| `--backbone-output`   | align/apply_backbone | backbone 保守区坐标文件            |
| `--output-guide-tree` | align            | 输出比对所用系统发育引导树（NEWICK）       |
| `--seed-weight`       | align            | 初始锚点种子权重                    |
| `--weight`            | align            | 最小 LCB 权重/断点罚分              |
| `--min-scaled-penalty`| align            | 缩放后最小断点罚分                   |
| `--disable-backbone`  | align            | 关闭 backbone 检测              |
| `--collinear`         | align            | 假定输入序列共线（无重排）               |
| `--mums`              | align            | 仅求 MUM（不做 LCB 判断）           |
| `--seed-family`       | align            | 使用 spaced seed family 提升灵敏度 |
| `--hmm-p-go-homologous` / `--hmm-p-go-unrelated` | apply_backbone | 同源/非同源 HMM 转移概率（默认 0.0001 / 0.000001） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方提供两条安装路线：**预编译二进制包**（Linux x64，`mauve_linux_2.4.0.tar.gz`）为首选，
**源码编译**（GitHub `koadman/mauve`，官方 developer-guide「Building from source」）并列保留；
同时官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）已维护镜像/conda 包。

### 1. 官方预编译二进制包（首选）

官方下载页 <http://darlinglab.org/mauve/download.html> 提供 Linux 预编译包：

```bash
wget http://darlinglab.org/mauve/downloads/mauve_linux_2.4.0.tar.gz -P ~/software/
tar zxf ~/software/mauve_linux_2.4.0.tar.gz -C ~/software/
# 解压得 ~/software/mauve_2.4.0/，命令行工具在 linux-x64/，GUI 启动脚本 Mauve 在顶层
echo 'export PATH=$PATH:~/software/mauve_2.4.0/linux-x64:~/software/mauve_2.4.0' >> ~/.bashrc
source ~/.bashrc
progressiveMauve --version   # 断言
```

> 一键安装直接 `bash native/install.sh --method binary`（下载官方 tarball → 解压到 `~/software/mauve-2.4.0`
> → 写 PATH → 断言 `progressiveMauve --version`；官方 tarball 仅 Linux x86_64 可用）。
> sha256 校验值取自官方下载实测（2026-09）。

### 2. 官方源码编译（并列保留）

官方源码仓库 <https://github.com/koadman/mauve>；编译步骤见官方 developer-guide
<https://darlinglab.org/mauve/developer-guide/building.html>。源码编译较繁（依赖 boost / libGenome /
muscle / libMems，再编译 mauveAligner），官方给出「brief instructions」：

```bash
# 0. 依赖（Debian/Ubuntu）
sudo apt-get update
sudo apt-get install g++ make pkg-config subversion libtool autoconf libbz2-dev libz-dev bzip2 ant openjdk-7-jdk
# 1. 检出构建脚本并编译
svn co https://svn.code.sf.net/p/mauve/code/build_scripts
cd build_scripts
./build_linux_x64.sh
# 产物位于 build/mauve/dist/
```

> 完整的手工分步编译（libGenome → muscle → libMems → mauveAligner → ant 打包 GUI）见官方 developer-guide
> 「Building from source」页面；此处不复制以免与官方漂移。

### 3. Conda（包管理器安装，备选）

```bash
mamba create -n mauve -c conda-forge -c bioconda mauve=2.4.0.r4736
conda activate mauve
progressiveMauve --version   # 断言（mauve 依赖 mauvealigner，提供 progressiveMauve / mauveAligner）
```

> **无 brew 块**：2026-09 核实 homebrew-core（`formulae.brew.sh/api/formula/mauve.json` 404）与
> brewsci/bio（`Formula/mauve.rb` 404）均无 mauve 公式，故不登记 Homebrew 小节。
>
> 一键安装也可 `bash native/install.sh`（默认 auto：有 conda/mamba 走 bioconda `mauve=2.4.0.r4736`；
> 无 conda 时回退官方预编译 tarball。用法：`bash native/install.sh --help`）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mauve:2.4.0.r4736--h43d4aaa_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mauve:2.4.0.r4736--h43d4aaa_3 \
    progressiveMauve --output=/data/alignment.xmfa \
    /data/genome1.fasta /data/genome2.fasta /data/genome3.fasta
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull mauve.sif docker://depot.galaxyproject.org/singularity/mauve:2.4.0.r4736--h43d4aaa_3
apptainer run -B $PWD:/data -H /data mauve.sif \
    progressiveMauve --output=/data/alignment.xmfa \
    /data/genome1.fasta /data/genome2.fasta /data/genome3.fasta
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（三子命令）+ 自省；progressiveMauve 未安装时跳过真实冒烟
```

## 容器与 Conda 链接

* **Mauve 官网**：http://darlinglab.org/mauve/mauve.html

* **下载地址**：http://darlinglab.org/mauve/download.html

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/mauve/overview>

* **Docker**：`docker pull quay.io/biocontainers/mauve:2.4.0.r4736--h43d4aaa_3`

* **Singularity**：<https://depot.galaxyproject.org/singularity/mauve%3A2.4.0.r4736--h43d4aaa_3>

* 官方预编译包：<http://darlinglab.org/mauve/downloads/mauve_linux_2.4.0.tar.gz>

* 安装方式（本地）：`mamba create -n mauve -c conda-forge -c bioconda mauve=2.4.0.r4736`

## 版本

* Mauve **2.4.0**（官方预编译 `mauve_linux_2.4.0.tar.gz`；bioconda 包 `mauve=2.4.0.r4736` +
  依赖 `mauvealigner=1.2.0`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/mauve:2.4.0.r4736--h43d4aaa_3 /
  depot.galaxyproject.org；本地不自建容器）

* 2026-09 核实：nf-core `modules/nf-core/mauve` 404；snakemake-wrappers `bio/mauve` 404；
  homebrew-core 与 brewsci/bio 均无 mauve 公式；progressiveMauve / Mauve 单线程（Java）
