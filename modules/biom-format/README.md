# biom-format 软件模块

> 汇总说明：本 README 记录 BIOM / biom-format（OTU/特征表格式工具，CLI 命令 `biom`）的 native 实现用法与容器/conda 环境信息；安装方式见「环境安装」节。

***

## native 实现

# biom-format / native — 自包含特征表格式转换驱动（biom CLI）

BIOM（Biological Observation Matrix）工具集的本地自包含实现（`source_type: custom`、`type: native`）。BIOM 是 QIIME 1.x/2.x 特征表（OTU/ASV 表）的标准化格式，`biom` CLI 用于其特征表的格式互转与统计。

## 功能

| 子命令              | biom 命令                    | 作用                                        |
| ---------------- | -------------------------- | ----------------------------------------- |
| `convert`        | `biom convert`             | BIOM(HDF5)/TSV/JSON 互转（含 taxonomy 等观测元数据） |
| `summarize-table` | `biom summarize-table`     | 特征表统计摘要（样本数/观测数/总计数/密度等）                  |

## 用法

```bash
# BIOM -> TSV（特征表统计与可视化流程中 table.qza 导出为 feature-table.biom 后）
python main.py convert -i feature-table.biom -o feature-table.tsv --to-tsv

# 经典 OTU 表 -> BIOM(HDF5)
python main.py convert -i otu_table.txt -o table.biom --table-type "OTU table" --to-hdf5

# 特征表统计摘要（物种组成分析）
python main.py summarize-table -i feature-table.biom -o summary.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`biom convert` / `summarize-table` 均为单线程，`--threads` 接受但不注入）。

## 实战示例：特征表导出与统计

BIOM 是微生物组特征表的通用交换格式，QIIME 导出的 `feature-table.biom` 常需转 TSV 供下游（R/Excel）使用，并用 summarize-table 快速查看数据规模。以下为典型用法；等价能力由 `native/main.py` 的 `convert` / `summarize-table` 子命令提供（见上「用法」）。

### 1. BIOM -> TSV（供 R/Excel）

```bash
# QIIME 2 导出：qiime tools export --output-dir ./ table.qza 得到 feature-table.biom
python main.py convert -i feature-table.biom -o feature-table.tsv --to-tsv
head feature-table.tsv
```

### 2. 带观测元数据（taxonomy）导出

```bash
python main.py convert -i feature-table.biom -o feature-table-taxonomy.tsv \
    --to-tsv --header-key taxonomy
```

### 3. 特征表统计摘要

```bash
python main.py summarize-table -i feature-table.biom -o summary.txt
cat summary.txt
# 输出形如：Num samples / Num observations / Total count / Table density 等
```

### 4. 参数说明

| 参数                 | 说明                                        |
| ------------------ | ----------------------------------------- |
| `--to-tsv`         | 输出制表符分隔 TSV（与 `--to-json`/`--to-hdf5` 三选一） |
| `--to-hdf5`        | 输出 BIOM 二进制（HDF5）                        |
| `--to-json`        | 输出 JSON                                   |
| `--table-type`     | 表类型（如 `"OTU table"`）                      |
| `--header-key`     | 观测元数据键（如 taxonomy），转 TSV 时作为额外列            |
| `-m`               | 样本元数据文件                                   |
| `--qualitative`    | summarize-table 以定性（存在/缺失）统计               |
| `--observations`   | summarize-table 增加逐观测统计                   |

> BIOM 作为 QIIME 的 Python 依赖自动安装的 `biom-format` 模块；QIIME 1.x 的 `biom summarize-table -i *.biom`（物种组成分析）与 QIIME 2 导出后的 `biom convert -i feature-table.biom -o feature-table.tsv --to-tsv`（特征表统计与可视化）均可由本模块子命令等价完成。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / pip（包管理器安装）

```bash
mamba create -n biom-format-native -c conda-forge biom-format=2.1.17
conda activate biom-format-native
biom --version   # 断言
```

```bash
# 或用 pip（用户级 venv，无需 conda）
python3 -m venv ~/software/biom-format-2.1.17
~/software/biom-format-2.1.17/bin/pip install biom-format==2.1.17
export PATH="$HOME/software/biom-format-2.1.17/bin:$PATH"
biom --version   # 断言
```

> ⚠️ bioconda 频道 `biom-format` 仅发布到 2.1.7；`2.1.17` 取自 conda-forge（官方容器 tag 为 2.1.17）。一键安装也可直接运行 `native/install.sh`（有 conda 走 conda-forge，否则建用户级 venv 用 pip 安装；用法：`bash native/install.sh --help`）。
>
> brew 无公式（2026-09 核实 homebrew-core 与 brewsci/bio 均无 biom-format/biom），故不提供 brew 小节。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/biom-format:2.1.17
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/biom-format:2.1.17 \
    biom convert -i /data/feature-table.biom -o /data/feature-table.tsv --to-tsv
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull biom-format.sif docker://depot.galaxyproject.org/singularity/biom-format:2.1.17
apptainer run -B $PWD:/data -H /data biom-format.sif \
    biom summarize-table -i /data/feature-table.biom
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证为主；biom 已安装时追加真实 convert + summarize-table 回归
```

## 容器与 Conda 链接

* **Conda（conda-forge）**：<https://anaconda.org/conda-forge/biom-format>

* **Docker**：`docker pull quay.io/biocontainers/biom-format:2.1.17`

* **Singularity**：<https://depot.galaxyproject.org/singularity/biom-format%3A2.1.17>

* 安装方式（本地）：`mamba create -n biom-format -c conda-forge biom-format=2.1.17` 或 `pip install biom-format==2.1.17`

## 版本

* biom-format 2.1.17（conda-forge::biom-format=2.1.17；官方容器 tag 2.1.17）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/biom-format / depot.galaxyproject.org；本地不再自建容器）

* nf-core（modules/nf-core/biom-format 404）与 snakemake-wrappers（bio/biom-format、bio/biom 404）均无官方模块（2026-09 核实），Nextflow/Snakemake 场景以本模块 native biom CLI 驱动为兜底
