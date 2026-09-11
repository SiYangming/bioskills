# antismash 软件模块（次级代谢 BGC 预测）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。
>
> 官网：<https://antismash.secondarymetabolites.org/> ｜ 文档：<https://docs.antismash.secondarymetabolites.org/> ｜ 源码：<https://github.com/antismash/antismash>

***

## native 实现

# antismash / native — 次级代谢生物合成基因簇（BGC）预测驱动

antiSMASH（[antismash/antismash](https://github.com/antismash/antismash)，antibiotics & Secondary Metabolite Analysis SHell）是**次级代谢产物生物合成基因簇（BGC）预测与注释**的行业标准工具：在细菌/真菌基因组中鉴定 **PKS / NRPS / 萜烯 / RiPP / 糖苷等 100+ 类**基因簇（antiSMASH 8 从 81 类扩到 101 类），预测核心生物合成酶与产物，并可做 ClusterBlast / KnownClusterBlast / MiBIG 等比较分析，输出 **HTML 可视化报告** + 各 region 的 **GenBank/JSON** 结构化结果。生物信息教学课件中用它从基因组（GenBank）出发预测抗生素等次级代谢基因簇。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/antismash / bioconda antismash）提供：

## 能力

| 子命令        | 包装命令                                                                                                   | 作用                              | 线程            |
| ---------- | ------------------------------------------------------------------------------------------------------ | ------------------------------- | ------------- |
| `run`       | `antismash --cpus N --taxon <bacteria\|fungi> [--output-dir DIR] [--genefinding-tool T] genome.gbk`       | BGC 预测：基因组 → HTML 报告 + region GenBank/JSON | ✅ 默认 8（注入 `--cpus`） |
| `download_db` | `download-antismash-databases [--database-dir DIR]`                                                      | 下载并预处理运行数据库（数 GB，首次运行前必做）         | —（无并行参数）       |

## 用法

```bash
# 首次使用：下载数据库（Pfam/Resfam/ClusterBlast/MiBIG 等，~15GB 磁盘，时间较长）
python main.py download_db --output-dir ~/antismash_db     # 指定目录（映射 --database-dir）
python main.py download_db                                  # 或装到 antismash 默认库目录

# BGC 预测（等价教学 CLI：antismash -c 8 --taxon fungi genome.gbk）
python main.py run genome.gbk --taxon fungi --cpus 8
python main.py run genome.gbk --taxon bacteria --cpus 8 --output-dir asm_out \
    --genefinding-tool prodigal

# 只打印将执行的命令行（不真跑，可用于核查/调试）
python main.py run genome.gbk --taxon fungi --dry-run

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量；`run` 的 `--threads` 等价 `--cpus`）。

> 💡 **版本注（v7 CLI 变化）**：antiSMASH **v7 起**输出目录参数由旧版 `--outputfolder` 更名为 **`--output-dir`**，`--taxon` 取值 `bacteria|fungi`（默认 bacteria）。本模块登记的 8.0.4 / 兼容 7.1.0 均用 `--output-dir`（v6 及更早旧参数不在支持范围）。

## 实战示例：下载数据库 → 细菌/真菌基因组 BGC 预测（教学典型）

antiSMASH 是预测次级代谢生物合成基因簇（抗生素、聚酮、非核糖体肽等）的**教学标准工具**。以下为原生 CLI 的典型用法；**等价能力由 `native/main.py` 的 `download_db` / `run` 子命令提供**（见上「用法」）。

### 1. 首次使用先下载数据库（数 GB，一次性）

```bash
# 独立 conda 环境内执行（见「环境安装」）
download-antismash-databases            # 下载 + 预处理（hmmpress 等），耗时较长
# 亦可指定目录，分析时用 --databases 指向它：
# download-antismash-databases --database-dir ~/antismash_db
```

### 2. 真菌基因组 BGC 预测（教学典型用法）

```bash
# antiSMASH 7/8 教学典型：-c 8 并行、--taxon fungi 真菌
antismash -c 8 --taxon fungi genome.gbk

# 输出目录默认与输入同名（genome/），可显式指定：
antismash -c 8 --taxon fungi --output-dir fungi_asm_out genome.gbk
```

### 3. 细菌基因组 BGC 预测（默认细菌，等价 antismash my_input.gbk）

```bash
# 细菌是默认 --taxon，直接给输入即可；-c 指定并行数
antismash my_input.gbk                 # 细菌默认分析（Prodigal 预测基因 + 全套分析模块）
antismash -c 8 --taxon bacteria genome.gbk
```

### 4. 批量分析多个基因组（bash 循环）

```bash
mkdir -p asm_results
for gbk in ../genomes/*.gbk; do
    name=$(basename "$gbk" .gbk)
    antismash -c 8 --taxon bacteria --output-dir "asm_results/$name" "$gbk"
done
# 结果解读：asm_results/<name>/index.html 打开可视化报告；
#           region 级 *_regionNNN.gbk / *.json 供 BiG-SCAPE 等下游使用
```

### 5. 参数说明

| 参数               | 说明                                                              |
| ---------------- | --------------------------------------------------------------- |
| `-c N` / `--cpus N` | 并行 CPU 数（默认本机核数；驱动 run 默认注入 8）                                |
| `--taxon`        | 输入物种分类：`bacteria`（默认）\| `fungi`（真菌，v7+；教学真菌示例）               |
| `--output-dir`   | 结果输出目录（v7+；v6 及更早为 `--outputfolder`）                            |
| `--genefinding-tool` | 基因预测工具覆盖：`prodigal`（细菌默认）/ `glimmerhmm` / `none`（配合已有注释）等 |
| `--databases PATH` | 指定运行数据库根目录（默认 antismash 包内 databases/；经 `--extra-args` 透传）     |
| `--minimal` 等分析开关 | 只跑核心检测以加速 / ClusterBlast 等模块开关（经 `--extra-args` 透传，高级用法）      |

> 💡 **旧版本参数（v6 及更早）**：以下开关属旧版 CLI（教学历史用法），v7+ 已不再作为并列命令行参数（对应分析并入默认流程或由配置控制）——在 8.0.4 上直接传入会报未知参数，旧文档命令仅作历史对照：
>
> * `--clusterblast`：与已知基因簇进行比对（旧版本参数）
> * `--subclusterblast`：子簇比对（旧版本参数）
> * `--smcogs`：SMCOG 注释（旧版本参数）
> * `--full-hmmer`：全 HMMER 搜索（旧版本参数）

## 依赖模块（安装见对应模块文档）

antiSMASH 依赖的外部工具由 `antismash` conda 包自动装入；如需单独安装或核查版本，见对应模块文档：

| 依赖          | 作用                                                 | 安装文档                                        |
| ----------- | -------------------------------------------------- | ------------------------------------------- |
| BLAST+      | 序列比对（ClusterBlast 等）                               | [modules/blast](../blast/README.md)         |
| HMMER 3.x   | 蛋白谱比对                                             | [modules/hmmer](../hmmer/README.md)（3.x 现行版章节，`native/` 实现） |
| HMMER 2.x   | 旧版谱比对依赖（bioconda 包名 hmmer2）                          | [modules/hmmer](../hmmer/README.md)（2.x 遗留版章节，`native2/` 实现） |
| Glimmer3    | 原核基因预测（旧版/可选）                                      | [modules/glimmer](../glimmer/README.md)     |
| GlimmerHMM  | 真核基因预测（`--genefinding-tool glimmerhmm`）             | [modules/glimmerhmm](../glimmerhmm/README.md) |
| MUSCLE      | 多序列比对（旧版依赖，v5 起不再需要）                               | [modules/muscle](../muscle/README.md)       |

> HMMER 的 2.x 与 3.x 属**同一软件**，已合并为一个模块 `modules/hmmer`（3.x = `native/` 默认实现；2.x = `native2/` 遗留版实现，二进制带 `2` 后缀且许可为 GPL-2.0-or-later）。

> 现代 antiSMASH（7/8）另依赖 diamond / fasttree / prodigal 等，均由 conda 包自动装入；运行数据库（Pfam/ClusterBlast/MiBIG 等）见「实战示例 §1」的 `download-antismash-databases`。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。⚠️ **antismash 依赖多、数据库大**（conda 依赖 hmmer2/hmmer/diamond/fasttree/prodigal/blast 等；运行需另下数 GB 数据库）——请建**独立 conda 环境**，勿混入 base 环境。其中 HMMER 的 2.x / 3.x 属**同一软件**，已合并为本仓库的 [`modules/hmmer`](../hmmer/README.md)（3.x = `native/` 默认实现；2.x = `native2/` 遗留版实现）。

### 1. Conda / brew（包管理器安装）

```bash
# 独立环境 + 双通道安装（版本 8.0.4，与 meta software_versions 对齐）
mamba create -n antismash -c conda-forge -c bioconda antismash=8.0.4
conda activate antismash
antismash --version          # 断言：antiSMASH 8.0.4
download-antismash-databases # 首次运行前下载数据库（数 GB，见「实战示例 §1」）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio antismash 8.0.4，与 meta 登记一致（无版本差异）
# 注：brew 依赖链较重（blast/diamond/fasttree/hmmer/hmmer@2/glimmerhmm/meme@4.11.2/prodigal 等），
#     仍建议 conda/官方容器优先
brew tap brewsci/bio     # 首次使用需要
brew install antismash
antismash --version      # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/antismash:8.0.4--pyhdfd78af_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root；
#       biocontainer 镜像不含数据库，需先下载并挂载（或改用下方含库的 antismash/standalone）
# 1) 下载数据库到宿主目录
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/antismash:8.0.4--pyhdfd78af_1 \
    download-antismash-databases --database-dir /data/antismash_db
# 2) 分析（--databases 指向已下载库；容器内 CPU 数按宿主调整）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/antismash:8.0.4--pyhdfd78af_1 \
    antismash --cpus 8 --taxon fungi --databases /data/antismash_db /data/genome.gbk
```

> 💡 **Docker Hub 补充渠道（官方、含数据库，备用）**：官方另有 **`antismash/standalone`**（**内含全部数据库**，~9GB，无需 download 步骤；配官方 wrapper 脚本 `run_antismash <input> <output dir> [antismash options]`，从 <https://dl.secondarymetabolites.org/releases/latest/docker-run_antismash-full> 下载）与 `antismash/standalone-lite`（不含 Pfam/ClusterBlast，需自行装库）。教学/免下载场景可 `docker pull antismash/standalone`（tag 以 Docker Hub 为准）。此渠道仅作**备用登记**，主登记仍是上方 quay.io/biocontainers 官方镜像。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull antismash.sif docker://depot.galaxyproject.org/singularity/antismash:8.0.4--pyhdfd78af_1
# 先下载数据库（写目录需可写）
apptainer run -B $PWD:/data -H /data antismash.sif \
    download-antismash-databases --database-dir /data/antismash_db
# 再分析
apptainer run -B $PWD:/data -H /data antismash.sif \
    antismash --cpus 8 --taxon fungi --databases /data/antismash_db /data/genome.gbk
```

### 4. 二进制包安装（无官方预编译单文件资产）

antiSMASH 官方 GitHub release **只发源码 tag 归档**（无预编译单文件 assets），且运行依赖众多（hmmer2/hmmer/diamond/fasttree/prodigal/blast + MEME/`--cassis` 可选 + 数 GB 数据库）——**教学/常规使用请走上方 Conda、Docker 或 Apptainer**；其中 HMMER 2.x / 3.x 见 [`modules/hmmer`](../hmmer/README.md)（`native2/` / `native/`）。确需源码路线时拉对应 tag 源码按官方文档手动安装：

```bash
wget https://github.com/antismash/antismash/archive/refs/tags/8-0-4.tar.gz -P ~/software/
tar zxf ~/software/8-0-4.tar.gz -C ~/software/     # -> ~/software/antismash-8-0-4/
cd ~/software/antismash-8-0-4
# 依赖工具与数据库需按官方 install 文档自行安装/下载；版本与 software_versions 对齐 8.0.4
```

## 测试

```bash
cd modules/antismash/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/--help 契约）+
#   --dry-run 命令行构造断言必跑；PATH 含 antismash 时追加 --version / --help 探测；
#   绝不真跑 antismash run（需 GB 级数据库 + 长耗时）
```

## 版本

* antismash **8.0.4**（bioconda::antismash=8.0.4，noarch build `pyhdfd78af_1` / `pyhdfd78af_0`；antiSMASH 8 将可检测 BGC 类型扩到 101 类，2025 NAR W32-W38 论文）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/antismash / depot.galaxyproject.org；本地不再自建容器）

* 官方数据库下载器 `download-antismash-databases` 随 bioconda 包安装（目录参数 `--database-dir`）

* 上游 GitHub：<https://github.com/antismash/antismash>（AGPL-3.0-or-later）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/antismash/` **存在**（2026-09 在线核实，以官方在线目录为准），含 **4 个子模块**（+ 模块根 Dockerfile/README.md）：

| 子模块（与官方目录一致）        | environment.yml 关键 pin                  | 作用                                             |
| ---------------------- | -------------------------------------- | ---------------------------------------------- |
| `antismash`            | bioconda::antismash=**8.0.1**           | 完整版 BGC 预测（容器 quay.io/nf-core/antismash:8.0.1--pyhdfd78af_0；`--genefinding-tool none` + 数据库目录经 `input` 传入） |
| `antismashdownloaddatabases` | （下载数据库专用子模块）                         | 下载 antiSMASH 运行数据库                          |
| `antismashlite`        | bioconda::antismash-lite=**7.1.0**       | 精简版（antismash-lite 包，不含部分大数据库/分析）          |
| `antismashlitedownloaddatabases` | （精简版下载专用）                             | 下载 antismash-lite 运行数据库                      |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf-core modules install nf-core antismash:antismash`（及需要的 downloaddatabases 子模块；
> 安装到项目自身 `modules/nf-core/`，**不要直接 include 本仓库文件**），随后：
>
> ```nextflow
> include { ANTISMASH_ANTISMASH } from '../modules/nf-core/antismash/antismash/main'
> include { ANTISMASH_ANTISMASHDOWNLOADDATABASES } from '../modules/nf-core/antismash/antismashdownloaddatabases/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/antismash | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方无，404）

官方 snakemake-wrappers **无** `bio/antismash`（2026-09 抓取
`https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/antismash` 返回 404；
`bio/` 下无 antismash / antismash-lite wrapper）。Snakemake 场景暂无官方 wrapper 可登记，
需要时以 `antismash_native` 为兜底（`rule` 内 `shell:` 直接调 antismash，或 `run` 调本模块 main.py）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | antismash 版本        | 来源                                                                                                      |
| ------------------ | ------------------- | ------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **8.0.4**           | official biocontainer：quay.io/biocontainers/antismash:8.0.4--pyhdfd78af\_1 / bioconda antismash=8.0.4     |
| nf-core master     | 8.0.1（full）/ 7.1.0（lite） | bioconda::antismash=8.0.1 + antismash-lite=7.1.0（modules/nf-core/antismash/{antismash,antismashlite}/environment.yml） |
| snakemake-wrappers | 官方无                | bio/antismash 404（2026-09）                                                                                |
| brew（brewsci/bio）   | 8.0.4               | brewsci/bio antismash 8.0.4（与 native 一致，无需差异标注）                                                            |

> ⚠️ **CLI 代际注**：v6 及更早用 `--outputfolder`，**v7 起更名为 `--output-dir`**（`--taxon` 同时规范为 bacteria/fungi）。native（Agent/CLI，8.0.4）与 nf-core full（8.0.1）同属 v7+ CLI，命令写法一致；nf-core lite 走 `antismash-lite` 包（7.1.0，同样 v7+ CLI）。三路可在不同 conda 环境/容器内共存。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# antismash native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 antismash-native.yml 后 mamba env create -f antismash-native.yml；
# 在线推荐上方 mamba create 直装命令。antismash=8.0.4 会把运行依赖（hmmer2/hmmer/diamond/
# fasttree/prodigal/blast 等）随包装入（HMMER 2.x/3.x 见 modules/hmmer：native2/ 与 native/）；
# ⚠️ 还需另跑 download-antismash-databases 下载数 GB 数据库。
name: antismash
channels:
  - conda-forge
  - bioconda
dependencies:
  - python>=3.11
  - antismash=8.0.4
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/antismash>

* **Docker**：`docker pull quay.io/biocontainers/antismash:8.0.4--pyhdfd78af_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/antismash%3A8.0.4--pyhdfd78af_1>

* **Docker Hub 补充渠道（官方，含数据库，备用）**：`docker pull antismash/standalone`（含全部数据库 ~9GB）与 `antismash/standalone-lite`（tag 以 Docker Hub 为准；配官方 `run_antismash` wrapper，见「环境安装 §2」）

* 安装方式（本地）：`mamba create -n antismash -c conda-forge -c bioconda antismash=8.0.4`

* 上游 GitHub：<https://github.com/antismash/antismash>（release 为源码 tag 归档，无预编译单文件资产；AGPL-3.0-or-later）
