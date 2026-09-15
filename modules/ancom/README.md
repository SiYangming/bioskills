# ancom 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；环境安装见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# ancom / native — 自包含差异丰度分析驱动

ANCOM 的本地自包含实现（`source_type: custom`、`type: native`；R 脚本，经 Rscript 驱动）。

## 功能

ANCOM（Analysis of Composition of Microbiomes）基于成对 log-ratio 检验（W 统计量）检测两组样本间的差异丰度 taxa，考虑数据的组成性（compositional nature）、控制假阳性。

| 子命令      | 命令                                                                        | 作用                                             |
| -------- | ------------------------------------------------------------------------- | ---------------------------------------------- |
| `analyze` | `Rscript run_ancom.R <params.tsv>`（由 `python main.py analyze` 生成 params） | feature_table_pre_process 预处理 → ANCOM 检测差异丰度 taxa |

> ⚠️ **入口核实**：ANCOM 以 R 脚本分发，**无独立命令行二进制**；代码归档于 `FrederickHuangLin/ANCOM`（含 `programs/ancom.R`，提供 `feature_table_pre_process()` 与 `ANCOM()`）。本模块以 Rscript 驱动该脚本。
>
> ⚠️ **假设**：ANCOM 需满足「>75% 的 features 在两组间无丰度差异」假设，且**主分组变量须恰为两组**（超过两组会报错）。

## 用法

```bash
# CLI 直跑（先过滤样本 + 加 pseudocount，确保满足假设）
python main.py analyze feature-table.tsv sample-metadata.tsv \
    --sample-var SampleID --main-var Subject -o ancom_result.csv
# 纵向/多组场景（结构零识别 + 随机效应）
python main.py analyze table.tsv metadata.tsv --sample-var Sample.ID --main-var delivery \
    --group-var delivery --neg-lb --rand-formula "~ 1 | studyid" -o res.csv

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；ANCOM 源码目录经 `--ancom-home`（缺省用环境变量 `ANCOM_HOME`，再回退 `~/software/ANCOM`）。

## 实战示例：两组间差异丰度分析

ANCOM 是 QIIME 2 `qiime composition ancom` 插件。以下为 QIIME 2 语境下的典型步骤与等价本地用法；等价能力由 `native/main.py` 的 `analyze` 子命令提供（见上「用法」）。

QIIME 2 内置，通过 `qiime composition ancom` 插件调用。

**分析假设**：绝大部分 features（>75%）在两组比较中没有丰度差异。

### 1. QIIME 2 语境（对照）

```bash
# 过滤样品（仅取 BodySite='gut'，缩小差异、更好满足 >75% 假设）
qiime feature-table filter-samples --i-table table.qza \
    --m-metadata-file sample-metadata.tsv --p-where "BodySite='gut'" --o-filtered-table gut-table.qza
# 加 pseudocount（组成性分析不能含零值）
qiime composition add-pseudocount --i-table gut-table.qza --o-composition-table comp-gut-table.qza
# 两组比较（Subject 列须恰有两种取值）
qiime composition ancom --i-table comp-gut-table.qza \
    --m-metadata-file sample-metadata.tsv --m-metadata-category Subject --o-visualization ancom-Subject.qzv
```

### 2. 本地等价（本模块）

```bash
# 准备 feature-table.tsv（首列特征 id，其余列样本；绝对丰度）+ sample-metadata.tsv（首列样本 id）
python main.py analyze feature-table.tsv sample-metadata.tsv \
    --sample-var SampleID --main-var Subject -o ancom_result.csv
# 结果 CSV 含 W 统计量与 detected_0.9/0.8/0.7/0.6 检出标记（detected_0.7 常用作判定）
```

### 3. 参数说明

| 参数                | 说明                                                        |
| ----------------- | --------------------------------------------------------- |
| `feature_table`   | 特征丰度表（首列特征 id，其余列样本；**绝对丰度**）                              |
| `metadata`        | 样本元数据表（首列样本 id）                                           |
| `--sample-var`    | 元数据中样本 ID 列名（如 `Sample.ID`）                                |
| `--main-var`      | 主分组变量列名（分类变量，须恰为两组）                                       |
| `--group-var`     | 结构零识别的分组列（纵向/多组场景可选）                                      |
| `--out-cut`/`--zero-cut`/`--lib-cut`/`--neg-lb` | 预处理阈值（离群 0.05 / 零比例 0.9 / 文库大小 0 / 结构零判据，见 `feature_table_pre_process`） |
| `--p-adj-method`/`--alpha` | 多重校正方法与显著性水平（默认 BH / 0.05）                       |
| `--adj-formula`/`--rand-formula` | 协变量校正公式 / 随机效应公式（nlme::lme）                    |
| `--ancom-home`    | ANCOM 源码目录（含 `programs/ancom.R`）                           |

## 环境安装（自建容器兜底；原始 ANCOM 无官方镜像）

原始 ANCOM 为 GitHub 代码归档（无 releases/tags），**bioconda / quay.io/biocontainers / depot.galaxyproject.org 均无 ancom 包**（2026-09 核实 bioconda `ancom`/`ancombc`/`r-ancombc` 均 404）→ 走自建兜底（容器配方：`native/Dockerfile` + `native/Apptainer.def`）。后继实现 ANCOM-BC 有官方渠道（见 §4）。

### 1. R / Conda（包管理器安装）

```bash
# R 直装（本机 R>=4.0）：装依赖 + 下载 ANCOM 源码到 ~/software/ANCOM
Rscript -e 'install.packages(c("nlme","tidyverse","compositions"), repos="https://cloud.r-project.org")'
git clone https://github.com/FrederickHuangLin/ANCOM-Code-Archive.git ~/software/ANCOM
export ANCOM_HOME=~/software/ANCOM

# 或 conda（隔离环境）
mamba create -n ancom -c conda-forge r-base r-tidyverse r-compositions r-nlme
```

> brew 无该软件公式（homebrew-core / brewsci-bio 均无 `ancom`），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 Rscript 时装 R 依赖 + 部署 ANCOM 源码，否则建 conda-forge 环境 `ancom`；默认版本 2.1，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（自建镜像，debian:bookworm-slim）

```bash
# 自建镜像（apt 最小化装 r-base-core + r-cran-* 依赖 + ANCOM 源码）
docker build -t ancom:2.1 -f native/Dockerfile native/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    ancom:2.1 Rscript /opt/skill/run_ancom.R /data/params.tsv
```

> 说明：`params.tsv` 由 `native/main.py analyze` 生成（键值对，含 feature_table/metadata/output/main_var 等）；容器内亦发布 `run_ancom.R` 于 `/opt/skill/`。

### 3. Apptainer / Singularity

```bash
# 自建 sif（与 Dockerfile 同构）
apptainer build ancom.sif native/Apptainer.def
apptainer run -B $PWD:/data -H /data ancom.sif Rscript /opt/skill/run_ancom.R /data/params.tsv
```

### 4. 后继实现 ANCOM-BC（官方渠道）

原始 ANCOM 已归档且不再维护，官方推荐后继 **ANCOM-BC / ANCOM-BC2**（同一 Bioconductor 包 `ANCOMBC`，含 `ancom()`/`ancombc()`/`ancombc2()` 函数），有官方 conda/容器渠道：

```bash
# 官方 biocontainer（bioconda 自动构建）
docker pull quay.io/biocontainers/bioconductor-ancombc:2.14.0--r45hdfd78af_0
# 或官方 depot sif 直拉
apptainer pull ancombc.sif docker://depot.galaxyproject.org/singularity/bioconductor-ancombc:2.14.0--r45hdfd78af_0
# 或 conda
mamba create -n ancombc -c conda-forge -c bioconda bioconductor-ancombc=2.14.0
```

> **与原 ANCOM 的差异**：ANCOM-BC 通过偏差校正（bias correction）给出一致的丰度估计，支持多组比较与更稳健的零值处理；原始 ANCOM 仅支持两组比较、需先加 pseudocount。本模块 native 实现封装的是**原始 ANCOM 脚本**（`programs/ancom.R`）。

## 测试

```bash
bash test/run_test.sh   # 无 R 环境下亦可全绿（argv/params.tsv 构造验证）；R+ANCOM 就绪时额外真实回归
```

## 版本

* ANCOM 2.1（代码归档 `FrederickHuangLin/ANCOM` → `ANCOM-Code-Archive`，MIT；无 releases/tags，版本号按用户手册自述 v2.1）
* 依赖 R 包：nlme / tidyverse / compositions（Debian bookworm apt 提供 r-cran-nlme/r-cran-tidyverse/r-cran-compositions）
* 构建路线：原始 ANCOM 无官方镜像 → 自建容器（`native/Dockerfile` + `Apptainer.def`，debian:bookworm-slim + apt R 包 + 源码归档）
* 后继 ANCOM-BC：官方渠道 bioconda `bioconductor-ancombc=2.14.0`
* 与 nf-core / snakemake-wrappers 的对应关系：均为 404（无官方子模块/wrapper，见 `software_versions`）

## 相关背景（QIIME）

* QIIME 2：`qiime composition ancom --i-table <comp-table.qza> --m-metadata-file <md.tsv> --m-metadata-category <col> --o-visualization <out.qzv>`（本模块等价能力由 `native/main.py analyze` 提供）
* 分析假设：绝大部分 features（>75%）在两组间无丰度差异

## 容器与 Conda 链接

* **代码归档**：<https://github.com/FrederickHuangLin/ANCOM>（重定向至 `ANCOM-Code-Archive`）
* **Zenodo**：<https://doi.org/10.5281/zenodo.3577802>
* **自建容器**：`native/Dockerfile` + `native/Apptainer.def`（debian:bookworm-slim + apt r-base-core/r-cran-* + ANCOM 源码）
* **后继 ANCOM-BC（官方）**：Docker `quay.io/biocontainers/bioconductor-ancombc:2.14.0--r45hdfd78af_0`；Singularity <https://depot.galaxyproject.org/singularity/bioconductor-ancombc%3A2.14.0--r45hdfd78af_0>
* 安装方式（本地）：`bash native/install.sh` 或 `mamba create -n ancom -c conda-forge r-base r-tidyverse r-compositions r-nlme`
