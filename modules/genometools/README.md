# genometools 软件模块（基因组分析工具集 · LTRharvest 重复序列分析）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。
>
> ⚠️ **包名对照**：软件 canonical 目录名为 `genometools`，但 **bioconda / biocontainer 的实际包名是 `genometools-genometools`**（`quay.io/biocontainers/genometools-genometools`）；历史包名 `genometools` 仅到 1.2.1（很旧，勿用）。安装/拉镜像一律用 `genometools-genometools`。

***

## native 实现

# genometools / native — ESA 索引 + LTRharvest LTR 反转录转座子预测驱动

GenomeTools（[genometools/genometools](https://github.com/genometools/genometools)，官网 <https://genometools.org/>）把大量基因组分析功能集中到**单一二进制 `gt`**（子命令式 CLI，C 库 libgenometools）。本模块聚焦重复序列分析链路中的两个子命令：

* `gt suffixerator`：为基因组 FASTA 建立**增强后缀数组（ESA）索引**（LTRharvest 等工具的前置索引）；
* `gt ltrharvest`：基于该索引**预测 LTR 反转录转座子**（LTR retrotransposons）。

GenomeTools 的 LTRharvest 是 **RepeatModeler（`-LTRStruct`）与 LTR_retriever** 流程的 LTR 结构发现依赖——即「先 `gt suffixerator` 建索引，再 `gt ltrharvest` 挖掘 LTR」是这两条流程内部的标准两步。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/genometools-genometools / bioconda genometools-genometools）提供；两个子命令分别包装官方 `gt` 的两个子命令：

## 能力

| 子命令            | 包装命令                                                                    | 作用                                                                | 线程                                    |
| -------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------- |
| `suffixerator` | `gt suffixerator -db <fasta> -indexname <prefix> [-tis -suf -lcp -des -ssp -sds -dna]` | 基因组 FASTA → ESA 索引（`<prefix>.{esq,ssp,des,sds,suf,lcp,md5}`） | 原生无线程参数，接受 `--threads` 但不注入             |
| `ltrharvest`   | `gt ltrharvest -index <prefix> [-out F] [-outinner F] [-gff3 F]`          | 基于 ESA 索引预测 LTR 反转录转座子 → FASTA（LTR / inner）+ GFF3                    | 原生无线程参数，接受 `--threads` 但不注入             |

## 用法

```bash
# 1) 建 ESA 索引（教学链路默认注入 -tis -suf -lcp -des -ssp -sds -dna）
python main.py suffixerator -db genome.fasta -indexname genome --threads 4

# 2) 预测 LTR 反转录转座子
python main.py ltrharvest -index genome \
    -out ltrharvest.out -outinner ltrharvest.inner -gff3 ltrharvest.gff3

# 单独关闭某个索引开关（如不需要 transformed suffix array；-sds 依赖 -des，须同时关闭）
python main.py suffixerator -db genome.fasta -indexname genome --no-tis --no-sds --no-des

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。`gt suffixerator` / `gt ltrharvest` 原生**无线程参数**，`--threads` 仅作为运行期选项被接受、不注入命令行（与 RepeatModeler 的 BuildDatabase 同策略）。

## 实战示例：基因组 LTR 反转录转座子挖掘（suffixerator → ltrharvest）

LTRharvest 是 LTR 反转录转座子注释的经典工具，也是 RepeatModeler `-LTRStruct` / LTR_retriever 的 LTR 结构发现引擎。以下为原生 CLI 的典型两步链路（教学课件 LTR_retriever 一节即 `gt suffixerator ... -tis -suf -lcp -des -ssp -sds -dna` + `gt ltrharvest -index ... -out ... -outinner ... -gff3 ...`）；**等价能力由 `native/main.py` 的 `suffixerator` / `ltrharvest` 子命令提供**（见上「用法」）。

> ⚠️ **工作目录约定**：索引前缀 `-indexname` 是相对当前目录的 basename，`gt ltrharvest -index` 必须指向同一前缀的索引产物，请在同一目录下先后调用（容器运行同理，见「环境安装 §2」）。索引体积与基因组大小同量级（真核大基因组需预留充足磁盘）。

### 1. 为基因组建立 ESA 索引（suffixerator）

```bash
mkdir -p ltrharvest_out && cd ltrharvest_out

# -indexname genome：输出 genome.{esq,ssp,des,sds,suf,lcp,md5}
gt suffixerator -db ../genome.fasta -indexname genome \
    -tis -suf -lcp -des -ssp -sds -dna
```

### 2. 预测 LTR 反转录转座子（ltrharvest）

```bash
# -index 指向第 1 步的索引前缀；三路输出分别为 LTR 序列 / 内部区域序列 / GFF3 注释
gt ltrharvest -index genome \
    -out ltrharvest.out -outinner ltrharvest.inner -gff3 ltrharvest.gff3
```

产物：

```bash
ls -1 ltrharvest.*
# ltrharvest.out     <- 预测到的 LTR 反转录转座子序列（FASTA）
# ltrharvest.inner   <- 内部区域（inner region）序列（FASTA）
# ltrharvest.gff3    <- 预测结果 GFF3（LTR_retrotransposon / LTR / TSD / motif 等特征）
```

### 3. 批量（多基因组）：每个基因组一套索引 + LTR 注释

```bash
for fa in ../genomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    gt suffixerator -db "$fa" -indexname "${name}" -tis -suf -lcp -des -ssp -sds -dna
    gt ltrharvest -index "${name}" \
        -out "${name}.ltr.fa" -outinner "${name}.inner.fa" -gff3 "${name}.ltr.gff3"
done
```

### 4. 参数说明

| 参数                                                             | 说明                                                                                          |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `-db <fasta>`                                                  | suffixerator 输入基因组 FASTA（驱动 `--db`；gt 原生 `-db` 可多文件，多文件请走 `--extra-args`）                    |
| `-indexname <prefix>`                                          | suffixerator 输出索引前缀（产物 `<prefix>.{esq,ssp,des,sds,suf,lcp,md5}`）                             |
| `-tis` / `-suf` / `-lcp` / `-des` / `-ssp` / `-sds` / `-dna`    | 索引/编码开关：`-tis` 输出 transformed 序列、`-suf` 后缀数组、`-lcp` lcp 表、`-des` 序列描述表、`-ssp` 分隔位置表、`-sds` 描述分隔位置表、`-dna` DNA 输入；本驱动默认全部注入，可用 `--no-<开关>` 关闭（`-sds` 依赖 `-des`） |
| `-index <prefix>`                                              | ltrharvest 的 ESA 索引前缀（必需，指向 suffixerator `-indexname` 产物）                                   |
| `-out` / `-outinner`                                           | LTR 序列 / 内部区域序列 FASTA 输出                                                                     |
| `-gff3`                                                        | 预测结果 GFF3 输出                                                                                 |
| `-seed` / `-minlenltr` / `-maxlenltr` / `-maxdistltr` / `-similar` | 敏感度与 LTR 边界阈值（默认 seed 30、LTR 长 100–1000、LTR 起始间距 1000–15000、相似度 85%）；经 `--extra-args` 透传 |
| `-outinner`（同 `-vic` / `-mintsd` / `-maxtsd` / `-motif`）        | TSD/motif 与内部区域相关阈值；经 `--extra-args` 透传                                                     |

> 💡 **与 RepeatModeler / LTR_retriever 的关系**：RepeatModeler 的 `-LTRStruct` 内部会调用 GenomeTools 的 LTRharvest（并配合 LTR_retriever）；用本模块可单独、可控地跑这条 LTR 发现链路（例如先看 LTR 家族数量再决定是否进入完整建库）。依赖方文档只需指向本模块的安装文档，依赖管理不在本模块内。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

GenomeTools 上游同时提供**官方预编译二进制包**（GitHub release assets）与**源码编译**两条官方路线——**本模块安装方式以官方预编译包为首选**（§1），官方源码编译并列保留（§2）；官方容器 / conda / brew（§3–§5）为备选。**注意官方 conda 包名为 `genometools-genometools`**。

### 1. 官方预编译二进制包（首选，免编译）

官方 GitHub release 提供各平台预编译资产：Linux x86_64 `gt-1.6.6-Linux_x86_64-64bit-complete.tar.gz`、macOS arm64 `gt-1.6.6-Darwin_arm64-64bit-complete.tar.gz`、Windows `gt-1.6.6-Windows_x86_64-64bit.zip`（complete = 含 AnnotationSketch/cairo；另有体积更小的 `-barebone` 版）。部署到用户前缀（免 root）：

```bash
mkdir -p ~/software && cd ~/software
curl -L -O https://github.com/genometools/genometools/releases/download/v1.6.6/gt-1.6.6-Linux_x86_64-64bit-complete.tar.gz
tar zxf gt-1.6.6-Linux_x86_64-64bit-complete.tar.gz   # -> ~/software/gt-1.6.6-Linux_x86_64-64bit-complete/
echo 'export PATH=$PATH:~/software/gt-1.6.6-Linux_x86_64-64bit-complete/bin' >> ~/.bashrc && source ~/.bashrc
gt -version    # 断言：GenomeTools 1.6.6
```

> 发行页：<https://github.com/genometools/genometools/releases/tag/v1.6.6>；仅用 `suffixerator`/`ltrharvest` 时可换用 `...-64bit-barebone.tar.gz`（不含 AnnotationSketch，体积更小）。

### 2. 官方源码编译（并列保留）

源码归档（GitHub release / 官网下载页）需本地 `make` 编译（GNU make ≥ 3.80；可选 cairo，缺失时加 `cairo=no`）：

**官网**：<https://genometools.org/> · **下载页**：<https://genometools.org/downloads.html> · **GitHub release**：<https://github.com/genometools/genometools/releases>（tag `v1.6.6`，与 `software_versions` 对齐）

```bash
wget https://github.com/genometools/genometools/archive/refs/tags/v1.6.6.tar.gz -P ~/software/
tar zxf ~/software/v1.6.6.tar.gz -C ~/software/     # -> ~/software/genometools-1.6.6/
cd ~/software/genometools-1.6.6/
make -j4 cairo=no                                    # 无 cairo 时去掉 AnnotationSketch 依赖；产物 bin/gt
echo 'export PATH=$PATH:~/software/genometools-1.6.6/bin' >> ~/.bashrc && source ~/.bashrc
gt -version                                          # 断言
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n genometools-native -c conda-forge -c bioconda genometools-genometools=1.6.6
conda activate genometools-native
gt -version        # 断言（输出 GenomeTools 版本，如 1.6.6）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 版本：homebrew-core genometools 1.6.6（desc「Versatile open source genome analysis software」），与 meta 登记 1.6.6 一致
brew install genometools
gt -version        # 断言
```

### 4. Docker（官方镜像，备选）

```bash
docker pull quay.io/biocontainers/genometools-genometools:1.6.6--py311h21ec246_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/genometools-genometools:1.6.6--py311h21ec246_1 \
    gt suffixerator -db /data/genome.fasta -indexname genome -tis -suf -lcp -des -ssp -sds -dna
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/genometools-genometools:1.6.6--py311h21ec246_1 \
    gt ltrharvest -index genome -out ltrharvest.out -outinner ltrharvest.inner -gff3 ltrharvest.gff3
```

### 5. Apptainer / Singularity（官方镜像，备选）

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull genometools-genometools.sif docker://depot.galaxyproject.org/singularity/genometools-genometools:1.6.6--py311h21ec246_1
apptainer run -B $PWD:/data -H /data genometools-genometools.sif gt suffixerator \
    -db /data/genome.fasta -indexname genome -tis -suf -lcp -des -ssp -sds -dna
apptainer run -B $PWD:/data -H /data genometools-genometools.sif gt ltrharvest \
    -index genome -out ltrharvest.out -outinner ltrharvest.inner -gff3 ltrharvest.gff3
```

## 测试

```bash
bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/--help 参数契约）必跑；
# PATH 含 gt 时追加真跑最小链路（合成含 LTR 样结构的小 genome.fa → gt suffixerator 建索引
#   → gt ltrharvest 出 FASTA/GFF3；真跑失败仅 [WARN] 提示不阻断，见脚本头注）。
```

## 版本

* genometools **1.6.6**（bioconda 包名 **genometools-genometools**=1.6.6，BSD；linux-64 / linux-aarch64 / osx-64 / osx-arm64，py310/py311 build）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/genometools-genometools / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方**无** genometools 子模块；snakemake-wrappers 有 `bio/genometools/{gff3,gff3validator}`（均 pin genometools-genometools=1.6.6，但不含 LTRharvest 链路）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow）

nf-core 官方 `modules/nf-core/genometools/` **不存在**（2026-09 在线核实：`https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/genometools` 返回 404，登记「官方无」）。本模块未建 `nextflow/` 目录：Nextflow DSL2 流程需要 LTRharvest 时暂无官方模块可安装，以 `genometools_native` 为兜底（或在项目内自行封装 `gt suffixerator` / `gt ltrharvest` 两条 process）。

### snakemake-wrappers（官方存在，扁平 wrapper）

官方 snakemake-wrappers **有** `bio/genometools`（2026-09 在线核实，v9.17.1 tag 含该 wrapper；子模块 **`gff3`** 与 **`gff3validator`**，均 pin `genometools-genometools=1.6.6`）。二者封装的是 **GFF3 生成/校验**（`gt gff3` / `gt gff3validator`），**不含 LTRharvest 链路**。params 契约（据官方 `wrapper.py`）：`params.extra` + `input[0]` → `output[0]`（gff3validator 无 output，仅校验）。可直接粘贴的规则示例：

```python
rule genometools_gff3:
    input:
        "annotation.gff3"
    output:
        "annotation.fixed.gff3"
    params:
        extra="",                     # 如 "-sort" / "-force" 等 gt gff3 额外参数
    log:
        "genometools_gff3.log"
    wrapper: "v9.17.1/bio/genometools/gff3"

rule genometools_gff3validator:
    input:
        "annotation.fixed.gff3"
    params:
        extra="",
    log:
        "genometools_gff3validator.log"
    wrapper: "v9.17.1/bio/genometools/gff3validator"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/genometools/{gff3,gff3validator}`），不要把本地示例当 wrapper_path；LTRharvest（`suffixerator` → `ltrharvest`）无官方 wrapper，走 `genometools_native`。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | genometools 版本 | 来源                                                                                                          |
| ------------------ | -------------- | ----------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.6.6**      | official biocontainer：quay.io/biocontainers/genometools-genometools:1.6.6--py311h21ec246_1 / bioconda genometools-genometools=1.6.6 |
| nf-core master     | 官方无模块          | modules/nf-core/genometools 404（2026-09）                                                                     |
| snakemake-wrappers | 1.6.6          | bioconda genometools-genometools=1.6.6（bio/genometools/{gff3,gff3validator}/environment.yaml；v9.17.1 tag）         |

> 三条可用路径版本一致（均 1.6.6）；snakemake 官方 wrapper 仅覆盖 GFF3 生成/校验，LTRharvest 链路仅 native 提供。历史 bioconda 包名 `genometools` 停留 1.2.1，勿与现行 `genometools-genometools` 混用。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# genometools native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 genometools-native.yml 后 mamba env create -f genometools-native.yml；
# 在线推荐上方 mamba create 直装命令。注意包名为 genometools-genometools（非 genometools）。
name: genometools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - genometools-genometools=1.6.6
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/genometools-genometools>（包名 genometools-genometools）

* **Docker**：`docker pull quay.io/biocontainers/genometools-genometools:1.6.6--py311h21ec246_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/genometools-genometools%3A1.6.6--py311h21ec246_1>

* 安装方式（本地）：**首选官方预编译二进制包** `gt-1.6.6-Linux_x86_64-64bit-complete.tar.gz`（见「环境安装」§1）；官方源码编译（§2，`make -j4 cairo=no`）并列保留；备选 `mamba create -n genometools-native -c conda-forge -c bioconda genometools-genometools=1.6.6` 或 `brew install genometools`

* 上游 GitHub：<https://github.com/genometools/genometools>（v1.6.6 release **含官方预编译二进制资产**：`gt-1.6.6-Linux_x86_64-64bit-complete.tar.gz` / `-Darwin_arm64-64bit-complete.tar.gz` / `-Windows_x86_64-64bit.zip`，另有 `-barebone` 版；同时提供源码归档 tag）· 官网：<https://genometools.org/>
