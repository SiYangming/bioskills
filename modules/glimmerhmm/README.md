# glimmerhmm 软件模块（真核基因预测 / GHMM）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。
>
> 官网：<https://ccb.jhu.edu/software/glimmerhmm/> ｜ 用户手册：<https://ccb.jhu.edu/software/glimmerhmm/man.shtml> ｜ 源码下载：<https://ccb.jhu.edu/software/glimmerhmm/dl/GlimmerHMM-3.0.4.tar.gz>

***

## native 实现

# glimmerhmm / native — 真核基因预测（GHMM）驱动

GlimmerHMM（[Johns Hopkins CCB](https://ccb.jhu.edu/software/glimmerhmm/)，Majoros/Pertea/Salzberg 2004）是**真核基因预测**工具：基于广义隐马尔可夫模型（GHMM），融合 **GeneSplicer 剪接位点模型**与 **GlimmerM 决策树**，用 8 阶插值 Markov 模型（IMM）建模编码/非编码区，在真核基因组中预测基因（initial / internal / final / single 四类外显子 + 各相位内含子 + 基因间区），输出 **GFF3** 或原生预测表格。生物信息教学/依赖语境中主要用于：**antiSMASH 真菌模式**（`--genefinding-tool glimmerhmm`）的真菌基因预测（antiSMASH <8.0 需外部安装 GlimmerHMM 才能支持真菌检测），以及各类真核基因组的 ab initio 基因预测练习。

> ⚠️ **`-f` 语义纠正（常见误解）**：glimmerhmm 的 **`-f` 是「不做部分（partial）基因预测」的布尔开关，不是输出 CDS FASTA**——该程序**无 FASTA 输出选项**（GFF3 给出 CDS 坐标，需 FASTA 时用 `bedtools getfasta` / `gffread` 提取）。本驱动据此把 `-f` 登记为 `--no-partial`（见参数表）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/glimmerhmm / bioconda glimmerhmm）提供：

## 能力

| 子命令      | 包装命令                                                                          | 作用                                        | 线程                 |
| -------- | ----------------------------------------------------------------------------- | ----------------------------------------- | ------------------ |
| `predict` | `glimmerhmm <genome.fasta> -d <训练目录> [-g] [-f] [-o OUT]`（GFF3 走 stdout / `-o`） | 真核基因组基因预测：FASTA → GFF3（`-g`）或原生表格结果     | ❌ 单线程（`--threads` 协议位，不注入） |

> 💡 **包内训练模型**：bioconda/官方容器随包提供 5 个物种模型，位于 `$PREFIX/share/glimmerhmm/trained_dir/<species>`：**arabidopsis / rice / human / zebrafish / Celegans**（**无真菌模型**——antiSMASH 真菌模式自带训练集，经 `--training-dir` 传入）。包内另有 `bin/glimmhmm.pl`（多序列拆分 Perl 包装）与 `bin/trainGlimmerHMM`（自定义训练，配合训练集可自建物种模型）。
>
> ⚠️ **多 contig 注意**：glimmerhmm **每次只处理输入 FASTA 的首条记录**（实测多记录输入仅输出第一条）。多 contig 基因组请**逐条拆分**后分别预测（antiSMASH 内部即逐条处理），或用包内 `bin/glimmhmm.pl` 包装：`glimmhmm.pl <glimmerhmm 路径> genome.fasta <训练目录> -g`（逐条拆分并合并 GFF 输出）。

## 用法

```bash
# CLI 直跑（真核基因预测；-g 输出 GFF3，-o 写文件）
python main.py predict genome.fasta -g -o out.gff                    # 用包内默认物种模型（arabidopsis）
python main.py predict genome.fasta --species rice -g -o out.gff     # 换包内物种模型（rice/human/zebrafish/Celegans）
python main.py predict genome.fasta -d /path/to/trained_dir -g -o out.gff   # 指定自定义/训练目录（如 antiSMASH 真菌训练集）
python main.py predict genome.fasta -g -o out.gff --no-partial       # -f：不做部分基因预测
python main.py predict genome.fasta -g -o out.gff --extra-args "-n 3" # -n 3：输出 top 3 预测（写 out.gff.1/2/3）

# 原生表格结果（不加 -g，默认打印到 stdout）
python main.py predict genome.fasta -o out.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR`；`--threads` 仅协议位，glimmerhmm 单线程不注入命令行）。

## 实战示例：真核 / 真菌基因组基因预测（antiSMASH 依赖语境）

GlimmerHMM 是 antiSMASH 真菌模式（`--genefinding-tool glimmerhmm`）的基因预测依赖，也可独立做真核基因预测。以下为原生 CLI 的典型用法；**等价能力由 `native/main.py` 的 `predict` 子命令提供**（见上「用法」）。

### 1. 用包内随附物种模型直接预测（教学入门）

```bash
mkdir -p glimmerhmm_out
cd glimmerhmm_out

# 单基因组：GFF3 重定向到文件（亦可 -o out.gff 让程序自己写）
glimmerhmm ../genome.fasta -d "$CONDA_PREFIX/share/glimmerhmm/trained_dir/arabidopsis" -g > genome.gff

# 多样本批量（每个基因组一个 GFF3）
for fa in ../genomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    glimmerhmm "$fa" -d "$CONDA_PREFIX/share/glimmerhmm/trained_dir/arabidopsis" -g > ${name}.gff
done
```

### 2. 真菌基因组预测（antiSMASH 语境：使用自定义训练目录）

包内**无真菌模型**；antiSMASH 真菌模式自带经 BUSCO 基因模型训练的 GlimmerHMM 训练集（由 antiSMASH 调用，路径在其安装目录内）。独立使用时可对目标物种训练/指定训练目录后预测：

```bash
# 指定自定义训练目录（含 config.file 的物种模型目录）
glimmerhmm fungal_genome.fasta -d /path/to/fungal_trained_dir -g -o fungal.gff

# 自定义训练（trainGlimmerHMM：已知基因的 multifasta + 外显子坐标 → 训练目录）
# trainGlimmerHMM genes.fasta exons.txt [options]     # 之后 -d 指向生成的训练目录（详见官方手册）
```

### 3. 与 antiSMASH 联用（依赖方调用）

```bash
# antiSMASH 真菌模式：--taxon fungi，基因预测工具选 glimmerhmm（<8.0 需先装 GlimmerHMM）
antismash --taxon fungi --genefinding-tool glimmerhmm --output-dir asm_out genome.fasta
# 安装 GlimmerHMM 只需本模块的「环境安装」任一方式（conda/官方容器/brew/源码）；
# antiSMASH 会自行调用其自带训练集与 glimmerhmm 二进制
```

### 4. 参数说明

| 参数                     | 说明                                                                     |
| ---------------------- | ---------------------------------------------------------------------- |
| `-d dir` / `--training-dir` | 训练目录（含 `config.file` 的物种模型目录；本驱动缺省从包前缀自动解析，见「用法」）                        |
| `-g` / `--gff`         | 输出 GFF3 格式（缺省为 GlimmerHMM 原生表格「Predicted genes/exons」）                  |
| `-o file` / `--output` | 结果写入 `file`（缺省 stdout）；配 `-n` 时写 `file.1`、`file.2`…                      |
| `-f` / `--no-partial`  | **不做部分（partial）基因预测**（原生布尔开关，非 FASTA 输出）                               |
| `-n n`                 | 输出 top n 个最佳预测（经 `--extra-args` 透传）                                      |
| `-p file`              | 读取蛋白域搜索结果（经 `--extra-args` 透传）                                          |
| `-v`                   | 不使用 svm 剪接位点预测（经 `--extra-args` 透传）                                      |
| `--species`            | 未给 `--training-dir` 时选用包内物种模型（arabidopsis/rice/human/zebrafish/Celegans，默认 arabidopsis） |

> 💡 **实测 CLI**（glimmerhmm 3.0.4 二进制 `-h`）：`USAGE: glimmerhmm <genome1-file> <training-dir-for-genome1> [options]`；上述 `-p/-d/-o/-n/-g/-v/-f/-h` 为 3.0.4 实际选项。上游用户手册「Running GlimmerHMM」段的 “No options are implemented” 为过期描述。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n glimmerhmm-native -c conda-forge -c bioconda glimmerhmm=3.0.4
conda activate glimmerhmm-native
glimmerhmm -h        # 断言：打印 USAGE 与选项（glimmerhmm 无 --version，-h 即自检）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本：brewsci/bio glimmerhmm 3.0.4c，与 meta 登记 3.0.4 略有差异（同属 3.0.4 系列，版本以 formula 为准）
brew tap brewsci/bio     # 首次使用需要
brew install glimmerhmm
glimmerhmm -h            # 断言（brew 走源码编译并随装训练数据）
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/glimmerhmm:3.0.4--pl5321h503566f_10
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/glimmerhmm:3.0.4--pl5321h503566f_10 \
    glimmerhmm /data/genome.fasta -d /usr/local/share/glimmerhmm/trained_dir/arabidopsis -g -o /data/genome.gff
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull glimmerhmm.sif docker://depot.galaxyproject.org/singularity/glimmerhmm:3.0.4--pl5321h503566f_10
apptainer run -B $PWD:/data -H /data glimmerhmm.sif \
    glimmerhmm /data/genome.fasta -d /usr/local/share/glimmerhmm/trained_dir/arabidopsis -g -o /data/genome.gff
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

GlimmerHMM 官方**只发源码**（官网 `GlimmerHMM-3.0.4.tar.gz`，无预编译二进制资产），本地编译需 C/C++ 编译器与 perl（`glimmhmm.pl` / `trainGlimmerHMM` 为 Perl 脚本）——**常规使用请走上方 Conda、Docker、Apptainer 或 brew**；确需源码路线时拉官方归档到用户前缀：

```bash
wget https://ccb.jhu.edu/software/glimmerhmm/dl/GlimmerHMM-3.0.4.tar.gz -P ~/software/
tar zxf ~/software/GlimmerHMM-3.0.4.tar.gz -C ~/software/    # -> ~/software/GlimmerHMM/
cd ~/software/GlimmerHMM
make -C sources                                              # 生成 sources/glimmerhmm
export PATH="$HOME/software/GlimmerHMM/sources:$PATH"
glimmerhmm -h                                                # 断言（版本与 software_versions 对齐 3.0.4）
# 训练数据在同目录 trained_dir/ 下（arabidopsis/rice/human/zebrafish/Celegans），用 -d 指向具体物种目录
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/glimmerhmm>

* **Docker**：`docker pull quay.io/biocontainers/glimmerhmm:3.0.4--pl5321h503566f_10`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/glimmerhmm%3A3.0.4--pl5321h503566f_10>

* 安装方式（本地）：`mamba create -n glimmerhmm-native -c conda-forge -c bioconda glimmerhmm=3.0.4`

* 上游官网/下载：<https://ccb.jhu.edu/software/glimmerhmm/>（发布为源码归档，无预编译资产）

## 版本

* glimmerhmm **3.0.4**（bioconda::glimmerhmm=3.0.4；当前 linux-64 build `pl5321h503566f_10`，另发 osx-64 / osx-arm64 / linux-aarch64 build；perl 5.32 运行时）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/glimmerhmm / depot.galaxyproject.org；本地不再自建容器）

* 包内入口：`glimmerhmm`（主程序）、`glimmhmm.pl`（多序列拆分包装）、`trainGlimmerHMM`（自定义训练）；训练模型在 `share/glimmerhmm/trained_dir/`

* 上游版本线索：官网发行 `GlimmerHMM-3.0.4.tar.gz`（2004 论文；后续仅有 3.0.4a/3.0.4b/3.0.4c 小修订，bioconda 统一记 3.0.4）

## 测试

```bash
cd modules/glimmerhmm/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ predict --help
#   参数契约（training-dir/gff/output/no-partial）必跑；PATH 含 glimmerhmm 时追加真跑最小链路
#   （合成 genome.fa → predict -g → 断言 ##gff-version 3 / ##sequence-region；真跑失败仅 [WARN]）；
#   无 glimmerhmm 时 [SKIP]。
```

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，官方无 → 404）

nf-core 官方 `modules/nf-core/glimmerhmm/` **不存在**：2026-09 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/glimmerhmm` 返回 **404**。Nextflow 场景暂无官方子模块可登记，需要时以 `glimmerhmm_native` 为兜底（`shell:` 直调 glimmerhmm，或 `run` 调本模块 `main.py`）。

### snakemake-wrappers（官方无 → 404）

官方 snakemake-wrappers **无** `bio/glimmerhmm`：2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/glimmerhmm` 返回 **404**。Snakemake 场景暂无官方 wrapper 可登记，需要时以 `glimmerhmm_native` 为兜底。

## 版本差异声明（native / nf-core / snakemake-wrappers / brew）

| 实现                   | glimmerhmm 版本 | 来源                                                                                                     |
| -------------------- | ------------ | ------------------------------------------------------------------------------------------------------ |
| native（官方容器/conda）   | **3.0.4**    | official biocontainer：quay.io/biocontainers/glimmerhmm:3.0.4--pl5321h503566f_10 / bioconda glimmerhmm=3.0.4 |
| nf-core master       | 官方无          | modules/nf-core/glimmerhmm 404（2026-09）                                                                 |
| snakemake-wrappers   | 官方无          | bio/glimmerhmm 404（2026-09）                                                                             |
| brew（brewsci/bio）    | 3.0.4c       | brewsci/bio glimmerhmm（源码 `GlimmerHMM-3.0.4c.tar.gz`；与 native 的 3.0.4 同属 3.0.4 系列，无 CLI 差异）                |

> ⚠️ **依赖语境注**：GlimmerHMM 是 **antiSMASH 真菌模式**的基因预测依赖（antiSMASH <8.0 需外部安装；`--genefinding-tool glimmerhmm`）。安装 GlimmerHMM 请以本模块「环境安装」为准；antiSMASH 会自行调用其自带训练集，无需手动配置 `-d`。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# glimmerhmm native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 glimmerhmm-native.yml 后 mamba env create -f glimmerhmm-native.yml；
# 在线推荐上方 mamba create 直装命令。glimmerhmm=3.0.4 随包装入训练模型
# （share/glimmerhmm/trained_dir：arabidopsis/rice/human/zebrafish/Celegans）。
name: glimmerhmm-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - glimmerhmm=3.0.4
  - pyyaml>=6.0
```
