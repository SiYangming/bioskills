# rdp-classifier 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；环境安装见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# rdp-classifier / native — 自包含 16S 物种分类驱动

RDP Classifier 的本地自包含实现（`source_type: custom`、`type: native`；Java 工具）。

## 功能

RDP（Ribosomal Database Project）分类器是一种基于朴素贝叶斯算法的 16S rRNA 基因序列分类工具，由密歇根州立大学开发。它能够快速将 16S rRNA 序列注释到不同的分类学水平（界、门、纲、目、科、属）。

RDP Classifier 基于朴素贝叶斯算法，把代表序列（OTU/ASV rep set）注释到各分类水平并给出置信度。

| 子命令       | 命令                                                                                                         | 作用                          |
| --------- | ---------------------------------------------------------------------------------------------------------- | --------------------------- |
| `classify` | `rdp_classifier -Xmx6g classify -t <train.prop> -o <out.txt> -f <format> -c <conf> <rep_set.fna>` | 16S rRNA 序列 → 界/门/纲/目/科/属 分类注释 |

`-t` 不填时使用 `classifier.jar` 内置的默认 16S 训练集；也可用 `-t rRNAClassifier.properties` 指定自定义训练集（如 RDP/SILVA/CO1 训练文件）。

## 用法

```bash
# CLI 直跑
python main.py classify rep_set.fna -o rdp_assigned_taxonomy.txt --conf 0.8 --threads 8
python main.py classify rep_seqs.fna -t rRNAClassifier.properties -o taxonomy.txt -f allrank
python main.py classify rep_set.fna -o taxonomy.txt -f fixrank -r genus -b bootstrap.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。JVM 内存等参数经 `JAVA_OPTS`（默认 `-Xmx6g`）透传（`-Xm*`/`-D*`/`-XX*` token 会置于 `classify` 之前）。

## 实战示例：批量 16S 序列物种注释

RDP Classifier 是 QIIME 1.x `assign_taxonomy.py -m rdp` 的底层分类器，速度快（每秒可分类上千条序列）、对短读 16S 友好，是无参/有参扩增子流程常用的物种注释工具。以下为典型批量用法；等价能力由 `native/main.py` 的 `classify` 子命令提供（见上「用法」）。

### 1. 单批序列分类

```bash
mkdir -p 07.taxonomic_analysis
cd 07.taxonomic_analysis

# rep_set.fna 为去嵌合后的代表序列（OTU/ASV）
rdp_classifier -Xmx8g classify \
  -o rdp_assigned_taxonomy.txt \
  -f allrank -c 0.8 \
  ../rep_set.fna
```

### 2. 指定自定义训练集 / 分类水平

```bash
# 使用自定义训练集（-t 指向 rRNAClassifier.properties）
rdp_classifier -Xmx8g classify \
  -t mydata_trained/rRNAClassifier.properties \
  -o rdp.output -c 0.8 \
  query.fasta

# 仅输出到属水平（-r genus），并导出 bootstrap 计数（-b）
rdp_classifier -Xmx8g classify -o genus.txt -f allrank -r genus -b bootstrap.txt rep_set.fna
```

### 3. 参数说明

| 参数                | 说明                                                              |
| ----------------- | --------------------------------------------------------------- |
| `-t`              | 训练集属性文件（`rRNAClassifier.properties`）；不填用内置默认 16S 训练集              |
| `-o`              | 分类结果输出文件（Tab 分隔）                                                |
| `-f`              | 输出格式：`allrank`（各水平明细）/ `fixrank`（默认）/ `biom` / `filterbyconf` / `db` |
| `-c`              | 置信度阈值（bootstrap confidence cutoff，默认 0.8）                        |
| `-g`              | 指定基因（如 `16srrna`）；不使用自定义 `-t` 时可用                               |
| `-r`              | 只输出到指定分类水平（如 `genus`）                                            |
| `-b` / `-s`       | bootstrap 计数输出 / 过短序列名输出文件                                       |
| `-Xmx` / `JAVA_OPTS` | JVM 堆内存（如 `-Xmx8g`），置于 `classify` 之前                              |

> 💡 提示：RDP Classifier 是单线程 Java 程序，`-Xmx` 决定其内存上限；大训练集时请相应调高 `JAVA_OPTS`。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。RDP Classifier 为 Java（noarch）程序，另提供官方 SourceForge 分发包（内含 `dist/classifier.jar`，无需编译）。

### 1. Conda（包管理器安装）

```bash
mamba create -n rdp-classifier -c conda-forge -c bioconda rdp_classifier=2.14
conda activate rdp-classifier
```

> brew 无该软件公式（2026-09 核实 homebrew-core `formulae.brew.sh/api/formula/rdp-classifier.json` 返回 404），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `rdp-classifier`，无 conda 时自动下载官方 SourceForge 分发包到 `~/software/rdp_classifier-<ver>` 并写 PATH；版本默认 2.14，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/rdp_classifier:2.14--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/rdp_classifier:2.14--hdfd78af_0 \
    rdp_classifier -Xmx6g classify -o /data/rdp_assigned_taxonomy.txt -f allrank /data/rep_set.fna
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull rdp_classifier.sif docker://depot.galaxyproject.org/singularity/rdp_classifier:2.14--hdfd78af_0
apptainer run -B $PWD:/data -H /data rdp_classifier.sif \
    rdp_classifier -Xmx6g classify -o /data/rdp_assigned_taxonomy.txt -f allrank /data/rep_set.fna
```

### 4. 官方分发包（SourceForge zip，无需编译）

* **官网/项目**：<https://sourceforge.net/projects/rdp-classifier/>
* **代码仓库**：<https://github.com/rdpstaff/classifier>

```bash
wget https://sourceforge.net/projects/rdp-classifier/files/rdp-classifier/rdp_classifier_2.14.zip -O ~/software/rdp_classifier_2.14.zip
mkdir -p ~/software/rdp_classifier_2.14 && unzip -q ~/software/rdp_classifier_2.14.zip -d ~/software/rdp_classifier_2.14
# 分发包内为 dist/classifier.jar，可直接用 java 运行：
java -jar ~/software/rdp_classifier_2.14/rdp_classifier_2.14/dist/classifier.jar classify \
    -o rdp_assigned_taxonomy.txt -f allrank rep_set.fna
```

> 说明：官方分发包为 2.14 版本 zip（约 338 MB，含训练数据）；`native/install.sh --method binary` 会自动下载并生成 `rdp_classifier` 包装脚本到 `--prefix/bin`，默认版本的内嵌 sha256 取自 bioconda recipe 登记的官方分发包摘要。

QIIME 1.x 内置：通过 `assign_taxonomy.py -m rdp` 调用

QIIME 2.x 内置：通过 `qiime feature-classifier classify-sklearn` 使用类似的朴素贝叶斯算法

## 测试

```bash
bash test/run_test.sh   # classify 退化为 argv 构造验证；二进制已装时额外冒烟
```

## 版本

* rdp_classifier 2.14（bioconda::rdp_classifier=2.14，noarch: generic，run 依赖 openjdk>=11）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/rdp_classifier:2.14--hdfd78af_0 / depot.galaxyproject.org；本地不再自建容器）
* 与 nf-core / snakemake-wrappers 的对应关系：均为 404（无官方子模块/wrapper，见 `software_versions`）

## 相关背景（QIIME）

* QIIME 1.x：`assign_taxonomy.py -i rep_set.fna -m rdp -o rdp_assigned_taxonomy`（内部调用 RDP Classifier）
* QIIME 2：`qiime feature-classifier classify-sklearn --i-classifier <nb-classifier.qza> ...`（复刻朴素贝叶斯思路，非同一实现）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/rdp_classifier>
* **Docker**：`docker pull quay.io/biocontainers/rdp_classifier:2.14--hdfd78af_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/rdp_classifier%3A2.14--hdfd78af_0>
* **官方分发包**：<https://sourceforge.net/projects/rdp-classifier/files/rdp-classifier/rdp_classifier_2.14.zip>
* 安装方式（本地）：`mamba create -n rdp-classifier -c conda-forge -c bioconda rdp_classifier=2.14`
