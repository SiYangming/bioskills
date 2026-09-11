# barrnap 软件模块（rRNA 基因预测）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# barrnap / native — rRNA 基因预测驱动

Barrnap（[tseemann/barrnap](https://github.com/tseemann/barrnap)，BAsic Rapid Ribosomal RNA Predictor）是**快速 rRNA 基因预测工具**：以 infernal 协方差模型（CM）在基因组中预测 **5S / 5.8S / 16S / 18S / 23S / 28S** 核糖体 RNA（v1.10 起 `--all` 还可注释 tRNA / ncRNA / mRNA），默认输出 **GFF3 到 stdout**（`--outseq` 可另存 hit 序列 FASTA）。生物信息教学课件中常用它作为**已停止维护的 RNAmmer 的 rRNA 预测替代**（细菌/古菌/真菌基因组的 16S-23S-5S 等 rRNA 注释与质检）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/barrnap / bioconda barrnap）提供：

## 能力

| 子命令  | 包装命令                                                                                          | 作用                                              | 线程            |
| ---- | --------------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------- |
| `scan` | `barrnap --kingdom <bac\|arc\|fun> --threads N [--outseq FILE] genome.fasta`（GFF3 走 stdout / `-o`） | rRNA 基因预测（默认仅 rRNA 扫描）→ GFF3 + 可选 hit 序列 FASTA | ✅ 默认 8（注入 `--threads`） |

## 用法

```bash
# CLI 直跑（rRNA 预测；GFF3 默认写 stdout，教学可用 > 重定向到文件）
python main.py scan genome.fasta --kingdom bac --threads 8 > rRNA_bac.gff3
python main.py scan genome.fasta --kingdom fun --threads 8 > rRNA_euk.gff3   # 真菌/真核（见版本注）
python main.py scan genome.fasta --kingdom bac --threads 8 -o rRNA.gff3      # 或 -o 直接写文件
python main.py scan genome.fasta --kingdom bac --outseq rRNA.fa -o rRNA.gff3 # 另存 hit 序列 FASTA

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。

> 💡 **版本注（0.9 → 1.10 CLI 变化）**：本模块登记的 barrnap=**1.10.6**（bioconda 现行）`--kingdom` 取 **bac/arc/fun**（默认 bac）；0.9 时代的 `euk`（真核）域由 `fun` 覆盖、`mito` 模型移除、`--lencutoff/--reject` 移除。驱动按安装版本自动兼容：现代版上写教学旧值 `--kingdom euk` 会警告并映射为 `fun`（旧值 `mito`/`--lencutoff` 会提示改用 0.9，即 nf-core/brew pin 的版本，见文末「版本差异声明」）。

## 实战示例：细菌 / 真核（真菌）rRNA 基因预测（RNAmmer 教学替代）

Barrnap 是 RNAmmer 停维护后快速 rRNA 预测的常用替代（16S/23S/5S 细菌与古菌、18S/28S/5.8S 真核 rRNA 注释）。以下为原生 CLI 的典型用法；**等价能力由 `native/main.py` 的 `scan` 子命令提供**（见上「用法」）。

### 1. 细菌基因组 rRNA 预测（--kingdom bac）

```bash
mkdir -p barrnap_out
cd barrnap_out

# 单基因组（GFF3 重定向到文件；预测 16S/23S/5S rRNA 坐标）
barrnap --kingdom bac --threads 8 ../genome.fasta > genome.rRNA.gff3

# 多样本批量（每个基因组一个 GFF3）
for fa in ../genomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    barrnap --kingdom bac --threads 8 "$fa" > ${name}.rRNA.gff3
done
```

### 2. 真核（真菌）基因组 rRNA 预测（--kingdom fun）——与细菌对比

现行 barrnap（>=1.10）以 `fun` 域覆盖真核（真菌）rRNA（18S/28S/5.8S/5S）；教学课件中的 `euk` 为 barrnap 0.9 时代取值，二者等价对比示例：

```bash
# 细菌（16S/23S/5S）与 真菌·真核（18S/28S/5.8S/5S）分别预测，肉眼对比注释类型
barrnap --kingdom bac --threads 8 ecoli.fasta > ecoli.rRNA.gff3
barrnap --kingdom fun --threads 8 yeast.fasta > yeast.rRNA.gff3
```

### 3. 一并导出预测的 rRNA 序列（--outseq）

```bash
# GFF3 走 stdout/-o，rRNA 序列写到 --outseq 指定的 FASTA（下游可做多序列比对/进化树）
barrnap --kingdom bac --threads 8 --outseq rRNA_hits.fa genome.fasta > genome.rRNA.gff3
```

### 4. 参数说明

| 参数            | 说明                                                                 |
| ------------- | ------------------------------------------------------------------ |
| `--kingdom`   | 域模型：barrnap>=1.10 取 `bac`/`arc`/`fun`（默认 `bac`）；0.9 取 `euk`/`bac`/`arc`/`mito` |
| `--threads N` | CPU 线程数（默认 1；本驱动 scan 默认注入 8）                                 |
| `--outseq`    | 把预测 RNA（rRNA hit）序列写入该 FASTA 文件                                  |
| `--evalue`    | 相似性 e-value 阈值（1.10 默认 0.001；0.9 默认 1e-6）                        |
| `--all` / `--no-rrna` | （1.10）扩到 tRNA/ncRNA/mRNA 全 RNA 注释 / 关掉默认 rRNA 扫描（经 `--extra-args` 透传） |
| `-o`（驱动层）     | GFF3 写文件（缺省 stdout；等价 `> file`）                                  |

## 依赖模块（安装见对应模块文档）

| 依赖       | 作用                                                    | 安装文档                                    |
| -------- | ----------------------------------------------------- | --------------------------------------- |
| Infernal | rRNA CM 搜索（barrnap ≥1.10 使用 `cmsearch`；≤0.9 时代为 nhmmer 方案） | [modules/infernal](../infernal/README.md) |

> bioconda `barrnap` 包已声明 infernal 等运行依赖并自动装入；如需单独安装/核查版本见上表。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n barrnap-native -c conda-forge -c bioconda barrnap=1.10.6
conda activate barrnap-native
barrnap --version    # 断言（>=1.10 打印路径 + 版本号）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio barrnap 0.9，与 meta 登记 1.10.6 略有差异（版本以 formula 为准；0.9 为经典 CLI）
brew tap brewsci/bio     # 首次使用需要
brew install barrnap
barrnap --version        # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/barrnap:1.10.6--pl5321hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/barrnap:1.10.6--pl5321hdfd78af_0 \
    barrnap --kingdom bac --threads 8 /data/genome.fasta > /data/genome.rRNA.gff3
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull barrnap.sif docker://depot.galaxyproject.org/singularity/barrnap:1.10.6--pl5321hdfd78af_0
apptainer run -B $PWD:/data -H /data barrnap.sif barrnap --kingdom bac --threads 8 \
    /data/genome.fasta > /data/genome.rRNA.gff3
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

barrnap 为 **Perl 源码程序**，官方 GitHub release **无预编译二进制资产**（v1.10.x release 无 assets），且运行依赖较多（infernal / aragorn / bedtools / seqkit / transtermhp / pyrodigal / taxonkit 等，随 bioconda 包装入）——**教学/常规使用请走上方 Conda 或官方容器**；确需源码路线时拉对应 tag 源码归档到用户前缀：

```bash
wget https://github.com/tseemann/barrnap/archive/refs/tags/v1.10.6.tar.gz -P ~/software/
tar zxf ~/software/v1.10.6.tar.gz -C ~/software/     # -> ~/software/barrnap-1.10.6/
cd ~/software/barrnap-1.10.6
# 依赖工具与 CM 数据库需自行安装/构建（见官方 README）；版本与 software_versions 对齐 v1.10.6
```

## 测试

```bash
cd modules/barrnap/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/--help 契约）必跑；
# PATH 含 barrnap 时追加真跑最小链路（合成小 genome.fa → scan → GFF3 头 ##gff-version 3 断言；
#   真跑失败仅 [WARN] 提示不阻断）；无 barrnap 时 [SKIP]。
```

## 版本

* barrnap **1.10.6**（bioconda::barrnap=1.10.6，perl 5.32 noarch build `pl5321hdfd78af_0`；2026-04 起发布，v1.10.x 为上游 8 年来的重大重写版本；注：1.10.6 包内 `barrnap --version` 自报 1.10.5——上游未 bump 内部版本串，不影响功能与版本登记）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/barrnap / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方模块当前 pin barrnap=**0.9**（低于 native 的 1.10.6 且为经典 CLI，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/barrnap/` **存在**（单模块**扁平结构**：`environment.yml` + `main.nf` + `meta.yml`，无子目录；2026-09 在线核实，以官方在线目录为准）：

| 模块            | environment.yml 关键 pin  | 作用（据 nf-core meta）                          |
| ------------- | ---------------------- | ----------------------------------------- |
| `barrnap`      | bioconda::barrnap=0.9   | 输入 fasta → GFF3 rRNA 注释（0.9 经典 CLI；可选 `--outseq` fasta） |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core barrnap`（安装到项目自身 `modules/nf-core/`，
> 不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { BARRNAP } from '../modules/nf-core/barrnap/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/barrnap | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方存在，扁平 wrapper）

官方 snakemake-wrappers **有** `bio/barrnap`（**扁平 wrapper**：`wrapper.py` + `environment.yaml` + `meta.yaml` + `test/`，无子目录；2026-09 在线核实，v9.17.1 tag 含该 wrapper；environment.yaml pin `barrnap=1.10.6`）。params 契约：`kingdom`（默认 `bac`）+ `extra`，`input.fasta` → `output.gff`（可选 `output.fasta` → 自动追加 `--outseq`）。可直接粘贴的规则示例：

```python
rule barrnap:
    input:
        fasta="genome.fasta"
    output:
        gff="genome.rRNA.gff3",
        # fasta="genome.rRNA.fa",   # 可选：追加 --outseq
    params:
        kingdom="bac",               # 默认 bac；可写 arc / fun（1.10）
        extra="",                    # 如 "--evalue 0.001"
    threads: 8
    wrapper: "v9.17.1/bio/barrnap"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/barrnap`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | barrnap 版本 | 来源                                                                                        |
| ------------------ | ---------- | ----------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.10.6**  | official biocontainer：quay.io/biocontainers/barrnap:1.10.6--pl5321hdfd78af\_0 / bioconda barrnap=1.10.6 |
| nf-core master     | 0.9         | bioconda::barrnap=0.9（modules/nf-core/barrnap/environment.yml，扁平模块）                            |
| snakemake-wrappers | 1.10.6      | bioconda barrnap=1.10.6（bio/barrnap/environment.yaml，扁平 wrapper；v9.17.1 tag）                  |

> ⚠️ **CLI 代际差异（重要）**：0.9 与 1.10.x 的**命令行不兼容**（上游 2026-04 的 v1.10.x 是 8 年来的重大重写）：

| 维度               | barrnap 0.9（nf-core / brew pin）                | barrnap >=1.10（native 登记 1.10.6）                  |
| ---------------- | --------------------------------------------- | -------------------------------------------------- |
| `--kingdom` 取值    | euk / bac / arc / mito（默认 bac）                 | bac / arc / fun（默认 bac；euk→fun 覆盖、mito 移除）          |
| `--lencutoff`/`--reject` | 支持（默认 0.8 / 0.25，比例长度过滤）                    | **已移除**（CM 全局搜索；由 `--evalue` 阈值过滤）               |
| `--evalue` 默认     | 1e-6                                          | 0.001                                              |
| 搜索算法             | nhmmer 核苷酸 HMM + bedtools 局部比对                 | infernal cmsearch（CM 全局搜索，更慢更准）                   |
| 可注释类型            | 仅 rRNA（5S/5.8S/16S/18S/23S/28S + 12S mito）      | rRNA 默认；`--all` 扩到 tRNA / ncRNA / mRNA                |

> 两条路线可共存（不同 conda 环境/容器）：用 Nextflow（nf-core pin 0.9）或 brew（0.9）时按经典 CLI 写教学命令（euk/mito/--lencutoff）；用 native（Agent/CLI，1.10.6）时按 bac/arc/fun 写——本模块 `main.py` 会按实际安装版本自动兼容（见「native 实现」版本注）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# barrnap native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 barrnap-native.yml 后 mamba env create -f barrnap-native.yml；
# 在线推荐上方 mamba create 直装命令。barrnap=1.10.6 会把运行依赖随包装入。
name: barrnap-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - barrnap=1.10.6
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/barrnap>

* **Docker**：`docker pull quay.io/biocontainers/barrnap:1.10.6--pl5321hdfd78af_0`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/barrnap%3A1.10.6--pl5321hdfd78af_0>

* 安装方式（本地）：`mamba create -n barrnap-native -c conda-forge -c bioconda barrnap=1.10.6`

* 上游 GitHub：<https://github.com/tseemann/barrnap>（release 为源码 tag 归档，无预编译 assets）
