# ensembl-vep 软件模块

> 汇总说明：本 README 合并各实现（native + 官方 nf-core / snakemake-wrappers 登记）的用法；
> 安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# ensembl-vep / native — 自包含变异注释驱动（Perl CLI 驱动）

VEP（Variant Effect Predictor）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

VEP（Variant Effect Predictor）是 Ensembl 开发的变异注释工具，支持预测变异对基因、转录本和蛋白质序列的影响，是最全面的变异注释工具之一。

三个子命令覆盖注释、缓存管理与结果过滤：

| 子命令        | 命令（驱动构造）                                                                                                 | 作用                                |
| ---------- | -------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `annotate` | `vep -i <in.vcf> -o <out> --cache [--cache_version N] --species <s> --assembly <a> [--vcf\|--tab] --fork N [--force_overwrite]` | 变异功能注释（CSQ / IMPACT / SIFT / PolyPhen 等） |
| `cache`    | `vep_install -a <auto> -s <species> -y <assembly> -c <dir> [--CONVERT]`                                  | 下载/构建缓存数据库                        |
| `filter`   | `filter_vep -i <in> -o <out> -f "<expr>" [--format vcf\|tab]`                                            | 对注释结果按表达式过滤                       |

> 入口定位：按子命令解析 `vep`（annotate）/ `vep_install`（cache）/ `filter_vep`（filter），
> 支持 PATH、`ENSEMBL_VEP_HOME`、conda share、`~/software/ensembl-vep*`。
> `annotate` 的 `--fork` 由 `--threads`（默认 8）注入。

## 用法

```bash
# CLI 直跑
python main.py annotate -i variants.vcf -o variants.vep.vcf --cache --species homo_sapiens \
    --assembly GRCh38 --vcf --fork 4 --force_overwrite
python main.py cache -a cf -s homo_sapiens -y GRCh38 -c ~/.vep --CONVERT
python main.py filter -i variants.vep.vcf -o filtered.vcf -f "IMPACT is HIGH"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：下载缓存 → 变异注释 → 输出/过滤

文档（07 变异检测 §10）给出 VEP 的典型用法；等价能力由 `native/main.py` 的
`annotate` / `cache` 子命令提供（见上「用法」）。

### 1. 下载人类数据库缓存（GRCh38）

```bash
vep_install -a cf -s homo_sapiens -y GRCh38 -c ~/.vep/ --CONVERT
# 等价：python main.py cache -a cf -s homo_sapiens -y GRCh38 -c ~/.vep --CONVERT
```

### 2. 基础变异注释

```bash
vep -i variants.vcf -o variants.vep.vcf \
    --cache --cache_version 104 \
    --species homo_sapiens --assembly GRCh38 \
    --vcf --fork 4 --force_overwrite
# 等价：python main.py annotate -i variants.vcf -o variants.vep.vcf --cache \
#         --cache_version 104 --species homo_sapiens --assembly GRCh38 --vcf --fork 4 --force_overwrite
```

### 3. 更全面的注释（含 SIFT / PolyPhen 预测）

```bash
vep -i variants.vcf -o variants.vep_full.vcf \
    --cache --species homo_sapiens --assembly GRCh38 --vcf \
    --sift b --polyphen b --ccds --uniprot --hgvs --symbol --numbers \
    --domains --regulatory --canonical --protein --biotype --uniprot_isoform \
    --tsl --appris --fork 4 --force_overwrite
```

### 4. 输出制表符格式

```bash
vep -i variants.vcf -o variants.vep.txt --cache --species homo_sapiens --assembly GRCh38 \
    --tab --symbol --protein --biotype --fork 4 --force_overwrite
```

### 5. 参数说明

| 参数                  | 说明                            |
| ------------------- | ----------------------------- |
| `-i` / `-o`         | 输入 VCF / 输出文件                  |
| `--cache`           | 使用本地缓存数据库（速度更快）               |
| `--species`         | 物种名称                          |
| `--assembly`        | 参考基因组版本                       |
| `--vcf` / `--tab`   | 输出 VCF / 制表符分隔格式              |
| `--sift b`          | 输出 SIFT 致病性预测（b=both 评分和预测）    |
| `--polyphen b`      | 输出 PolyPhen 致病性预测             |
| `--symbol`          | 输出基因符号                        |
| `--protein`         | 输出蛋白质变化                       |
| `--canonical`       | 仅注释经典转录本                      |
| `--fork`            | 并行线程数（本驱动经 `--threads` 注入）     |
| `--force_overwrite` | 强制覆盖输出文件                      |

### 6. 注释结果说明

VEP 的 VCF 输出在 INFO 字段添加 `CSQ` 标签，包含 `Allele`、`Consequence`、`IMPACT`
（HIGH/MODERATE/LOW/MODIFIER）、`SYMBOL`、`Gene`、`Feature_type`、`Feature`、
`Protein_position`、`Amino_acids`、`Codons`、`SIFT`、`PolyPhen` 等字段。

| 字段               | 说明                                   |
| ------------------ | -------------------------------------- |
| `Allele`           | 变异等位基因                           |
| `Consequence`      | 变异后果（如 missense_variant）        |
| `IMPACT`           | 影响程度（HIGH/MODERATE/LOW/MODIFIER） |
| `SYMBOL`           | 基因符号                               |
| `Gene`             | 基因 ID                                |
| `Feature_type`     | 特征类型（如 Transcript）              |
| `Feature`          | 转录本 ID                              |
| `Protein_position` | 蛋白质位置                             |
| `Amino_acids`      | 氨基酸变化                             |
| `Codons`           | 密码子变化                             |
| `SIFT`             | SIFT 预测                              |
| `PolyPhen`         | PolyPhen 预测                          |

### 7. 注意事项

* VEP 是功能最全面的变异注释工具之一，支持大量数据库与预测工具
* 建议使用本地缓存（`--cache`）以提高运行速度
* 支持在线模式（不下载缓存），但速度较慢且需网络
* 支持多种物种，包括非模式生物（需准备 GFF 文件）

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像
运行工具二进制；`main.py` 驱动在宿主机跑。VEP 无官方预编译二进制包（官方以 Perl 源码 +
`INSTALL.pl` 分发，已核实），故本节以官方镜像/conda 为首选，官方源码安装并列保留。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n ensembl-vep-native -c conda-forge -c bioconda ensembl-vep=116.2
conda activate ensembl-vep-native
vep --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install vep
vep --version            # 断言
# 注：brewsci/bio vep 当前基于 release/116.0，与 meta 登记 116.2 略有差异（版本以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `ensembl-vep`，
> 无 conda 时下载官方源码 release 并跑 `perl INSTALL.pl --AUTO a --NO_HTSLIB`；版本默认 116.2，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/ensembl-vep:116.2--pl5321h2a3209d_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/ensembl-vep:116.2--pl5321h2a3209d_0 \
    vep -i /data/variants.vcf -o /data/variants.vep.vcf \
        --cache --species homo_sapiens --assembly GRCh38 --vcf --fork 4 --force_overwrite
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull ensembl-vep.sif docker://depot.galaxyproject.org/singularity/ensembl-vep:116.2--pl5321h2a3209d_0
apptainer run -B $PWD:/data -H /data ensembl-vep.sif \
    -i /data/variants.vcf -o /data/variants.vep.vcf --cache --species homo_sapiens --assembly GRCh38 --vcf
```

### 4. 官方源码安装（Perl INSTALL.pl；已核实无预编译二进制）

* **GitHub**：<https://github.com/Ensembl/ensembl-vep>

* **release 源码包**：`https://github.com/Ensembl/ensembl-vep/archive/refs/tags/release/116.2.tar.gz`

```bash
git clone https://github.com/Ensembl/ensembl-vep.git   # 或下载 release/<ver>.tar.gz 解压
cd ensembl-vep
perl INSTALL.pl --AUTO a --NO_HTSLIB --NO_UPDATE       # 安装 Perl 依赖（非交互）
# 如需一并下载缓存：perl INSTALL.pl --AUTO acf -s homo_sapiens -y GRCh38
echo 'export PATH=$PWD:$PATH' >> ~/.bashrc && source ~/.bashrc
vep --version   # 断言
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules（官方）**：模块名为 **`ensemblvep`**，含 `ensemblvep/{vep,filtervep,download}`
   三个子模块，pin `bioconda::ensembl-vep=116.1`（+ `htslib=1.23.1`）。执行前请
   `nf modules install nf-core ensemblvep vep filtervep download` 安装到项目自身目录，
   **不要直接引用本仓库示例**；缺失时以本模块 `native/` 兜底。

* **snakemake-wrappers（官方）**：目录名为 **`vep`**，含 `bio/vep/{annotate,cache,plugins}`
   三个 wrapper（annotate pin `ensembl-vep=116.1`；cache pin `ensembl-vep=116.2`）。运行靠
   Snakemake 解析 `wrapper: "v9.17.1/bio/vep/annotate"` 句柄，**不要把本地示例当 `wrapper_path`**；
   缺失时以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch _resolve_binary，不依赖已安装 vep）
```

## 版本

* ensembl-vep 116.2（bioconda::ensembl-vep=116.2；quay tag 116.2--pl5321h2a3209d_0）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/ensembl-vep / depot.galaxyproject.org；本地不再自建容器）

* nf-core/ensemblvep pin 116.1（低于 bioconda 最新 116.2，见 software_versions）

## 容器与 Conda 链接

* **官网**：https://www.ensembl.org/info/docs/tools/vep/index.html

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/ensembl-vep/overview>

* **Docker**：`docker pull quay.io/biocontainers/ensembl-vep:116.2--pl5321h2a3209d_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/ensembl-vep%3A116.2--pl5321h2a3209d_0>

* 安装方式（本地）：`mamba create -n ensembl-vep -c conda-forge -c bioconda ensembl-vep=116.2`
