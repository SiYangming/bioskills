# jcvi 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 无 jcvi 实现（2026-09 核实 404），故仅登记 native 实现。

***

## native 实现

# jcvi / native — 共线性与基因组比对可视化驱动（MCscan Python 版）

jcvi 的本地自包含实现（`source_type: custom`、`type: native`）。jcvi 以 Python 包形态分发，
无独立命令行二进制，统一以 `python -m jcvi...` 驱动。

## 功能

**jcvi**（MCscan Python版）是一个功能强大的基因组比较和共线性分析工具包，是 MCScanX 的 Python 重写版。它提供了更丰富的可视化功能，包括点阵图（dotplot）、共线性圈图（circos风格）、基因结构比较变异分析、宏共线性和微共线性分析等。

| 子命令         | 命令                                                                                   | 作用                            |
| ----------- | ------------------------------------------------------------------------------------ | ----------------------------- |
| `ortholog`  | `python -m jcvi.compara.catalog ortholog <sp1> <sp2> [--cscore F] [--no_strip_names] [--cpus N]` | LAST/BLAST + MCscan 计算共线性锚点  |
| `dotplot`   | `python -m jcvi.graphics.dotplot <anchors> [--title S] [-o out]`                     | 共线性点阵图（dotplot）                |
| `karyotype` | `python -m jcvi.graphics.karyotype <seqids> <layout> [-o out]`                       | 共线性圈图 / 核型图                    |
| `synteny`   | `python -m jcvi.graphics.synteny <blocks> <bed> <layout> [--outputprefix P]`         | 微共线性图（synteny）                 |

线程经 `--cpus` 注入到 `ortholog`（优先级：`--threads` > `per_subcommand_threads` > `default_cpus`）；
绘图子命令接受 `--threads` / `--tmpdir` 仅为接口统一。

> ⚠️ CLI 说明：14.md 教程中的 `jcvi.graphics.karyotype --layout=circos ...` 与 `jcvi.graphics.synteny
> --regions=...` 属旧版写法；jcvi 1.6.7 实际 CLI 为 **位置参数**（`karyotype <seqids> <layout>`、
> `synteny <blocks> <bed> <layout>`），本模块按 1.6.7 实际 CLI 构造命令（已核对官方源码）。

## 用法

```bash
# 1) 共线性锚点（LAST/BLAST + MCscan）
python main.py ortholog laame plost --cscore 0.5 --no-strip-names --threads 8

# 2) 点阵图
python main.py dotplot laame.plost.anchors --title "Laccaria vs Pleurotus" -o dot.pdf

# 3) 共线性圈图（seqids + layout 位置参数）
python main.py karyotype seqids layout -o karyotype.pdf

# 4) 微共线性图
python main.py synteny blocks.bed laame.bed layout -o synteny.pdf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：两物种基因组共线性检测与发表级出图

jcvi 以 LAST/BLAST 比对 + MCscan 算法计算共线性，并提供点阵图、圈图、微共线性图等可视化，适合产出
发表级图片。以下为 14.md 教程流程；等价能力由 `native/main.py` 的 `ortholog` / `dotplot` / `karyotype`
/ `synteny` 子命令提供（见上「用法」）。

### 1. 数据准备

```bash
# 需要 GFF/GTF 注释与基因组序列（jcvi 需先转换为 .bed/.cds）
python -m jcvi.formats.gff bed --type=mRNA --key=ID laame.gff3 -o laame.bed
python -m jcvi.formats.fasta format laame.cds.fasta laame.cds
# 同理处理 plost
```

### 2. 计算共线性区块

```bash
# 等价 CLI：
python main.py ortholog laame plost --cscore 0.5 --no-strip-names
# -> laame.plost.anchors / laame.plost.blocks / laame.plost.last 等
```

### 3. 出图

```bash
# 点阵图
python main.py dotplot laame.plost.anchors --title "Laccaria amethystina vs Pleurotus ostreatus" -o laame.plost.dotplot.pdf

# 共线性圈图（seqids 每行一个 seqid；layout 指定轨道顺序/颜色）
printf 'la1\npl1\n' > seqids
printf 'la1,0,1,r,laame\npl1,0,1,b,plost\n' > layout
python main.py karyotype seqids layout -o karyotype.pdf

# 微共线性图
python main.py synteny laame.plost.blocks laame.bed layout -o synteny.pdf
```

### 4. 参数说明

| 参数                 | 说明                                       |
| ------------------ | ---------------------------------------- |
| `--cscore`         | ortholog 的 C-score 阈值（默认取 jcvi 内置 0.7）   |
| `--no_strip_names` | 不简化序列名称（保留完整基因名）                         |
| `--cpus`           | ortholog 线程数（由 `--threads` 注入）           |
| `--title`          | dotplot 图标题                              |
| `seqids` / `layout` | karyotype/synteny 的位置参数（seqid 列表 / 轨道布局） |
| `--outputprefix`   | synteny 输出前缀                             |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具本体；
`main.py` 驱动在宿主机跑。jcvi 官方以 **PyPI / conda** 分发（无预编译二进制包、无源码编译路线），
宿主机首选 `pip install jcvi`。

### 1. Conda（包管理器安装）

```bash
mamba create -n jcvi-native -c conda-forge -c bioconda jcvi=1.6.7
conda activate jcvi-native
python -m jcvi -h
```

> 说明：Homebrew 两源均未找到 jcvi 公式（homebrew-core `formulae.brew.sh/api/formula/jcvi.json`
> 返回 404；brewsci/bio `Formula/jcvi.rb` 返回 404，2026-09 核实），故不写 brew 小节。

### 2. PyPI（pip 安装）

```bash
pip install jcvi==1.6.7
python -m jcvi -h
```

> 依赖：numpy / scipy / matplotlib / biopython（conda 包已内置；pip 会自动解析依赖）。
> 一键安装也可直接运行 `native/install.sh`（auto：有 conda/mamba 走 bioconda，否则 pip；版本默认 1.6.7。
> 用法：`bash native/install.sh --help`）。

### 3. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/jcvi:1.6.7--py312hfcd9dac_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/jcvi:1.6.7--py312hfcd9dac_0 \
    python -m jcvi.compara.catalog ortholog laame plost --cpus 8
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull jcvi.sif docker://depot.galaxyproject.org/singularity/jcvi:1.6.7--py312hfcd9dac_0
apptainer run -B $PWD:/data -H /data jcvi.sif \
    python -m jcvi.compara.catalog ortholog laame plost --cpus 8
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（jcvi 未安装时不做真实比对/出图）
```

## 版本

* jcvi 1.6.7（bioconda::jcvi=1.6.7；quay tag `1.6.7--py312hfcd9dac_0`；PyPI 1.6.7）
* 构建路线：官方镜像 / PyPI / conda（quay.io/biocontainers/jcvi / depot.galaxyproject.org；本地不再自建容器）
* nf-core / snakemake-wrappers 官方均无 jcvi 实现（2026-09 核实 404）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/jcvi/overview>
* **PyPI**：<https://pypi.org/project/jcvi/>
* **Docker**：`docker pull quay.io/biocontainers/jcvi:1.6.7--py312hfcd9dac_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/jcvi%3A1.6.7--py312hfcd9dac_0>
* 安装方式（本地）：`pip install jcvi==1.6.7` 或 `mamba create -n jcvi -c conda-forge -c bioconda jcvi=1.6.7`
