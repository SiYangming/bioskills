# samtools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# samtools / native

samtools 是处理 SAM/BAM/CRAM 比对结果的核心工具集，支持排序、索引、查看、格式转换、统计、提取与 mpileup 变异检测等操作，是测序数据分析中最常用的工具之一、绝大多数 NGS 流程的底座（官网：<https://www.htslib.org/>）。本目录为自包含的 samtools 驱动实现（`source_type: custom`）。

## 能力

覆盖 samtools 高频子命令，自动注入线程与临时目录优化：

| 子命令          | 说明                 | 线程 |
| ------------ | ------------------ | -- |
| `view`       | SAM/BAM/CRAM 互转与过滤 | ✅  |
| `sort`       | 坐标 / read name 排序  | ✅  |
| `index`      | 建立 bai/csi 索引      | —  |
| `flagstat`   | flag 统计            | —  |
| `idxstats`   | 按参考序列统计            | —  |
| `stats`      | 全量统计报告             | —  |
| `depth`      | 测序深度               | —  |
| `mpileup`    | pileup 生成          | ✅  |
| `faidx`      | FASTA 索引           | —  |
| `merge`      | 合并 BAM             | ✅  |
| `quickcheck` | 完整性校验              | —  |

## 快速开始

> 安装 samtools 的四种方式（conda / docker / apptainer / 源码编译）见下方「环境安装」节；以下 CLI 与自省命令在宿主机已装工具的环境执行。

### 1. CLI 调用

```bash
python main.py view -bS input.sam -o out.bam --threads 8
python main.py sort input.bam -o sorted.bam --threads 8
python main.py index sorted.bam
python main.py flagstat sorted.bam
python main.py faidx refs.fa
```

### 2. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 3. 测试

```bash
bash test/run_test.sh
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑（容器内只含 samtools，无 python 驱动）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n samtools-native -c conda-forge -c bioconda samtools=1.21
conda activate samtools-native
samtools --version    # 验证
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 1.24，与 meta 登记 1.21 略有差异（版本以 formula 为准）
brew install samtools
samtools --version   # 断言
```

> 完整离线配方（含 python=3.11 / pyyaml / htslib，可另存为 samtools-native.yml（离线兜底），在线直接 mamba create -n samtools-native -c conda-forge -c bioconda samtools=1.21）见文末「Conda 环境」节（name: samtools-native）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/samtools:1.21--h96c455f_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/samtools:1.21--h96c455f_1 \
    sort /data/input.bam -o /data/sorted.bam --threads 8
```

容器内为原生 samtools 入口；需要 Schema/自省/参数注入时在**宿主机**（conda env 装 samtools）运行 `python main.py <subcommand> ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换；等价直链见文末「容器与 Conda 链接」）：

```bash
apptainer pull samtools.sif docker://depot.galaxyproject.org/singularity/samtools:1.21--h96c455f_1
apptainer run -B "$PWD":/data -H /data samtools.sif sort /data/input.bam -o /data/sorted.bam --threads 8
```

### 4. 二进制包安装（官方源码编译，无 conda / docker 依赖）

* **官网/下载页**：<https://www.htslib.org/download/>

* **GitHub release**：<https://github.com/samtools/samtools/releases>

samtools 官方以源码形式分发（无预编译二进制），release 源码包不捆绑 htslib，需先安装 htslib（同下载页 htslib-1.21 源码按同样 configure/make 流程安装，或 conda 安装）再编译：

```bash
wget https://github.com/samtools/samtools/releases/download/1.21/samtools-1.21.tar.bz2 -P ~/software/
cd ~/software && tar jxf samtools-1.21.tar.bz2 && cd samtools-1.21
./configure --prefix=$HOME/software/samtools-1.21 && make -j 8 && make install
echo 'export PATH=$PATH:$HOME/software/samtools-1.21/bin' >> ~/.bashrc
source ~/.bashrc

# 验证安装
samtools --version
```

## 性能优化约定

* **线程**：`sort` 默认 8 线程（CPU 密集），其他默认 4；用户显式 `--threads` 永远优先。

* **临时目录**：`sort` 自动使用 `$TMPDIR` 下的临时前缀，避免污染工作目录。

* **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## SAM 格式速查（读取 / 处理 SAM 前置知识）

SAM（The Sequence Alignment/Map format）为序列比对文件格式；详细规范见
`http://samtools.github.io/hts-specs/SAMv1.pdf`。SAM 由**头部区**与**主体区**
两部分组成，均以 tab 分列。比对工具（bowtie、tophat 等）产出的 SAM 记录比对
结果，后续常需用 samtools 对其排序/过滤/转换，故先掌握格式：

**头部区**（以 `@` 开头，记录总体信息：比对软件、参考序列、格式版本等）：

```
@HD VN:1.0 SO:unsorted
    头部第一行：VN 为格式版本；SO 表示排序类型——unknown(默认)/unsorted/queryname/
    coordinate。注意：samtools sort 后不自动更新 BAM 的 SO 值，picard 会更新。
@SQ SN:A.auricula_all_contig_1 LN:9401
    参考序列（决定排序顺序）。SN 参考序列名；LN 参考序列长度。
@RG ID:sample01
    Read Group：1 个 sample 的测序结果=1 个 Read Group（可含多个 library）。
    数据编号信息记录于此；GATK 要求输入 SAM 必须含 @RG。
@PG ID:bowtie2 PN:bowtie2 VN:2.0.0-beta7
    生成该 SAM 的比对软件（程序记录）。
```

**主体区**（每比对一行，11 个主列 + 1 个可选列）：

| 列号 | 列名 | 说明 |
| ---- | ---- | ---- |
| 1 | QNAME | 比对的序列名 |
| 2 | FLAG | Bitwise FLAG（表明比对类型：pairing、strand、mate strand 等） |
| 3 | RNAME | 比对上的参考序列名 |
| 4 | POS | 1-based 比对最左侧定位 |
| 5 | MAPQ | 比对质量 |
| 6 | CIGAR | Extended CIGAR string（操作符 MIDNSHP） |
| 7 | MRNM | 匹配另一端 read 所比对的参考序列名（`*` 未配对） |
| 8 | MPOS | 1-based leftmost Mate Position |
| 9 | ISIZE | 插入片段长度 |
| 10 | SEQ | 与参考同链的比对序列（`*` 未存储） |
| 11 | QUAL | 序列质量（ASCII-33 = Phred base quality） |
| 12 | 可选列 | `TAG:TYPE:VALUE` 形式提供额外信息 |

**第 2 列 FLAG 位值速查**（`samtools view -f/-F` 筛选即按这些位组合）：

| FLAG 值 | 含义 |
| ------ | ---- |
| 1 | 该 read 是 paired reads 中的一个 |
| 2 | Paired reads 中每个都正确比对到参考序列 |
| 4 | 该 read 未比对到参考序列 |
| 8 | 与之配对的另一端 read 未比对到参考序列 |
| 16 | 该 read 与参考序列反向互补 |
| 32 | 与之配对的另一端 read 反向互补 |
| 64 | Paired reads 中该 read 是第 1 条 |
| 128 | Paired reads 中该 read 是第 2 条 |
| 256 | 次优比对结果 |
| 512 | 未通过质量控制 |
| 1024 | PCR 重复或光学重复 |

## 实战示例

比对、变异检测类流程中常见的 SAM/BAM 操作套路如下。命令为软件原生 CLI；其中 `tview` 等未封装进 `main.py` 的命令按需直接调用原生 `samtools`，`sort` / `index` / `view` / `flagstat` / `depth` / `mpileup` / `faidx` / `merge` 的等价能力已由 `native/main.py` 覆盖（见上「能力」与「快速开始」）。

### 1. 比对后处理基本操作（SAM → 排序 BAM → 索引 → 查看 / 过滤）

```bash
# SAM 转 BAM 并按坐标排序（-@ 线程数；-O 输出格式）
samtools sort -@ 8 -o sample1.bam -O BAM sample1.sam
samtools sort -@ 8 -o sample2.bam -O BAM sample2.sam

# 为排序后的 BAM 建立索引（生成 .bai 文件）
samtools index sample1.bam
samtools index sample2.bam

# 查看特定区域的比对结果（header + alignments）
samtools view -h sample1.bam chr1:10000-20000 | less -S

# 提取指定区域（此处为整条 chr1）的比对并另存为 BAM
samtools view -h -b sample1.bam chr1 > sample1.chr1.bam

# 按 FLAG 过滤：-f 64 取双端第一条 reads，再接 -F 4 排除未比对 reads
samtools view -h -f 64 sample1.bam | samtools view -h -F 4 | less
```

### 2. 提取参考序列与比对统计

```bash
# 从参考 FASTA 提取指定区域序列（自动建立 .fai 索引）
samtools faidx genome.fa chr1:40000-42000 | less

# 比对率统计（flag 统计）
samtools flagstat sample1.bam

# 逐位点覆盖深度
samtools depth sample1.bam > sample1.depth.txt

# mapping quality（MAPQ）分布（SAM 第 5 列）
samtools view sample1.bam | awk '{print $5}' | sort | uniq -c | sort -k2 -n

# 交互式文本比对查看（tview 为原生 CLI；BAM 与参考 FASTA 均需先建索引）
samtools tview sample1.bam genome.fa
```

### 3. 基于 mpileup 的轻量变异检测（Samtools + bcftools）

```bash
# 一步完成：samtools mpileup 汇总多样品比对 → bcftools call 调用变异（bcftools 需另行安装）
samtools mpileup -ugf genome.fa sample1.bam sample2.bam | bcftools call -vm > variants.vcf

# 变异过滤（bcftools 自带脚本）
vcfutils.pl varFilter variants.vcf > variants.filter.vcf
```

mpileup 参数说明：

| 参数                    | 说明                                 |
| --------------------- | ---------------------------------- |
| `-t AD,ADF,ADR,DP,SP` | 输出额外标签信息：等位基因深度、正/负链各自深度、总深度、链偏倚评分 |
| `-g`                  | 直接输出 BCF（二进制 VCF）                  |
| `-f`                  | 参考基因组 FASTA                        |
| `-u`                  | 未压缩的 BCF，便于管道接力                    |

> 注：`bcftools call -vm` 中 `-v` = 只输出变异位点，`-m` = multiallelic-caller 模式（适合多样品分析）。Samtools + Bcftools 是快速、轻量的变异检测方案；复杂变异类型（如多等位基因变异）推荐 GATK HaplotypeCaller，或将两路结果取交集提高准确性（GATK 与 samtools 双路联检为常见实践）。

### 4. 多样本 BAM 合并（merge）

基因预测（AUGUSTUS 的 bam2hints、BRAKER 的 `--bam`）与多比对联检等场景，常需先把多个样本的比对结果合并为单个 BAM：

```bash
# 合并多个已排序 BAM，随后统一排序、建索引供下游使用
samtools merge -@ 8 rnaseq.merged.bam sample1.sorted.bam sample2.sorted.bam
samtools sort -@ 8 -o rnaseq.sort.bam rnaseq.merged.bam
samtools index rnaseq.sort.bam
```

### 5. 常用子命令参数速查（比对后处理主力）

| 命令 | 参数 | 说明 |
| ---- | ---- | ---- |
| `sort` | `-@ N` | 使用 N 个线程 |
| `sort` | `-O BAM` | 输出 BAM 格式（`-o out.bam` 显式输出文件；默认写 stdout） |
| `view` | `-h` | 输出含 header 信息（比对结果头部） |
| `view` | `-b` | 输出 BAM（二进制）格式 |
| `view` | `-f 64` | 筛选 flag=64 的 reads（双端测序的第一条；`-f` 需匹配的 flag） |
| `view` | `-F 4` | 排除 flag=4 的 reads（未比对；`-F` 需排除的 flag） |
| `index` | — | 为排序 BAM 建 `.bai/.csi` 索引（view 区域/tview 前置） |
| `tview` | — | 交互式文本可视化比对结果（BAM 与参考 FASTA 均需索引） |
| `faidx` | — | 为 FASTA 文件建立 `.fai` 索引（区域提取 / GATK 前置） |
| `flagstat` | — | 统计比对结果 flag 信息（总数/比对/配对/重复分类） |
| `depth` | — | 统计每个位点的覆盖深度（`-a` 输出零覆盖位点） |

> 速查表来源：比对后处理典型教程参数整理；完整子命令以官方
> `samtools --help` / 手册为准（本表所列命令除 `tview` 外均已被
> `native/main.py` 的等价子命令覆盖，见「能力」节）。

***

## snakemake 实现

# samtools / snakemake（本地规则 + 官方 wrappers 参考）

> 本目录为 snakemake-wrappers 缺失或需要本地定制时的 **Snakemake 自维护 rule**（`source_type: custom`、`type: snakemake_local`），td2 式布局：**每 rule 一个 config 驱动** **`.smk`**。

### 本地拆分规则（td2 式：每 rule 一个 .smk，config 驱动）

| 文件                                  | 规则                    | 作用                                           | 执行指令                                 |
| ----------------------------------- | --------------------- | -------------------------------------------- | ------------------------------------ |
| `snakemake/samtools_sort.smk`       | `samtools_sort`       | BAM/SAM/CRAM → sorted BAM（内存均摊 + 输出目录内临时前缀）  | `script:`（samtools\_sort.py）         |
| `snakemake/samtools_index.smk`      | `samtools_index`      | sorted BAM → `.bai` 索引                       | `script:`（samtools\_index.py）        |
| `snakemake/samtools_view.smk`       | `samtools_view`       | FLAG/MAPQ/region 过滤或格式转换                     | `script:`（samtools\_view\.py）        |
| `snakemake/samtools_sam_to_bam.smk` | `samtools_sam_to_bam` | SAM → BAM（`samtools view -b`，temp 中间产物）      | `script:`（samtools\_sam\_to\_bam.py） |
| `snakemake/samtools_flagstat.smk`   | `samtools_flagstat`   | BAM → flagstat 统计文本                          | `script:`（samtools\_flagstat.py）     |
| `snakemake/alignment_summary.smk`   | `alignment_summary`   | 多 flagstat → Sample/Total/Mapped/Rate 汇总 TSV | `script:`（alignment\_summary.py）     |

* 配套文件（平铺 `snakemake/`，`.smk` 同目录相对引用）：`samtools.yaml`（conda env）、5 个规则 wrapper `samtools_sort.py` / `samtools_index.py` / `samtools_view.py` / `samtools_sam_to_bam.py` / `samtools_flagstat.py`（单命令规则，经两级 `sys.path` 注入共享 `modules/docker_wrapper.py`，按 `config exec_mode` 做 docker/native/conda 三模式分派：docker 用镜像内 samtools（`samtools.docker_image`）、native 用 `samtools.samtools_bin`、conda 走 PATH）与 `alignment_summary.py`（有解析逻辑的 helper）。

* 规则 **config 驱动、可独立运行**（不依赖流程 `samples` / `config["paths"]` / `SAMPLES`），契约见各 `.smk` 头注。独立运行示例：

  ```bash
  snakemake -s modules/samtools/snakemake/samtools_sort.smk \
      --config samtools_sort_input=aln.sam samtools_sort_output=aln.sorted.bam --cores 8 --use-conda
  ```

* 串联：include `samtools_sort.smk` + `samtools_index.smk` 并令 `samtools_index_input == samtools_sort_output` 即自动建立 sort→index 依赖；批量 flagstat 汇总在流程内赋值 `config["alignment_summary_flagstats"] = [...]` 后 include `alignment_summary.smk`。

* samtools 子命令规则（`sort` / `index` / `view` / `sam_to_bam` / `flagstat` / `alignment_summary`）按上述单规则文件组织（无 `scripts/`、`envs/`、`../` 幽灵引用）。

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> 本模块**不重写官方 wrapper 源码**。官方仓库 `bio/samtools/` 提供 sort/index/view/flagstat 等 wrapper（软件级 `software_versions.samtools_snakemake_wrappers` 记录 `wrapper_tag`、samtools pin 与差异）；离线/私有环境缺失或需本地定制时用上方 `snakemake/samtools_*.smk` 本地规则兜底。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# samtools native Conda 环境配方
# 离线兜底：可另存为 samtools-native.yml 后 mamba env create -f samtools-native.yml；在线推荐上方 mamba create 直装命令
name: samtools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - samtools=1.21
  - htslib=1.21
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/samtools/overview>

* **Docker**：`docker pull quay.io/biocontainers/samtools:1.21--h96c455f_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/samtools%3A1.21--h96c455f_1>

* 安装方式（本地）：`mamba create -n samtools -c conda-forge -c bioconda samtools=1.21`

