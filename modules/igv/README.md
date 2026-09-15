# igv 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
>
> 说明：IGV 是 Broad Institute 的本地交互式基因组浏览器（**Java GUI**，需 Java 运行时与显示环境）。官方预编译包为 2.5.3；官方 bioconda/容器仅收录到 2.5.2。

***

## native 实现

# igv / native — 本地基因组浏览器启动器

IGV 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

IGV（Integrative Genomics Viewer）是 Broad Institute 开发的高性能交互式基因组可视化工具，支持多种基因组数据格式的可视化展示和探索，包括 BAM、VCF、GFF3、BigWig、BED 等。

两个子命令覆盖图形界面用法：

| 子命令      | 命令                                                                          | 作用                              |
| -------- | --------------------------------------------------------------------------- | ------------------------------- |
| `launch` | `igv.sh [--genome <id\|.genome>] [--locus <chr:start-end>] [files...]`          | 启动 IGV 图形界面并加载基因组/轨道数据          |
| `batch`  | `igv.sh --batch <script> [--genome <id\|.genome>] [--locus <chr:start-end>] [files...]` | 以批处理脚本运行（脚本内可 goto/snapshot 等） |

> IGV 为 **Java GUI** 工具（需 Java + `DISPLAY`），本驱动只做启动器与命令构造；
> `JAVA_OPTS`（默认 `-Xmx6g`）由 `optimization.env_vars` 透传；`--threads` 为统一接口保留（单实例 GUI，仅供调度参考）。

## 用法

```bash
# CLI 直跑
python main.py launch --genome hg18 --locus chr1:1000-2000 sample.bam sample.vcf
python main.py launch --genome ~/igv/genomes/hg18.genome sample.gff3
python main.py batch --batch snapshot.txt --genome hg18 sample.bam

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例

```bash
# 配置基因组文件
mkdir -p ~/igv/genomes/
cp ~/software/hg18.genome ~/igv/genomes/

# 启动 IGV 图形界面
igv.sh

# 常用操作：
# 1. 加载基因组序列（Genomes -> Load Genome From File）
# 2. 导入 BAM 文件（File -> Load From File，需 .bai 索引）
# 3. 导入 VCF、GFF3、BigWig 等注释文件
# 4. Ctrl+L: 定位到特定位置（如 scaffold_1:1000-2000）
```

### 注意事项

* IGV 需要 Java 环境支持（推荐 Java 8）
* BAM 文件必须带有对应的 .bai 索引文件
* 大型基因组建议使用 `.genome` 文件格式以提高加载速度

> 等价启动能力由 `native/main.py` 的 `launch` / `batch` 子命令提供（见上「用法」）：
> `igv.sh --genome ... --locus ... <files...>` 即 `python main.py launch --genome ... --locus ... <files...>`。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方预编译包（Broad 官网 2.5.3）为首选；官方容器/conda（最高 2.5.2）与官方源码并列作备选。

### 1. Conda / brew（包管理器安装）

```bash
# 注意：bioconda 的 igv 2.5.x 仅收录 2.5.2（无 2.5.3）；如需 2.5.3 走下方官方预编译包
mamba create -n igv-native -c conda-forge -c bioconda igv=2.5.2
conda activate igv-native
igv.sh --version   # 断言（Java 环境需已就绪）
```

```bash
# 或用 Homebrew（公式在 homebrew-core，无需额外 tap）
brew install igv
# 注：brew 当前版本 2.19.8，与 meta 登记 2.5.3 略有差异（以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `igv`（2.5.2），无 conda 时自动下载官方预编译 zip 到 `~/software/igv-2.5.3` 并写 PATH；版本默认 2.5.3，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/igv:2.5.2--0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root；GUI 需挂载 X11
docker run --rm -u $(id -u):$(id -g) \
    -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $PWD:/data -w /data \
    quay.io/biocontainers/igv:2.5.2--0 \
    igv.sh --genome hg18 --locus chr1:1000-2000 /data/sample.bam
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull igv.sif docker://depot.galaxyproject.org/singularity/igv:2.5.2--0
apptainer run --bind $PWD:/data -e DISPLAY=$DISPLAY --bind /tmp/.X11-unix:/tmp/.X11-unix igv.sif \
    igv.sh --genome hg18 --locus chr1:1000-2000 /data/sample.bam
```

### 4. 官方预编译二进制包（首选）

* **官网**：<https://igv.org/doc/desktop/>
* **下载页**：<https://igv.org/doc/desktop/#DownloadPage/>

```bash
# Linux 2.5.3（官方预编译 zip）
wget http://data.broadinstitute.org/igv/projects/downloads/2.5/IGV_Linux_2.5.3.zip -P ~/software/
unzip ~/software/IGV_Linux_2.5.3.zip -d ~/software/
export PATH="$PATH:$HOME/software/IGV_Linux_2.5.3"
igv.sh   # 启动（需 Java + 显示环境）
```

* macOS 对应 `IGV_Mac_2.5.3.zip`；通用包 `IGV_2.5.3.zip`（见下载页同目录）。
* 可直接走 `native/install.sh` 一键部署到 `~/software/igv-2.5.3` 并写 PATH（内嵌官方 zip sha256 校验）。

### 5. 官方源码编译（并列保留）

* **GitHub 源码**：<https://github.com/igvteam/igv>（Java + Gradle 工程）

```bash
git clone --depth 1 --branch 2.5.3 https://github.com/igvteam/igv.git
cd igv
./gradlew  # 依官方 README 构建；产物为可运行的 IGV 发行包
```

## 测试

```bash
bash test/run_test.sh   # GUI 启动器，退化为 argv 构造验证（monkeypatch 二进制解析）
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/igv/overview>

* **Docker**：`docker pull quay.io/biocontainers/igv:2.5.2--0`（2.5.3 未收录；最新 tag 2.19.8--hdfd78af_1）

* **Singularity**：<https://depot.galaxyproject.org/singularity/igv%3A2.5.2--0>

* **官方预编译包**：<https://data.broadinstitute.org/igv/projects/downloads/2.5/IGV_Linux_2.5.3.zip>

* 安装方式（本地）：`mamba create -n igv -c conda-forge -c bioconda igv=2.5.2`（或官方预编译 2.5.3）

## 版本

* igv 2.5.3（官方预编译包，Broad 官网；sha256 见 `native/install.sh`）

* 构建路线：官方预编译二进制（首选）→ 官方镜像/conda（quay.io/biocontainers/igv:2.5.2--0 / depot；本地不再自建容器）

* 差异说明：bioconda/quay 的 igv 2.5.x 仅到 2.5.2，与官方预编译 2.5.3 相差一个 patch；brew 当前 2.19.8（以 formula 为准）

* nf-core 官方仅有 `igv/js`（基于 igv.js 的静态浏览器嵌入，非桌面 IGV）
