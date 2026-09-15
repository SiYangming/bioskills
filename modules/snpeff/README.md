# snpeff 软件模块

> 汇总说明：本 README 合并各实现（native + 官方 nf-core / snakemake-wrappers 登记）的用法；
> 安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# snpeff / native — 自包含变异功能注释驱动

SnpEff 的本地自包含实现（`source_type: custom`、`type: native`；Java CLI 驱动）。

## 功能

SnpEff 用于对变异结果进行功能注释，预测变异对基因功能的影响（如错义突变、无义突变、同义突变等）。

四个子命令对应 SnpEff 的注释与数据库管理链路：

| 子命令         | 命令（驱动构造）                                                                                                    | 作用                     |
| ----------- | ----------------------------------------------------------------------------------------------------------- | ---------------------- |
| `eff`       | `snpEff eff -c <config> -csvStats <csv> -s <html> -v -ud <n> <genome> <vcf>`（结果写 stdout，`-o` 落盘）                | 变异功能注释与效应预测            |
| `build`     | `snpEff build -c <config> [-gtf22|-gff3] -v <genome>`                                                       | 用参考 FASTA + GTF/GFF3 构建自定义数据库 |
| `download`  | `snpEff download -v <genome>`                                                                               | 下载官方预构建数据库             |
| `databases` | `snpEff databases -v`                                                                                       | 列出可用数据库                |

> 入口定位：优先 PATH 上的 `snpEff` wrapper（bioconda/biocontainer 提供）；缺失时用
> `SNPEFF_JAR` 或 conda share / `~/software` 下的 `snpEff.jar`，以 `java $JAVA_OPTS -jar` 调用。
> SnpEff 单线程，`--threads` 仅作接口统一，不传给 snpEff；JVM 堆内存经 `JAVA_OPTS` 注入。

## 用法

```bash
# CLI 直跑
python main.py eff -c snpEff.config -csv-stats variants.SnpEff.csv -s variants.SnpEff.html \
    -ud 500 -o variant.SnpEff.vcf malassezia_sympodialis variants.vcf
python main.py build -c snpEff.config --gtf22 malassezia_sympodialis
python main.py download GRCh38.105
python main.py databases

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：构建自定义数据库 → 变异注释

针对非标准数据库中的物种（此处以 *Malassezia sympodialis* 为例），
先用参考 FASTA + GTF 构建自定义数据库，再对 VCF 做功能注释；等价能力由 `native/main.py`
的 `build` / `eff` 子命令提供（见上「用法」）。

### 1. 准备数据库目录与注释文件

```bash
mkdir -p ~/software/snpeff-5.4.0c/snpEff/data/malassezia_sympodialis/
cp Malassezia_sympodialis.genome_V01.fasta \
    ~/software/snpeff-5.4.0c/snpEff/data/malassezia_sympodialis/sequences.fa
gff3_remove_UTR.pl Malassezia_sympodialis_V01.BestGeneModels.gff3 > Malassezia_sympodialis.gff3
gff3ToGtf.pl Malassezia_sympodialis.genome_V01.fasta Malassezia_sympodialis.gff3 \
    > ~/software/snpeff-5.4.0c/snpEff/data/malassezia_sympodialis/genes.gtf
perl -p -i -e 's/^\s*$//' ~/software/snpeff-5.4.0c/snpEff/data/malassezia_sympodialis/genes.gtf
echo "malassezia_sympodialis.genome : malassezia sympodialis" >> ~/software/snpeff-5.4.0c/snpEff/snpEff.config
```

### 2. 构建数据库

```bash
java -jar ~/software/snpeff-5.4.0c/snpEff/snpEff.jar build \
    -c ~/software/snpeff-5.4.0c/snpEff/snpEff.config -gtf22 -v malassezia_sympodialis
# 等价：python main.py build -c ~/software/snpeff-5.4.0c/snpEff/snpEff.config --gtf22 malassezia_sympodialis
```

### 3. 运行注释

```bash
java -Xmx2G -jar ~/software/snpeff-5.4.0c/snpEff/snpEff.jar eff \
    -csvStats variants.SnpEff.csv -s variants.SnpEff.html \
    -c ~/software/snpeff-5.4.0c/snpEff/snpEff.config -v -ud 500 \
    malassezia_sympodialis variants.vcf > variant.SnpEff.vcf
# 等价：python main.py eff -c .../snpEff.config -csv-stats variants.SnpEff.csv \
#         -s variants.SnpEff.html -ud 500 -o variant.SnpEff.vcf malassezia_sympodialis variants.vcf
```

### 4. 参数说明

| 参数          | 说明                                  |
| ----------- | ----------------------------------- |
| `-csvStats` | 输出 CSV 格式的统计信息                      |
| `-s`        | 输出 HTML 格式的汇总报告                      |
| `-ud`       | 上下游扩展距离（用于分析 UTR 区域）                 |
| `-v`        | 详细模式                                |
| `-c`        | snpEff.config 路径（自定义数据库时必须）         |
| `-Xmx2G`    | Java 虚拟机最大内存（本驱动经 `JAVA_OPTS` 注入）    |

### 5. 注释结果说明

SnpEff 输出的注释信息包括 `missense_variant`（错义突变，改变氨基酸）、`nonsense_variant`（无义突变，产生终止密码子）、
`synonymous_variant`（同义突变，不改变氨基酸）、`frameshift_variant`（移码突变）、`splice_donor_variant` /
`splice_acceptor_variant`（剪接供体/受体位点变异）等。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），可直接拉取官方
镜像运行工具二进制；SnpEff 官方同时提供**预编译 zip 包**与**源码**两条路线，均保留如下。

### 1. 官方预编译二进制包（首选）

* **官方下载页**：<http://pcingola.github.io/SnpEff/download/>

* **zip 直链（SourceForge，仅 latest 命名）**：<https://downloads.sourceforge.net/project/snpeff/snpEff_latest_core.zip>

```bash
# 下载并解压到用户目录（免 root；禁 /opt/biosoft）
mkdir -p ~/software
wget https://downloads.sourceforge.net/project/snpeff/snpEff_latest_core.zip -P ~/software/
unzip ~/software/snpEff_latest_core.zip -d ~/software/       # 解压出 ~/software/snpEff/
echo 'export SNPEFF_JAR=~/software/snpEff/snpEff.jar' >> ~/.bashrc
source ~/.bashrc

# 验证（需宿主已装 JRE）
java -jar $SNPEFF_JAR -version
```

> 💡 一键安装可直接运行 `native/install.sh --method binary`（部署到 `~/software/snpeff-<ver>`
> 并写 `SNPEFF_JAR`；官方 zip 仅 latest 分发，无版本化资产 → 不内嵌 sha256）。
> 注意：官方 zip 以 latest 命名（SourceForge 无版本化资产，已核实 `snpEff_v5_4_core.zip` 404）。

### 2. 官方源码编译（并列保留）

SnpEff 源码（Java / Maven 工程）在 <https://github.com/pcingola/SnpEff>：

```bash
git clone https://github.com/pcingola/SnpEff.git
cd SnpEff
# 按官方 README 说明以 Maven 构建（需 JDK + Maven）；生产环境推荐直接用 §1 预编译 zip
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n snpeff-native -c conda-forge -c bioconda snpeff=5.4.0c
conda activate snpeff-native
snpEff -version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install snpeff
snpEff -version          # 断言
# 注：brewsci/bio snpeff 当前为 4.3t，与 meta 登记 5.4.0c 略有差异（版本以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `snpeff`，
> 无 conda 时下载官方 zip 到 `~/software/snpeff-<ver>`；版本默认 5.4.0c，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/snpeff:5.4.0c--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/snpeff:5.4.0c--hdfd78af_0 \
    snpEff eff -v GRCh38.105 variants.vcf > variant.SnpEff.vcf
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull snpeff.sif docker://depot.galaxyproject.org/singularity/snpeff:5.4.0c--hdfd78af_0
apptainer run -B $PWD:/data -H /data snpeff.sif eff -v GRCh38.105 /data/variants.vcf > variant.SnpEff.vcf
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules（官方）**：`modules/nf-core/snpeff/{snpeff,download}` 两个子模块，
  均 pin `bioconda::snpeff=5.4.0c`。执行前请 `nf modules install nf-core snpeff snpeff download`
  安装到项目自身目录，**不要直接引用本仓库示例**；缺失时以本模块 `native/` 兜底。

* **snakemake-wrappers（官方）**：`bio/snpeff/{annotate,download}` 两个 wrapper，
  environment.yaml pin `snpeff=5.4.0c` + `snakemake-wrapper-utils=0.9.0`。
  运行靠 Snakemake 解析 `wrapper: "v9.17.1/bio/snpeff/annotate"` 句柄，
  **不要把本地示例当 `wrapper_path`**；缺失时以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch _resolve_binary，不依赖已安装 snpeff）
```

## 版本

* snpeff 5.4.0c（bioconda::snpeff=5.4.0c；quay tag 5.4.0c--hdfd78af_0）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/snpeff / depot.galaxyproject.org；本地不再自建容器）

* 与 nf-core `snpeff/{snpeff,download}` 的 bioconda pin 一致

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/snpeff/overview>

* **Docker**：`docker pull quay.io/biocontainers/snpeff:5.4.0c--hdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/snpeff%3A5.4.0c--hdfd78af_0>

* 安装方式（本地）：`mamba create -n snpeff -c conda-forge -c bioconda snpeff=5.4.0c`
