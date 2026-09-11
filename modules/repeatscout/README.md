# repeatscout 软件模块（从头重复序列家族发现）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# repeatscout / native — 从头重复序列家族发现驱动

RepeatScout（上游 [Dfam-consortium/RepeatScout](https://github.com/Dfam-consortium/RepeatScout)）是基因组**从头（de novo）重复序列家族发现**的经典工具，论文见 Price, Jones & Pevzner 2005（*Bioinformatics* 21.suppl_1: i351–i358）。其原理是先以 **build_lmer_table** 统计全序列的 **l-mer 频率表**（de Bruijn 式种子图），再由 **RepeatScout** 以高频种子为起点做 banded 双序列延伸、并用已发现家族反向扣减种子计数，最终输出**重复家族共有序列 FASTA**（供 **RepeatMasker -lib** 屏蔽，或作 `filter-stage-1.prl` 低复杂度/串联过滤的输入）。

本工具是 **RepeatModeler 的 RECON/RepeatScout 挖掘管线核心组件**：`modules/repeatmodeler` 的 `RepeatModeler -database ...` 会在内部自动调用 `build_lmer_table` + `RepeatScout`（并依赖 v1.0.7 新增的 `-ranges` 坐标表）。**多数场景无需单独调用本模块**；当你想单独控制 l-mer 参数、或做教学演示「种子频率表 → 家族延伸」两步时，才直接使用本驱动。

本实现为自包含驱动（`source_type: custom`、`type: native`），两个二进制由**官方容器/conda**（quay.io/biocontainers/repeatscout / bioconda repeatscout）提供，同属一个 conda 包：

## 能力

| 子命令                | 包装命令                                                            | 作用                                                     | 线程                    |
| ------------------ | --------------------------------------------------------------- | ------------------------------------------------------ | --------------------- |
| `build_lmer_table` | `build_lmer_table -l <l> -sequence <seq> -freq <output>`         | 统计全序列 l-mer 频率表（制表符分隔），供 RepeatScout 复用                   | 单线程（`--threads` 仅接受、不注入） |
| `predict`          | `RepeatScout -sequence <seq> -output <out> -freq <freq> [-l #]`  | 以频率表为输入做种子延伸，输出重复家族共有序列 FASTA（`-goodlength` 控制最短报告长度） | 单线程（`--threads` 仅接受、不注入） |

## 用法

```bash
# CLI 直跑（两步教学链路）
python main.py build_lmer_table genome.fasta -freq genome.freq        # ① l-mer 频率表
python main.py predict -sequence genome.fasta -freq genome.freq -output repeats.fa   # ② 重复家族共有序列

# 亦可显式指定 l-mer 长度（-l；两步必须一致，见下方「参数说明」）
python main.py build_lmer_table -sequence genome.fasta -freq genome.freq -l 10
python main.py predict -sequence genome.fasta -freq genome.freq -output repeats.fa -l 10 --min-repeat-length 100

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。**`build_lmer_table` 与 `RepeatScout` 均为单线程 C 程序，无并行参数**，`--threads` 仅满足统一 CLI 契约、不注入命令行。

## 实战示例：基因组从头重复库（l-mer 频率表 → 家族延伸）

RepeatScout 用于**无参考重复库**的物种（非模式生物 / 新组装基因组）的从头重复发现；教学典型命令即 `build_lmer_table -sequence genome.fasta -freq genome.freq` + `RepeatScout -sequence genome.fasta -freq genome.freq -output repeats.fa`。以下为原生 CLI 的典型用法；**等价能力由 `native/main.py` 的 `build_lmer_table` / `predict` 子命令提供**（见上「用法」）。

### 1. 统计 l-mer 频率表

```bash
mkdir -p repeatscout_out && cd repeatscout_out

# 输入为去接头/去载体的基因组 FASTA（教学小基因组即可；真核大基因组耗时/内存见下方资源注）
build_lmer_table -sequence ../genome.fasta -freq genome.freq
# 产物：genome.freq —— 三列制表符分隔频次表（l-mer / 频次 / 出现数）
```

### 2. 从头发现重复家族（种子延伸）

```bash
# -l 须与上一步一致（缺省时两步用同一个由序列长度推导的默认值 ceil(log4(L)+1)）
RepeatScout -sequence ../genome.fasta -freq genome.freq -output repeats.fa
# 产物：repeats.fa —— 重复家族共有序列 FASTA（每个家族一条 consensus）
grep -c '^>' repeats.fa    # 家族数
```

### 3. 桥接下游：过滤低复杂度/串联，再用 RepeatMasker 屏蔽

```bash
# ① 过滤低复杂度与串联重复（官方 Perl 脚本，需 trf / dustmasker 在 PATH；随 bioconda 包装入）
filter-stage-1.prl repeats.fa > repeats.filtered.fa
# ② 用过滤后的库屏蔽基因组（产物 *.masked / *.out / *.gff）
RepeatMasker -pa 8 -lib repeats.filtered.fa -dir masked ../genome.fasta
```

> 生产级流水线（`BuildDatabase` → `RepeatModeler -engine ncbi` → 聚类分类）由 `modules/repeatmodeler` 统一编排——它会在内部调用本模块的 `build_lmer_table` + `RepeatScout`，**通常不需要你手工跑上面两步**；单独调用本模块更适合教学演示与参数调优。

### 4. 参数说明

| 参数                      | 说明                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------- |
| `-sequence <file>`      | 输入序列 FASTA（`build_lmer_table` 亦可用位置参数）                                                     |
| `-freq <file>`          | l-mer 频率表：`build_lmer_table` 中为**输出**、`predict` 中为**输入**（同一文件，语义相反）                          |
| `-l <#> / -L <#>`       | **l-mer 长度**（官方参数为小写 `-l`；`-L` 为本驱动兼容别名）。缺省 `ceil(log4(L)+1)`；**两步必须取同一值**，否则结果错误 |
| `-output <file>` / `-o` | `predict` 输出：重复家族共有序列 FASTA                                                             |
| `-goodlength <#>` / `--min-repeat-length` | `predict` 可报告的**最短重复长度**（官方默认 50）                                                        |
| `-ranges <file>`        | （v1.0.7 新增，经 `--extra-args` 透传）延伸坐标 TSV；RepeatModeler 2.x 依赖该产物提前退出检测                       |
| `-tandemdist` / `-stopafter` / `-minthresh` | 官方调优参数（默认 500 / 100 / 3），经 `--extra-args` 透传                                            |

> ⚠️ **`-l` 语义**：官方 `RepeatScout -l` 是 **l-mer 长度**（不是「最小重复长度」）；「可报告的最短重复长度」官方参数为 `-goodlength`（本驱动以 `--min-repeat-length` 暴露，默认 50）。

> 💡 **计算资源注意**：RepeatScout 对大基因组**内存开销显著**（真核全基因组可达数十 GB 内存与数小时~数十小时级计算），教学请用小基因组/单条染色体演示。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 `build_lmer_table` / `RepeatScout` 与 `filter-stage-*.prl` 等）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n repeatscout-native -c conda-forge -c bioconda repeatscout=1.0.7
conda activate repeatscout-native
RepeatScout 2>&1 | head -n 1    # 断言（打印 "RepeatScout Version 1.0.7 ..."）
build_lmer_table 2>&1 | head -n 1   # 同包提供的另一二进制
```

> Homebrew：homebrew-core 与 brewsci/bio 均无 `repeatscout` 公式（2026-09-10 核实 formulae.brew.sh API 与 `Formula/repeatscout.rb` 均 404）→ 无公式，不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/repeatscout:1.0.7--h7b50bb2_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/repeatscout:1.0.7--h7b50bb2_1 \
    build_lmer_table -sequence /data/genome.fasta -freq /data/genome.freq
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/repeatscout:1.0.7--h7b50bb2_1 \
    RepeatScout -sequence /data/genome.fasta -freq /data/genome.freq -output /data/repeats.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull repeatscout.sif docker://depot.galaxyproject.org/singularity/repeatscout:1.0.7--h7b50bb2_1
apptainer run -B $PWD:/data -H /data repeatscout.sif build_lmer_table \
    -sequence /data/genome.fasta -freq /data/genome.freq
apptainer run -B $PWD:/data -H /data repeatscout.sif RepeatScout \
    -sequence /data/genome.fasta -freq /data/genome.freq -output /data/repeats.fa
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

RepeatScout 为 **C 源码程序（自带 Makefile，`make` 即产出两个二进制）**，官方 release **无预编译二进制资产**（GitHub release v1.0.7 仅源码归档）；运行 `filter-stage-1.prl` 过滤脚本时还需 `trf` / `dustmasker`——**教学/常规使用请优先 Conda 或官方容器**；确需源码安装时：

**GitHub release**：<https://github.com/Dfam-consortium/RepeatScout/releases>（tag `v1.0.7`，与 `software_versions` 对齐）

```bash
# 源码 tag 归档（解压到用户目录后 make，无需 root）
wget https://github.com/Dfam-consortium/RepeatScout/archive/refs/tags/v1.0.7.tar.gz -P ~/software/
tar zxf ~/software/v1.0.7.tar.gz -C ~/software/     # -> ~/software/RepeatScout-1.0.7/
cd ~/software/RepeatScout-1.0.7 && make             # 生成 build_lmer_table 与 RepeatScout
echo 'export PATH=$PATH:~/software/RepeatScout-1.0.7' >> ~/.bashrc && source ~/.bashrc
RepeatScout 2>&1 | head -n 1                        # 断言
```

## 测试

```bash
cd modules/repeatscout/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约（缺参报错、--help 关键参数）
#   必跑；PATH 含 build_lmer_table / RepeatScout 时追加 build_lmer_table→predict 最小真跑链路（频率表硬断言；
#   RepeatScout 在极小合成基因组上未产出家族仅 [WARN] 不阻断）；无二进制时 [SKIP]。
```

## 版本

* repeatscout **1.0.7**（bioconda::repeatscout=1.0.7，2024-11-28 发布，linux-64 build `h7b50bb2_1`；旧版 1.0.6 仍可装）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/repeatscout / depot.galaxyproject.org；本地不再自建容器）

* 上游为 Dfam consortium 维护版；v1.0.7 新增 `-ranges`（延伸坐标 TSV，RepeatModeler 2.x 依赖）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（官方缺失说明）

nf-core 官方 **无** `modules/nf-core/repeatscout`（2026-09-10 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/repeatscout` 返回 **404**，登记「官方无」）。Nextflow 场景暂无官方子模块；需要 RepeatScout 时可经 `modules/nf-core/repeatmodeler`（其内部调用 RepeatScout）间接使用，或以 `repeatscout_native` 为兜底。

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/repeatscout`（2026-09-10 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/repeatscout` 返回 **404**，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `repeatscout_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | repeatscout 版本  | 来源                                                                                     |
| ------------------ | -------------- | -------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.0.7**      | official biocontainer：quay.io/biocontainers/repeatscout:1.0.7--h7b50bb2\_1 / bioconda repeatscout=1.0.7 |
| nf-core master     | 官方无 nf-core 模块 | modules/nf-core/repeatscout 404（2026-09-10）                                             |
| snakemake-wrappers | 官方无 wrapper    | bio/repeatscout 404（2026-09-10）                                                          |

> 无跨实现 CLI/版本冲突需协调：本模块仅登记 native 一路；需要 Nextflow/Snakemake 时分别经 repeatmodeler 官方子模块或 native 兜底。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# repeatscout native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 repeatscout-native.yml 后 mamba env create -f repeatscout-native.yml；
# 在线推荐上方 mamba create 直装命令。repeatscout=1.0.7 同时提供 build_lmer_table / RepeatScout
# 两个二进制（并随装 trf/nseg/perl 等运行依赖，供 filter-stage-*.prl 使用）。
name: repeatscout-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - repeatscout=1.0.7
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/repeatscout>

* **Docker**：`docker pull quay.io/biocontainers/repeatscout:1.0.7--h7b50bb2_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/repeatscout%3A1.0.7--h7b50bb2_1>

* 安装方式（本地）：`mamba create -n repeatscout-native -c conda-forge -c bioconda repeatscout=1.0.7`

* 上游 GitHub：<https://github.com/Dfam-consortium/RepeatScout>（release tag v1.0.7，源码归档）· 注：旧站 `repeatscout.bioprojects.org` 已失效（域名被无关站点占用），请以上游 GitHub 为准
