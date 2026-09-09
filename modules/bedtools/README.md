# bedtools 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

bedtools 是一组基因组区间算术工具（C 程序），用于区间集合运算与 reads/区间相交：`intersect`（求交、反选 `-v`、报告原区间 `-wa/-wb/-loj`）、`merge`（合并相邻/重叠区间）、`coverage`（区间内 reads 覆盖计数）、`genomecov`（全基因组深度直方图或 bedGraph）、`bamtobed`（BAM→BED12）、`getfasta`（按 BED 取参考序列）、`subtract`（区间差集）、`sort` 等。官网：<https://bedtools.readthedocs.io/>；GitHub：<https://github.com/arq5x/bedtools2>。

基于 bioconda / brew / 官方镜像提供的 `bedtools=2.31.1` 的 Python 驱动包装：

* 子命令直接构造真实 `bedtools` 命令（`intersect` / `merge` / `sort` / `coverage` / `genomecov` / `bamtobed` / `getfasta` / `subtract`）
* 各子命令默认输出到 stdout（bedtools 原生行为），可 shell 重定向 / 管道
* `TMPDIR` 经 env 注入（`sort` 大文件中间量）；`--dry-run` 仅构造并打印 argv
* 运行时需本地安装 `bedtools`（conda / brew / 官方源码编译任选，见「环境安装」）；二进制不在 PATH 时抛清晰错误

## CLI 用法示例

```bash
# intersect：peaks ∩ 基因体 / 反选黑名单
python main.py intersect -a peaks.bed -b genes.bed -wa -wb
python main.py intersect -a peaks.bed -b blacklist.bed -v > peaks.clean.bed

# merge / coverage / genomecov
python main.py merge -i peaks.bed -d 100 > peaks.merged.bed
python main.py coverage -a targets.bed -b sample.bam -counts > targets.cov.txt
python main.py genomecov -i sample.bam -g hg38.genome -bg > sample.cov.bg

# bamtobed / getfasta
python main.py bamtobed -i sample.bam > sample.bed
python main.py getfasta -fi hg38.fa -bed peaks.bed -name -s > peaks.fa

# 自省
python main.py --list-commands
python main.py --schema
```

## 实战示例（区间运算典型流程）

以下为原生 bedtools CLI 的典型用法；等价能力由 `native/main.py` 的子命令提供（见上「CLI 用法示例」）。

### 1. ChIP-seq peaks 处理：黑名单过滤 → 合并 → 注释

```bash
# 1) 去除黑名单重叠（-v 反选）
bedtools intersect -a raw_peaks.bed -b hg38.blacklist.bed -v > peaks.clean.bed
# 2) 合并相邻峰（间距 ≤ 100 bp 合并）
bedtools merge -i peaks.clean.bed -d 100 > peaks.merged.bed
# 3) 与基因体注释求交并输出两端原区间
bedtools intersect -a peaks.merged.bed -b genes.bed -wa -wb > peaks.annot.tsv
```

### 2. 覆盖度与深度（batch QC）

```bash
# 每个目标区间内的 reads 计数（panel/捕获 QC 常用）
for s in sampleA sampleB; do
  bedtools coverage -a capture_targets.bed -b ${s}.bam -counts > ${s}.target_cov.txt
done
# 全基因组深度 bedGraph（IGV 可视化 / 后续 callpeak 输入）
bedtools genomecov -ibam sampleA.bam -g hg38.genome -bg > sampleA.cov.bg
```

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-a A -b B` | 主文件与对照文件（B 可多个；文件可 .gz；支持 BED/BAM/VCF/GFF） |
| `-v` | 反选：输出 A 中不与 B 重叠的区间 |
| `-wa` / `-wb` | 输出原 A 区间 / 同时输出重叠的 B 区间 |
| `-loj` | 左外连接（A 每条都输出，无重叠时 B 列以 `.` 填充） |
| `-f 0.x` | 最小重叠比例（默认 1E-9 即 >0bp 即算重叠；`-F` 为对 B 的比例） |
| `merge -d N` | 间隔 ≤ N bp 的相邻区间合并；`-s` 按链合并 |
| `coverage -counts` | 输出每区间重叠 reads 数（默认逐碱基深度） |
| `genomecov -bg` | bedGraph 输出；`-ibam` 直读 BAM（genome 文件仍必需） |
| `bamtobed -cigar` | 保留 CIGAR（对 spliced reads 处理必需） |
| `getfasta -fi ref -bed x` | 按区间取序列；`-s` 按链取反互补、`-name` 用区间名作头 |
| `subtract -A` | 移除 A 中与 B 有任何重叠的整条区间 |

> 输入须按染色体排序时先 `bedtools sort`（或 `sort -k1,1 -k2,2n`）；`-sorted` 优化需确认排序。

### 4. 常用子命令速查（基因组区间运算主力）

| 命令 | 说明 |
| ---- | ---- |
| `intersect` | 求两个文件的交集（区间重叠；`-v` 反选、`-wa/-wb` 输出原区间） |
| `merge` | 合并重叠/相邻的区间（`-d` 允许间距、`-s` 按链） |
| `closest` | 查找最近的特征（无重叠时的最近邻） |
| `coverage` | 计算覆盖度（每区间内 reads 深度/计数） |
| `genomecov` | 计算全基因组覆盖度（逐位点/bedGraph/histogram） |
| `bamtobed` | BAM 转 BED 格式 |
| `nuc` | 计算核酸组成（GC 含量等；按区间统计序列构成） |
| `sort` | 排序 BED 文件（按染色体/坐标） |

> 常用子命令 30+；实际使用时以官方文档为准（<https://bedtools.readthedocs.io/>）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 bedtools 二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n bedtools -c conda-forge -c bioconda bedtools=2.31.1
conda activate bedtools
bedtools --version   # 断言：bedtools v2.31.1
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install bedtools
bedtools --version   # 断言
# 注：brew 当前 2.31.1，与 meta 登记 2.31.1 一致
```

> 宿主机直跑 `python main.py intersect|...` 推荐用文末「Conda 环境」配方建环境（`name: bedtools-native`）。本模块不维护本地安装脚本：conda/brew/官方源码三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bedtools:2.31.1--h13024bc_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bedtools:2.31.1--h13024bc_3 \
    bedtools intersect -a /data/peaks.bed -b /data/genes.bed -wa -wb > /data/out.tsv
```

> 容器内即 `bedtools` 二进制（单文件）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bedtools）运行 `python main.py`。tag 全列表以 quay 页面为准。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull bedtools.sif docker://depot.galaxyproject.org/singularity/bedtools:2.31.1--h13024bc_3
apptainer run -B $PWD:/data -H /data bedtools.sif \
    bedtools merge -i /data/peaks.bed -d 100 > /data/peaks.merged.bed
```

### 4. 二进制包安装（官方 release：源码编译）

bedtools 官方 release 仅提供源码归档 `bedtools-2.31.1.tar.gz`（无预编译二进制；`make` 编译，依赖 zlib）：

```bash
wget https://github.com/arq5x/bedtools2/releases/download/v2.31.1/bedtools-2.31.1.tar.gz -P ~/software/
tar xzf ~/software/bedtools-2.31.1.tar.gz -C ~/software/
make -C ~/software/bedtools2 -j4
ln -s ~/software/bedtools2/bin/bedtools ~/software/bin/bedtools     # 或写 PATH（用户级，免 root）
```

> 验证安装：`bedtools --version` 应输出 `bedtools v2.31.1`（路径一律用户级 `~/software/`，禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：`modules/nf-core/bedtools/` 含 **23 个子模块**（bamtobed/closest/complement/coverage/flank/genomecov/getfasta/groupby/intersect/jaccard/makewindows/map/merge/multiinter/nuc/shift/shuffle/slop/sort/split/subtract/unionbedg 等；2026-09-09 抓取核实），conda pin `bioconda::bedtools=2.31.1`。

```bash
nf-core modules install nf-core bedtools intersect   # 在用户项目安装官方子模块
# include: { BEDTOOLS_INTERSECT } from './modules/nf-core/bedtools/intersect/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core bedtools <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/bedtools/` 含 **9 个 wrapper**（bamtobed/complement/coveragebed/genomecov/intersect/merge/slop/sort/split；2026-09-09 抓取核实），当前 master `intersect` pin `bedtools=2.31.1` + `htslib=1.24`（未依赖 snakemake-wrapper-utils）。

```python
rule bedtools_intersect:
    input:
        a="peaks/{sample}.bed",
        b="anno/genes.bed"
    output: "intersect/{sample}.tsv"
    params: extra="-wa -wb"
    log: "logs/bedtools/intersect/{sample}.log"
    wrapper: "v9.17.1/bio/bedtools/intersect"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/bedtools/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要真实 bedtools）
```

## 版本

* bedtools **2.31.1**（默认锚点；官方 GitHub release v2.31.1，2023-11-07 实测；bioconda / brew core / nf-core / snakemake-wrappers 均 2.31.1，全渠道一致）
* 上游动态：v2.31.1 为当前最新（2023-11 发布，长期稳定）；上游 2.32+ 未有新 tag
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/bedtools / depot.galaxyproject.org）；本地不再自建容器配方
* bedtools 官方 release 无预编译二进制（源码 `bedtools-2.31.1.tar.gz`，make 编译）

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bedtools native Conda 环境配方（与 native/environment.yml 相同）
# 说明：官方镜像（quay.io/biocontainers/bedtools）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def。
name: bedtools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bedtools=2.31.1
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/bedtools/overview>（2.31.1 等；linux-64/osx-64/linux-aarch64/osx-arm64）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/bedtools:2.31.1--h13024bc_3`（同版另有 `2.31.1--hf5e1c6e_2/_1`，以 quay 实时为准）
* **Singularity**：<https://depot.galaxyproject.org/singularity/bedtools%3A2.31.1--h13024bc_3>
* **GitHub 官方仓库**：<https://github.com/arq5x/bedtools2>（releases：v2.31.1 源码 tar.gz）
* 安装方式（本地）：`mamba create -n bedtools -c conda-forge -c bioconda bedtools=2.31.1`；或 `brew install bedtools`

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* bedtools 早期文档（2.27 及更早）常见源码安装到 `/opt/biosoft/bedtools2/` 后 `export PATH`；归档时统一改用户级前缀。
* 旧版 `intersect` 无 `-sorted`/`-header` 等增强选项（2.28+ 加入）；`-loj` 行为一致。genomecov 的 `-ibam` 直读 BAM 写法与 `-i`（需先转 BED）并存，旧教程多用 `-i x.bam` 的兼容别名。
* 文档中 `/home/train/...` 教学固定路径为历史残留，不再沿用。
