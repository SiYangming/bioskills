# emperor 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；环境安装见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# emperor / native — 自包含 PCoA 交互式可视化驱动

Emperor 的本地自包含实现（`source_type: custom`、`type: native`；Python 库）。

## 功能

Emperor 是一款用于微生物组数据交互式可视化的工具，主要用于展示主坐标分析（PCoA）结果。它支持 3D 可视化、样本着色、元数据动画等功能，用户可以通过浏览器交互地探索样本间的相似性和差异。Emperor 把排序（ordination，如 PCoA）结果与样本元数据渲染为可在浏览器中交互探索的 3D HTML 可视化。

| 子命令    | 命令                                                                    | 作用                                 |
| ------ | --------------------------------------------------------------------- | ---------------------------------- |
| `plot` | `python3 run_emperor.py --ordination <ord> --metadata <md> --output <html>` | ordination + 元数据 → 交互式 3D HTML 可视化 |

> ⚠️ **入口核实**：Emperor 以 Python 库分发，**无独立命令行二进制**（包内无 `__main__.py`、`setup.py` 无 console_scripts，`python -m emperor` 不是有效入口，2026-09 核实）。本模块以 `run_emperor.py` 驱动 `emperor.core.Emperor` 完成渲染（等价于 QIIME 2 插件的 `qiime emperor plot`）。

## 用法

```bash
# CLI 直跑
python main.py plot ordination.txt sample-metadata.tsv -o emperor.html
python main.py plot unweighted_unifrac_ordination.txt metadata.tsv -o emperor.html \
    --custom-axes DaysSinceExperimentStart --dimensions 3
python main.py plot ordination.txt metadata.tsv -o emperor.html --ignore-missing-samples

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：微生物组 PCoA 可视化

Emperor 是 QIIME 生态的默认 PCoA 可视化工具（QIIME 2 由 `qiime emperor plot` 插件调用、QIIME 1.x 作为可视化组件）。以下为典型用法；等价能力由 `native/main.py` 的 `plot` 子命令提供（见上「用法」）。

### 1. 从 QIIME 2 结果导出 ordination 与元数据

```bash
# QIIME 2 的 *_pcoa_results.qza 导出的 ordination.txt 即为 skbio OrdinationResults 文本格式
qiime tools export --input-path core-metrics-results/unweighted_unifrac_pcoa_results.qza \
    --output-path unweighted_unifrac_ordination
# 得到 unweighted_unifrac_ordination/ordination.txt
```

### 2. 生成交互式 HTML

```bash
python main.py plot unweighted_unifrac_ordination/ordination.txt ../sample-metadata.tsv \
    -o unweighted-unifrac-emperor.html --custom-axes DaysSinceExperimentStart
```

浏览器打开 `unweighted-unifrac-emperor.html` 即可交互探索样本分布（按元数据着色、缩放、动画等）。

### 3. 参数说明

| 参数                         | 说明                                                       |
| -------------------------- | -------------------------------------------------------- |
| `ordination`               | 排序结果文件（skbio OrdinationResults 文本格式，含 Eigvals/Site 等段）  |
| `metadata`                 | 样本元数据表（Tab 分隔，首列样本 ID，需与 ordination 样本 ID 匹配）             |
| `-o`                       | 输出 HTML 文件路径                                              |
| `--custom-axes`            | 自定义轴（元数据列，逗号分隔），如 `DaysSinceExperimentStart`            |
| `--dimensions`             | 保留的排序维度数（默认 5）                                           |
| `--ignore-missing-samples` | 缺元数据的样本改为填充占位值（默认报错）                                     |
| `--remote`                 | 使用远程 CDN 资源（默认使用随包本地资源）                                  |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），`main.py` 驱动在宿主机跑。⚠️ 但官方 biocontainer 版本过旧（`emperor:0.9.3--py27_0`，Python 2.7）：**现代版本（1.0.5）请走 conda-forge / PyPI 安装**。

### 1. Conda / pip（包管理器安装）

```bash
# 推荐：conda-forge（现代版 1.0.5）
mamba create -n emperor -c conda-forge emperor=1.0.5
conda activate emperor

# 或 pip 直装
python3 -m pip install emperor==1.0.5
```

> brew 无该软件公式（2026-09 核实 homebrew-core `formulae.brew.sh/api/formula/emperor.json` 返回 404），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 python3+pip 时 pip 直装 `emperor==1.0.5`，否则建 conda-forge 环境 `emperor`；版本默认 1.0.5，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像，仅旧版）

```bash
# ⚠️ 官方镜像仅旧版（Python 2.7）；现代用法建议用上面的 conda-forge/pip
docker pull quay.io/biocontainers/emperor:0.9.3--py27_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/emperor:0.9.3--py27_0 \
    python /opt/skill/run_emperor.py --ordination /data/ordination.txt \
    --metadata /data/sample-metadata.tsv --output /data/emperor.html
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（同为旧版 py27）
apptainer pull emperor.sif docker://depot.galaxyproject.org/singularity/emperor:0.9.3--py27_0
apptainer run -B $PWD:/data -H /data emperor.sif \
    python /opt/skill/run_emperor.py --ordination /data/ordination.txt \
    --metadata /data/sample-metadata.tsv --output /data/emperor.html
```

### 4. 现代版本（1.0.5）的官方获取

* **conda-forge**：<https://anaconda.org/conda-forge/emperor>（`emperor=1.0.5`）
* **PyPI**：<https://pypi.org/project/emperor/>（`pip install emperor==1.0.5`）
* **源码仓库**：<https://github.com/biocore/emperor>

> 说明：bioconda 上的 emperor 仅 `0.9.51--py27`（Python 2.7 旧包，2026-09 核实），故本模块 modern 版本登记 conda-forge / PyPI 1.0.5；官方渠道已存在，本地不维护 Dockerfile/Apptainer.def。

## 测试

```bash
bash test/run_test.sh   # plot 退化为 argv 构造验证；emperor+skbio 已装时额外真实渲染
```

## 版本

* emperor 1.0.5（conda-forge / PyPI；依赖 scikit-bio、pandas、numpy、scipy）
* 构建路线：官方 conda 提供（conda-forge emperor=1.0.5 / PyPI emperor==1.0.5；bioconda 仅旧版 0.9.51--py27）
* 与 nf-core / snakemake-wrappers 的对应关系：均为 404（无官方子模块/wrapper，见 `software_versions`）

## 相关背景（QIIME）

* QIIME 2：`qiime emperor plot --i-pcoa <pcoa_results.qza> --m-metadata-file <md.tsv> --o-visualization <out.qzv>`（本模块等价能力由 `native/main.py plot` 提供）
* QIIME 1.x：Emperor 作为内置可视化组件

## 容器与 Conda 链接

* **conda-forge**：<https://anaconda.org/conda-forge/emperor>
* **Docker（官方，旧版）**：`docker pull quay.io/biocontainers/emperor:0.9.3--py27_0`
* **Singularity（官方，旧版）**：<https://depot.galaxyproject.org/singularity/emperor%3A0.9.3--py27_0>
* **PyPI**：<https://pypi.org/project/emperor/>
* 安装方式（本地）：`python3 -m pip install emperor==1.0.5` 或 `mamba create -n emperor -c conda-forge emperor=1.0.5`
