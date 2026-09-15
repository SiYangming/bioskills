# gemoma 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# gemoma / native — 自包含同源基因结构预测驱动

GeMoMa（Gene Model Mapper）的本地自包含实现（`source_type: custom`、`type: native`；Java CLI）。

## 功能

GeMoMa（Gene Model Mapper）是一个基于同源基因结构的基因预测工具，通过将参考物种的基因结构映射到目标基因组来进行基因注释。

五个子命令对应 GeMoMa 的 5 个 CLI 模块：

| 子命令                   | 命令（上游：`java -jar GeMoMa-<ver>.jar CLI <Module>`）                    | 作用                     |
| --------------------- | ------------------------------------------------------------------ | ---------------------- |
| `extractor`           | `CLI Extractor -a <gff> -g <ref.fa> -p <prot.fa> -c <cds.fa>`      | 从参考基因组+注释提取 CDS/蛋白序列   |
| `pipeline`            | `CLI GeMoMaPipeline -t <target> -a .. -g .. -p .. -c .. -o <dir> --threads N` | 完整同源基因预测流程             |
| `gaf`                 | `CLI GAF -g <predicted.gff> -o <out.gff3>`                          | 预测注释过滤/处理              |
| `annotation_evidence` | `CLI AnnotationEvidence <--extra-args>`                            | 注释证据整合                 |
| `coding_quarry`       | `CLI CodingQuarry <--extra-args>`                                  | 真菌基因预测专用模块             |

> Java 工具：运行期透传 `JAVA_OPTS`（`optimization.env_vars.JAVA_OPTS: -Xmx6g`）；`pipeline` 自动注入 `--threads`。

## 用法

```bash
# CLI 直跑
python main.py extractor -a ref.gff -g ref.fasta -p ref_proteins.fasta -c ref_cds.fasta
python main.py pipeline -t target.fasta -a ref.gff -g ref.fasta -p ref_proteins.fasta \
    -c ref_cds.fasta -o gemoma_output --threads 8
python main.py gaf -g gemoma_output/predicted_annotation.gff -o gemoma.gff3

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；jar 按 `GEMOMA_JAR` / `GEMOMA_HOME` /
`~/software/GeMoMa*/` / conda `share` 惰性解析。

## 注意事项

- GeMoMa 需要 Java 运行环境（推荐 Java 8 或更高）
- 需要参考物种的高质量基因组注释
- 对于亲缘关系较远的物种，预测准确性可能下降
- GeMoMa 可以与其他基因预测工具的结果整合，提高预测准确性
- 支持多参考物种，通过整合多个参考物种的结果提高准确性

## 实战示例：同源物种基因结构预测

GeMoMa 的典型使用流程包括：1）提取参考物种的 CDS 和蛋白序列；2）将参考基因比对到目标基因组；3）预测基因结构。

GeMoMa 用参考物种的注释，通过氨基酸序列与内含子位置保守性把基因结构映射到目标基因组，
适用于近缘物种注释迁移；对亲缘关系较远的物种准确性下降。以下为典型三段链路；等价能力由
`native/main.py` 的 `extractor` / `pipeline` / `gaf` 子命令提供（见上「用法」）。

```bash
mkdir -p gemoma && cd gemoma

# 1. 从参考基因组/注释提取 CDS 与蛋白序列
java -jar $GEMOMA_HOME/GeMoMa-1.9.jar CLI Extractor \
    -a reference_annotation.gff -g reference_genome.fasta \
    -p reference_proteins.fasta -c reference_cds.fasta

# 2. 运行完整预测流程（-t 目标基因组；--threads 并行）
java -jar $GEMOMA_HOME/GeMoMa-1.9.jar CLI GeMoMaPipeline \
    -t target_genome.fasta -a reference_annotation.gff -g reference_genome.fasta \
    -p reference_proteins.fasta -c reference_cds.fasta -o gemoma_output --threads 8

# 3. 从结果中提取/过滤 GFF
java -jar $GEMOMA_HOME/GeMoMa-1.9.jar CLI GAF \
    -g gemoma_output/predicted_annotation.gff -o gemoma.gff3
```

参数说明：

| 参数                  | 说明              |
| ------------------- | --------------- |
| `-t target.fasta`   | 目标基因组序列         |
| `-g reference.fasta` | 参考基因组序列         |
| `-a reference.gff`  | 参考基因组注释         |
| `-p reference_proteins.fasta` | 参考蛋白序列 |
| `-c reference_cds.fasta` | 参考 CDS 序列  |
| `-o output_dir`     | 输出目录（pipeline）  |
| `--threads 8`       | 并行线程数（pipeline） |

> 桥接句：上表的等价能力由 `native/main.py` 的 `extractor` / `pipeline` / `gaf` 子命令提供，先 CLI 直跑、再按需接入 Agent。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方**另有预编译 Java 包**，两条官方路线（预编译包 / 源码编译）均保留。

### 1. 官方预编译二进制包（首选，Java jar）

```bash
# 官方 Java 包（jstacs.de；含 GeMoMa-1.9.jar 与运行脚本）
curl -fsSL -o ~/software/GeMoMa-1.9.zip "https://www.jstacs.de/downloads/GeMoMa-1.9.zip"
mkdir -p ~/software/GeMoMa-1.9 && unzip -q -o ~/software/GeMoMa-1.9.zip -d ~/software/GeMoMa-1.9
export GEMOMA_HOME=~/software/GeMoMa-1.9
echo 'export GEMOMA_HOME=~/software/GeMoMa-1.9' >> ~/.bashrc
java -jar $GEMOMA_HOME/GeMoMa-1.9.jar CLI   # 断言（列出 CLI 模块）
```

> 一键安装：`bash native/install.sh --method binary`（默认部署到 `~/software/GeMoMa-1.9`，内嵌 sha256 校验）。

### 2. 官方源码（并列保留）

```bash
# 官方源码（GitHub Jstacs/GeMo-Projects；GeMoMa 与 GeMoSeq 源码，Maven 构建）
git clone https://github.com/Jstacs/GeMo-Projects.git
cd GeMo-Projects
# 使用 Maven 构建后得到 GeMoMa-<ver>.jar（构建细节以仓库 README 为准）
```

### 3. Conda（包管理器安装，备选）

```bash
mamba create -n gemoma -c conda-forge -c bioconda gemoma=1.9
conda activate gemoma
GeMoMa CLI        # 断言（package 提供 GeMoMa 包装脚本 = java -jar GeMoMa-1.9.jar CLI）
```

> ⚠️ 无 Homebrew 公式：已核实 homebrew-core（`formulae.brew.sh/api/formula/gemoma.json` 404）与 brewsci/bio tap
> 两源均无，故不提供 `brew` 块。
>
> ⚠️ Java 依赖：GeMoMa 需 **Java 1.8+**；`main.py` 透传 `JAVA_OPTS`（默认 `-Xmx6g`），可自行覆盖堆上限。
> 一键安装直接 `bash native/install.sh`（有 conda/mamba 走 bioconda gemoma=1.9，否则走官方 Java 包）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/gemoma:1.9--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/gemoma:1.9--hdfd78af_0 \
    GeMoMa CLI GeMoMaPipeline -t /data/target.fasta -o /data/gemoma_output --threads 8
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull gemoma.sif docker://depot.galaxyproject.org/singularity/gemoma:1.9--hdfd78af_0
apptainer run -B $PWD:/data -H /data gemoma.sif \
    GeMoMa CLI GeMoMaPipeline -t /data/target.fasta -o /data/gemoma_output --threads 8
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证；java+jar 就绪时额外做 CLI 冒烟
```

## 容器与 Conda 链接

* **官网**：<http://www.jstacs.de/index.php/GeMoMa>

* **Github**：<https://github.com/Jstacs/GeMo-Projects>

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/gemoma/overview>

* **Docker**：`docker pull quay.io/biocontainers/gemoma:1.9--hdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/gemoma%3A1.9--hdfd78af_0>

* **官方 Java 包**：<https://www.jstacs.de/downloads/GeMoMa-1.9.zip>

* 安装方式（本地）：`mamba create -n gemoma -c conda-forge -c bioconda gemoma=1.9`

## 版本

* GeMoMa 1.9（官方 Java 包 GeMoMa-1.9.zip；官方镜像/conda gemoma=1.9，tag 1.9--hdfd78af_0）

* 构建路线：官方预编译 Java 包（首选）+ 官方源码（并列保留）+ 官方 biocontainer/quay/depot（本地不再自建容器）

* nf-core / snakemake-wrappers：官方无模块 / 无 wrapper（2026-09-11 抓取 404）
