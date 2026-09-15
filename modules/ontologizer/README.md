# ontologizer 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
>
> ⚠️ **官方渠道核实（2026-09）**：bioconda `ontologizer` **404** · quay.io/biocontainers 无（bioconda 无包 → 自动构建链不存在）· depot.galaxyproject.org/singularity/ontologizer **404** · biocontainers.pro **404** · nf-core 404 · snakemake-wrappers 404 → 走自建容器兜底。
>
> ✅ **官方 jar 为公开 GPL 资产（非许可受限）**：命令行 `http://ontologizer.de/cmdline/Ontologizer.jar`（**200**）· 图形界面 `http://ontologizer.de/gui/OntologizerGui.jar`（**200**）；实测版本 **2.1（Build 20160628-1269）**。13.md 用 JRE 1.7 + Java WebStart（javaws），本模块改用独立 jar（javaws 在现代 JRE 已移除；jar 亦可跑在 OpenJDK 17/21 上）。

***

## native 实现

# ontologizer / native — Ontologizer 2.1 GO 富集分析驱动

Ontologizer（Java）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

两个子命令覆盖 13.md「十、GO富集分析（Ontologizer）」：

| 子命令      | 命令                                                                                                                    | 作用                              |
| -------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `enrich` | `java <JAVA_OPTS> -jar Ontologizer.jar -g <go.obo> -a <assoc> -s <study> -p <pop> [-c] [-m] [-o] [-d] [-n] [-i]`          | 命令行 GO 富集分析                     |
| `gui`    | `java <JAVA_OPTS> -jar OntologizerGui.jar`                                                                            | 图形界面（需 X11/显示环境）                |

> `JAVA_OPTS`（`-Xmx6g -Djava.io.tmpdir={tmpdir}`，见 `optimization.env_vars`）经命令前缀透传给 `java`；`--tmpdir` 覆盖时同步刷新 `-Djava.io.tmpdir`。Ontologizer 单进程，`--threads` 为统一接口保留（仅供上层调度器读取），不注入命令行。

## 用法

```bash
# CLI 直跑（13.md 富集分析；-o 指定结果输出目录）
python main.py enrich -g go.obo -a gene_association.gaf2 -s S1_vs_S3_S1_UP.list \
    -p population.list -c Parent-Child-Union -m Bonferroni -o ./enrichment

# 图形界面（需显示环境）
python main.py gui

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：GO 富集分析（13.md「十」）

在 GO 注释整理为 `gene_association.gaf2` 后，对差异基因集（study set）以其全基因组为背景做富集分析：

```bash
mkdir -p go/enrichment && cd go/enrichment
cp /opt/biosoft/go_class/bin/go.obo ./
cp ~/data_for_functional_annotation/enrichment_example/gene_association.gaf2 ./
cp ~/data_for_functional_annotation/enrichment_example/*.list ./

# 命令行富集（Parent-Child-Union + Bonferroni；也可用 GUI：javaws/独立 GUI jar）
java -Xmx6g -jar Ontologizer.jar \
    -g go.obo -a gene_association.gaf2 \
    -s S1_vs_S3_S1_UP.list -p population.list \
    -c Parent-Child-Union -m Bonferroni -o .

# 结果后处理（流程侧脚本，不在本模块内）：富集条目 -> GO + GeneID 表
ontologizer2enriched_GOs_and_GeneID.pl go.obo gene_association.gaf2 \
    S1_vs_S3_S1_UP.GoEnrichment.txt S1_vs_S3_S1_UP.list > S1_vs_S3_S1_UP.GoEnrichment.tab
```

> 等价能力由 `native/main.py` 的 `enrich` / `gui` 子命令提供（见上「用法」）。`ontologizer2enriched_GOs_and_GeneID.pl` 属流程侧后处理脚本，不在本模块内；`go.obo` 可由 `modules/go_class` 提供/由 GO 官网下载。

## 环境安装（无官方渠道，自建容器 / 官方公开 jar）

Ontologizer 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**全无**，官方以**公开 GPL jar** 分发（非许可受限）→ 本模块走**自建兜底**（`native/Dockerfile`、`native/Apptainer.def`，apt openjdk + 官方公开 jar）。

### 1. Docker（自建镜像）

```bash
docker build -t bioskills/ontologizer:2.1 modules/ontologizer/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/ontologizer:2.1 \
    -g /data/go.obo -a /data/gene_association.gaf2 \
    -s /data/S1_vs_S3_S1_UP.list -p /data/population.list -o /data
```

### 2. Apptainer / Singularity

无官方 sif（depot 无 ontologizer，2026-09 核实 404），从本模块自建配方构建（与 Docker 同一 apt 路线）：

```bash
apptainer build ontologizer.sif modules/ontologizer/native/Apptainer.def
apptainer run -B $PWD:/data ontologizer.sif \
    -g /data/go.obo -a /data/gene_association.gaf2 -s /data/S1_vs_S3_S1_UP.list -p /data/population.list -o /data
```

### 3. 官方独立 jar（官方推荐路线之一）

* 官网：<http://ontologizer.de/> · 命令行说明：<http://ontologizer.de/commandline/>

* 官方 jar（公开 GPL，直链；2026-09 核实 200）：

```bash
mkdir -p ~/software/ontologizer-2.1
curl -fL  http://ontologizer.de/cmdline/Ontologizer.jar    -o ~/software/ontologizer-2.1/Ontologizer.jar
curl -fL  http://ontologizer.de/gui/OntologizerGui.jar     -o ~/software/ontologizer-2.1/OntologizerGui.jar
export ONTOLOGIZER_HOME=~/software/ontologizer-2.1
java -jar "$ONTOLOGIZER_HOME/Ontologizer.jar" -v   # 断言 Ontologizer 2.1
```

* 亦可用 `native/install.sh` 一键部署到 `~/software/ontologizer-2.1`（下载官方 jar + 版本断言 + 写 `ONTOLOGIZER_HOME`）：

```bash
bash modules/ontologizer/native/install.sh
```

> 说明：13.md 采用 **Java WebStart（javaws）** + JRE 1.7；现代 JRE 已移除 WebStart，故改用独立 jar（官方同样提供）。

### 4. Conda / brew（均不可用，已核实）

* **conda**：`anaconda.org/bioconda/ontologizer` 返回 **404**，无包可装。
* **brew**：homebrew-core 与 brewsci/bio 均**无** ontologizer 公式（2026-09 核实 404）→ 不写 brew 块。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + JAVA_OPTS 透传验证（monkeypatch java/jar）
```

## 容器与 Conda 链接

* **Bioconda 页面**：无（`anaconda.org/bioconda/ontologizer` 404）

* **Docker**：无官方镜像；自建配方 `modules/ontologizer/native/Dockerfile`（`bioskills/ontologizer:2.1`）

* **Singularity**：无官方 sif；自建配方 `modules/ontologizer/native/Apptainer.def`

* **官方 jar**：<http://ontologizer.de/cmdline/Ontologizer.jar>（公开 GPL）

* **官方渠道核实（2026-09）**：bioconda 404 · quay.io/biocontainers 无 · depot.galaxyproject.org 404 · biocontainers.pro 404 · nf-core 404 · snakemake-wrappers 404

* 安装方式（本地）：`native/install.sh`（下载官方公开 jar）或自建容器

## 版本

* ontologizer **2.1（Build 20160628-1269）**（实测 `java -jar Ontologizer.jar -v`）

* 构建路线：无官方 conda/容器 → 自建容器（`debian:bookworm-slim` + apt `openjdk-17-jre-headless` + 官方公开 jar）

* 依赖：JRE（13.md 用 JRE 1.7 + WebStart；本模块用独立 jar，OpenJDK 17/21 实测可跑）；可选 GraphViz（`-d` 输出 .dot 图时）

* 许可：GPL（Ontologizer 项目声明 GNU GPL；jar 未标注具体版本，以官网为准）
