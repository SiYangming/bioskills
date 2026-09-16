# figtree 软件模块

> 汇总说明：本 README 说明 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# figtree / native — 自包含系统发育树可视化/导出驱动

FigTree 的本地自包含实现（`source_type: custom`、`type: native`；Java GUI 工具，无界面导出为 Agent 主用法）。

## 功能

FigTree 是一个用于可视化和编辑系统发育树的 Java 应用程序，支持多种树文件格式（Newick、Nexus、NHX 等），常用于分子钟分析结果的可视化。

| 子命令     | 命令                                                                                                          | 作用                       |
| ------- | ----------------------------------------------------------------------------------------------------------- | ------------------------ |
| `export` | `java <JAVA_OPTS> -Djava.awt.headless=true -jar figtree.jar -graphic <PDF|SVG|PNG|JPEG> [-width i] [-height i] <tree> <out>` | 无界面导出出版级图片 |
| `view`   | `java <JAVA_OPTS> -jar figtree.jar <tree>`                                                                   | 打开交互式 GUI（需显示环境）         |

JVM 堆内存与临时目录经 `JAVA_OPTS`（`-Xmx2g -Djava.io.tmpdir=<tmpdir>`）透传。

## 用法

```bash
# CLI 直跑
python main.py export tree_fullName.RAxML out.pdf -graphic PDF
python main.py export tree.tre out.png -graphic PNG -width 320 -height 320
python main.py view tree_fullName.RAxML          # 需显示环境

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：树文件处理与可视化

RAxML/IQ-TREE/BEAST2 产出的树（`RAxML_bipartitions.*`、`.treefile`、FigTree.tre 等）可用 FigTree 可视化；批量替换叶名为全称后导出出版级图片。等价能力由 `native/main.py` 的 `export` 子命令提供（见上「用法」）。

```bash
# 1. 将树文件中的物种名缩写换成全称（配合 source.txt 做后缀替换）
cp RAxML_bipartitions.out_codon tree_abbr.RAxML
cp tree_abbr.RAxML tree_fullName.RAxML
cut -f 1,2 ../../a.preparing_data/source.txt | \
    perl -p -e 's/\t/\t\"/; s/$/\"/;' | \
    perl -p -e 's#\s+#/#; s#^#perl -p -i -e "s/#; s#\n$#/" tree_fullName.RAxML\n#;' | \
    perl -p -e 's#/\"#/\\\"#; s#\"/#\\\"/#;' | sh

# 2. 用 FigTree 可视化/导出（GUI：直接打开；无界面导出见下）
java -jar $FIGTREE_HOME/lib/figtree.jar tree_fullName.RAxML
java -jar $FIGTREE_HOME/lib/figtree.jar -graphic PDF tree_fullName.RAxML tree_fullName.pdf

# 3. 分子钟分析结果（BEAST2/mcmctree/r8s）的树同样可视化
java -jar $FIGTREE_HOME/lib/figtree.jar tree_fullName.BEAST2
```

### 参数说明

| 参数         | 说明                                    |
| ---------- | ------------------------------------- |
| `-graphic` | 导出格式：PDF / SVG / PNG / JPEG（无界面导出必填）   |
| `-width`   | 图形宽度（像素；PNG/JPEG 用）                   |
| `-height`  | 图形高度（像素；PNG/JPEG 用）                   |
| `-url`     | 输入文件按 URL 读取（管道场景）                    |
| `<tree-file>`    | 输入树（Newick / NEXUS / NHX）             |
| `<graphic-file>` | 导出图片路径（export）                        |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；官方另提供**预编译包**与**源码**，两条官方路线均保留。

### 1. 官方预编译二进制包（首选）

```bash
# 下载官方预编译包（GitHub release v1.4.4）
wget https://github.com/rambaut/figtree/releases/download/v1.4.4/FigTree_v1.4.4.tgz -P ~/software/

# 解压到用户级前缀（无需 root；禁 /opt/biosoft、/home/train）
mkdir -p ~/software/FigTree_v1.4.4
tar zxf ~/software/FigTree_v1.4.4.tgz -C ~/software/FigTree_v1.4.4 --strip-components=1

# 设置 FIGTREE_HOME 并运行
export FIGTREE_HOME=~/software/FigTree_v1.4.4
java -jar $FIGTREE_HOME/lib/figtree.jar -help
```

> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `figtree`，无 conda 时下载官方预编译包到 `~/software/FigTree_v1.4.4` 并写 PATH、设 `FIGTREE_HOME`；版本默认 1.4.4，与下方 `software_versions` 对齐，内嵌官方 tgz sha256。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档（tag v1.4.4；ant 构建）
wget https://github.com/rambaut/figtree/archive/refs/tags/v1.4.4.tar.gz -P ~/software/
tar zxf ~/software/v1.4.4.tar.gz -C ~/software/
cd ~/software/figtree-1.4.4
# 依赖 Apache Ant + JDK（仓库 build.xml）
ant dist
java -jar release/FigTree_v1.4.4/lib/figtree.jar -help
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n figtree-native -c conda-forge -c bioconda figtree=1.4.4
conda activate figtree-native
figtree -help   # 断言（bioconda 提供 figtree 可执行）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install figtree
figtree -help            # 断言（brew 当前 1.4.4，与 meta 登记 1.4.4 一致，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/figtree:1.4.4--hdfd78af_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/figtree:1.4.4--hdfd78af_1 \
    -graphic PDF tree_fullName.RAxML tree_fullName.pdf
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull figtree.sif docker://depot.galaxyproject.org/singularity/figtree:1.4.4--hdfd78af_1
apptainer run -B $PWD:/data -H /data figtree.sif -graphic PDF /data/tree.nwk /data/tree.pdf
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（FigTree 为 GUI 工具，无 jar 时不做真实导出）
```

## 版本

* figtree 1.4.4（bioconda::figtree=1.4.4；官方 GitHub release v1.4.4）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/figtree / depot.galaxyproject.org；本地不再自建容器）

* 官方层：nf-core / snakemake-wrappers 均无 figtree（2026-09 核实 404）

## 容器与 Conda 链接

* **官网**：http://tree.bio.ed.ac.uk/software/figtree/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/figtree/overview>

* **Docker**：`docker pull quay.io/biocontainers/figtree:1.4.4--hdfd78af_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/figtree%3A1.4.4--hdfd78af_1>

* 安装方式（本地）：`mamba create -n figtree -c conda-forge -c bioconda figtree=1.4.4`（或 `bash native/install.sh`）
